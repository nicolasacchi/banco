module Api
  module V1
    # Read-only grading of answers to the inline checks and the «Prova tu»/«Try it» exercises of a banco.lesson/2 revision, for the lesson reviewer
    # (`banco lesson grade REV --check ID --answer "…"`, D-402 round 8). The check is graded by Lessons::Checks.grade and answered by Lessons::CheckAnswer with the
    # seed "preview" and no student, as the teacher's preview does: the shuffle of a choice, a matching or tiles is the preview's (`shown_order` says it), nothing is
    # recorded (no lesson_events row) and no try counts. Every token role may ask: a POST only because it carries the answers (Api::BaseController reader_grants).
    #
    # A check id is its place in the lesson: CARD.BLOCK for a check or an oral block, CARD.BLOCK.stepN for the blank of step N of a faded example, CARD.BLOCK.exN
    # for the check of exercise N of a «Prova tu» block, CARD.BLOCK.exN.P for its part P. The numbers are the `n` of the card and the block in the body.
    class LessonGradesController < Api::BaseController
      self.reader_grants = true

      MAX_ANSWERS = 100
      CHECK_ID = /\A(\d+)\.(\d+)(?:\.(?:step(\d+)|ex(\d+)(?:\.(\d+))?))?\z/
      ID_KINDS = %w[lesson shown].freeze

      before_action :load_revision, only: :create

      # POST /api/v1/lesson-revisions/:revision/grade {answers: [{check: "3.2", answer: "…"}]}
      def create
        body = parse_json_body or return
        grade_answers(body["answers"], "banco lesson grade #{@revision.id}", "revision #{@revision.id}")
      end

      # POST /api/v1/lesson-grade {files: {"lesson.md": "…"}, answers: [{check: "3.2", answer: "…"}]} (D-403, round 9): the checks of a lesson that is not stored yet, so
      # an author tests variants before submitting. The body is built as `lesson submit --dry-run` builds it (Validation::LessonChecks); nothing is stored, no
      # session is needed, and every role may ask. A lesson with findings is refused as the dry run refuses it.
      def file
        body = parse_json_body or return
        @revision = draft_revision(body["files"]) or return
        grade_answers(body["answers"], "banco lesson grade --file lesson.md", "the lesson")
      end

      private

      def grade_answers(answers, command, what)
        unless answers.is_a?(Array) && answers.any? && answers.size <= MAX_ANSWERS && answers.all? { |a| valid_answer?(a) }
          return refuse("E-FILES", "answers", "send {answers: [{check: ID, answer: …}]}: between 1 and #{MAX_ANSWERS} answers, each with the check id and the answer (and, for a tiles, ordering or matching check, " \
                        "optionally ids: \"lesson\" or \"shown\")", "#{command} --check 1.2 --answer \"…\"", 422)
        end
        answers.each_with_index do |a, i|
          next if locate(a["check"])

          return refuse("E-NOT-FOUND", "answers/#{i}/check", "#{what} has no check #{a['check'].first(30).inspect}: its checks are #{check_ids.join(', ')}",
                        "a check id is CARD.BLOCK, CARD.BLOCK.stepN, CARD.BLOCK.exN or CARD.BLOCK.exN.P (the n of the card and the block in the lesson)", 404, checks: check_ids)
        end

        render json: { revision_id: @revision.id, draft: (true unless @revision.persisted?), lesson: @revision.lesson.key, read_only: true, results: answers.map { |a| grade_one(a) },
                       next: "nothing was stored: no answer, no event; to file a finding quote the verdict and the matched value" }.compact
      end

      def valid_answer?(given)
        given.is_a?(Hash) && given["check"].is_a?(String) && given.key?("answer") && !given["answer"].nil? && (given["ids"].nil? || ID_KINDS.include?(given["ids"]))
      end

      def grade_one(given)
        locator = locator_of(given["check"])
        located = answerer.located(locator)
        check = located.check
        id_map = Lessons::Checks.id_map(check, located.seed)
        response = sequence_ids(check, given, id_map)
        graded = Lessons::Checks.grade(check, response, id_map, subject: @revision.body["subject"])
        reply = Lessons::CheckAnswer.new(@revision, student_key: "preview", trial_try: 1).call(locator, response)
        out = { check: given["check"], component: check["component"], answer: given["answer"], verdict: graded.verdict, matched: matched(check, graded, response, id_map),
                error_code: (graded.code unless graded.invalid?), error_index: graded.error_index, normalized: graded.normalized,
                message: message_fields(check, graded, reply),
                shown_order: Lessons::Checks.rekey(check, located.seed).shown_order.presence }
        out[:invalid_code] = graded.code if graded.invalid?
        out.compact
      end

      # The answer to a tiles, ordering or matching check, as the student's page sends it: the SHOWN ids (e1..eN, l1..lN and r1..rN of the preview's shuffle, `shown_order`).
      # The reader also takes the check's own ids, as the lesson file names them, and turns them into the shown ids of the preview's shuffle: for tiles and ordering a list
      # (a JSON list, a JSON text of one, or «a,b,c» / «a b c»), for matching the object {left id => right id} (an object or its JSON text). The shown ids win where both
      # could be meant (a tile called e1, a matching written with l1/r1 ids): the member `ids` of the answer says which it is, "lesson" or "shown". A list or an
      # object that is neither stays as sent and the grader says it cannot be read.
      def sequence_ids(check, given, id_map)
        answer = given["answer"]
        case check["component"]
        when "tiles", "ordering" then tile_ids(answer, id_map, given["ids"])
        when "matching" then pair_ids(answer, id_map, given["ids"])
        else answer
        end
      end

      def tile_ids(answer, id_map, kind)
        ids = id_list(answer) or return answer
        return ids if kind == "shown" || (kind.nil? && ids.all? { |id| id_map.key?(id) })

        shown = id_map.invert
        ids.all? { |id| shown.key?(id) } ? ids.map { |id| shown[id] } : ids
      end

      def pair_ids(answer, id_map, kind)
        pairs = id_pairs(answer) or return answer
        left = column(id_map, "l")
        right = column(id_map, "r")
        return pairs if kind == "shown" || (kind.nil? && pairs.all? { |l, r| left.key?(l) && (r.empty? || right.key?(r)) })

        shown_left = left.invert
        shown_right = right.invert
        return answer unless pairs.all? { |l, r| shown_left.key?(l) && (r.empty? || shown_right.key?(r)) }

        pairs.to_h { |l, r| [ shown_left[l], r.empty? ? r : shown_right[r] ] }
      end

      # {shown id => stored id} of one column of a matching (l1..lN or r1..rN).
      def column(id_map, prefix) = id_map.select { |shown, _| shown.start_with?(prefix) }

      def id_pairs(answer)
        pairs = answer.is_a?(String) && answer.lstrip.start_with?("{") ? parse_json(answer) : answer
        pairs if pairs.is_a?(Hash) && pairs.any? && pairs.all? { |l, r| l.is_a?(String) && r.is_a?(String) }
      end

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError
        nil
      end

      def id_list(answer)
        list = answer.is_a?(String) ? text_ids(answer) : answer
        list if list.is_a?(Array) && list.any? && list.all?(String)
      end

      def text_ids(text)
        return text.split(/[\s,]+/).reject(&:empty?) unless text.lstrip.start_with?("[")

        parse_json(text)
      end

      # The message a wrong answer gets, named by language (D-403, round 9): `message_<lang>` is the text of the language the lesson teaches (message_es, message_en)
      # and `message_it` its Italian, as the student reads them; a check with only an Italian message (or a generic one) has `message_it` alone.
      def message_fields(check, graded, reply)
        lang = Lessons::StudentBody.lang_of(@revision.body)
        entry = graded.error_index && check["errors"].to_a[graded.error_index]
        if lang && entry && Lessons::Lang.pair?(entry, "message")
          { "message_#{lang}" => entry["message_#{lang}"], "message_it" => entry["message_it"] }.compact
        else
          reply.body.slice(:message_it).transform_keys(&:to_s).presence
        end
      end

      # What the grader matched: a right answer the key, or the accept entry that is right alone; a wrong one the declared error answer
      # (with its code) or the accent/apostrophe slip it is of.
      def matched(check, graded, response, id_map)
        if graded.right?
          entry = ([ check["answer"] ] + check["accept"].to_a).find { |e| right_alone?(check, e, response, id_map) }
          return nil if entry.nil?

          { kind: entry == check["answer"] ? "key" : "accept", value: entry }
        elsif graded.wrong? && graded.error_index
          { kind: "error", value: check["errors"][graded.error_index]["answer"], code: graded.code }
        elsif graded.wrong? && graded.code
          { kind: "slip", code: graded.code }
        end
      end

      # Is the response right when this entry alone is the answer (and nothing is accepted besides)?
      def right_alone?(check, entry, response, id_map)
        Lessons::Checks.grade(check.merge("answer" => entry, "accept" => nil), response, id_map, subject: @revision.body["subject"]).right?
      end

      def answerer = @answerer ||= Lessons::CheckAnswer.new(@revision, student_key: "preview", trial_try: 1)

      def locator_of(id)
        m = CHECK_ID.match(id) or return nil
        { card: m[1].to_i, block: m[2].to_i, step: m[3]&.to_i, ex: m[4]&.to_i, part: m[5]&.to_i }.compact
      end

      def locate(id)
        locator = locator_of(id)
        locator && answerer.located(locator)
      end

      # Every id of the lesson that this endpoint grades.
      def check_ids
        @check_ids ||= Array(@revision.body["cards"]).flat_map do |card|
          Array(card["blocks"]).flat_map do |block|
            base = "#{card['n']}.#{block['n']}"
            case block["type"]
            when "check", "oral" then [ base ]
            when "example" then Array(block["steps"]).each_with_index.filter_map { |s, i| "#{base}.step#{i + 1}" if s["blank"] }
            when "try"
              Array(block["exercises"]).flat_map do |ex|
                if ex["checks"] then ex["checks"].each_index.map { |p| "#{base}.ex#{ex['n']}.#{p + 1}" }
                elsif ex["check"] then [ "#{base}.ex#{ex['n']}" ]
                else []
                end
              end
            else []
            end
          end
        end
      end

      def load_revision
        @revision = LessonRevision.find_by(id: params[:revision])
        return if @revision&.lesson2?

        refuse("E-NOT-FOUND", "revision", "no banco.lesson/2 revision #{params[:revision].to_s.first(20).inspect}", "banco lessons list --subject KEY", 404)
      end

      # The lesson of a draft, as `lesson submit --dry-run` reads it (the same parse and checks, Validation::LessonChecks), in a revision that is never stored; nil
      # when it was refused (the answer is rendered).
      def draft_revision(files)
        usage = "banco lesson grade --file lesson.md --check 1.2 --answer \"…\""
        unless files.is_a?(Hash) && files.keys == [ "lesson.md" ] && files["lesson.md"].is_a?(String)
          refuse("E-FILES", "files", "send exactly {\"lesson.md\": \"...\"}", usage, 422)
          return nil
        end

        source = Lessons::Parser.normalize(files["lesson.md"])
        unless Lessons::Parser2.schema2?(source)
          refuse("E-FILES", "files/lesson.md", "only a banco.lesson/2 lesson (cards) has checks to grade: the file must declare `schema: banco.lesson/2`", "banco brief show lesson", 422)
          return nil
        end
        limit = Validation::Rules.get(:lesson2, :max_bytes) * 4
        if source.bytesize > limit
          refuse("E-TOO-LARGE", "files/lesson.md", "lesson.md is over #{limit} bytes", "shorten the lesson", 413)
          return nil
        end

        front, = Lessons::Parser.front_matter(source, Validation::Findings.new)
        key = front.is_a?(Hash) ? front["key"].to_s : ""
        subject = Subject.find_by(key: key.split(".", 3)[1].to_s)
        unless subject
          refuse("E-NOT-FOUND", "files/lesson.md", "the front matter key #{key.first(60).inspect} names no subject (a key is such as ripasso.spanish.por-para)", "banco lesson submit DIR --dry-run", 404)
          return nil
        end

        outcome = Validation::LessonChecks.call(source, subject: subject.key, context: Validation::CourseContext.for(subject))
        return nil if refuse_findings(outcome.findings, "fix lesson.md and run banco lesson submit DIR --dry-run (the same checks) until it passes")

        LessonRevision.new(lesson: Lesson.new(subject: subject, key: key), body_json: JSON.generate(outcome.body))
      end
    end
  end
end
