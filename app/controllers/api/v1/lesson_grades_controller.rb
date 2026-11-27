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

      before_action :load_revision

      # POST /api/v1/lesson-revisions/:revision/grade {answers: [{check: "3.2", answer: "…"}]}
      def create
        body = parse_json_body or return
        answers = body["answers"]
        unless answers.is_a?(Array) && answers.any? && answers.size <= MAX_ANSWERS && answers.all? { |a| a.is_a?(Hash) && a["check"].is_a?(String) && a.key?("answer") && !a["answer"].nil? }
          return refuse("E-FILES", "answers", "send {answers: [{check: ID, answer: …}]}: between 1 and #{MAX_ANSWERS} answers, each with the check id and the answer",
                        "banco lesson grade #{@revision.id} --check 1.2 --answer \"…\"", 422)
        end
        answers.each_with_index do |a, i|
          next if locate(a["check"])

          return refuse("E-NOT-FOUND", "answers/#{i}/check", "revision #{@revision.id} has no check #{a['check'].first(30).inspect}: its checks are #{check_ids.join(', ')}",
                        "a check id is CARD.BLOCK, CARD.BLOCK.stepN, CARD.BLOCK.exN or CARD.BLOCK.exN.P (the n of the card and the block in the lesson)", 404, checks: check_ids)
        end

        render json: { revision_id: @revision.id, lesson: @revision.lesson.key, read_only: true, results: answers.map { |a| grade_one(a) },
                       next: "nothing was stored: no answer, no event; to file a finding quote the verdict and the matched value" }
      end

      private

      def grade_one(given)
        locator = locator_of(given["check"])
        located = answerer.located(locator)
        check = located.check
        id_map = Lessons::Checks.id_map(check, located.seed)
        response = sequence_ids(check, given["answer"], id_map)
        graded = Lessons::Checks.grade(check, response, id_map, subject: @revision.body["subject"])
        reply = Lessons::CheckAnswer.new(@revision, student_key: "preview", trial_try: 1).call(locator, response)
        out = { check: given["check"], component: check["component"], answer: given["answer"], verdict: graded.verdict, matched: matched(check, graded, response, id_map),
                error_code: (graded.code unless graded.invalid?), error_index: graded.error_index, normalized: graded.normalized,
                message: reply.body.select { |k, _| k.to_s.start_with?("message") || k.to_s == "tr" }.presence,
                shown_order: Lessons::Checks.rekey(check, located.seed).shown_order.presence }
        out[:invalid_code] = graded.code if graded.invalid?
        out.compact
      end

      # The answer to a tiles or an ordering check, as the student's page sends it: a list of the SHOWN ids (e1..eN, `shown_order`) in the order built. The
      # reader also takes the check's own tile ids (the `id` of each tile, as the lesson file names them), as a JSON list, a JSON text of one or a list written
      # «a,b,c» or «a b c»: they are turned into the shown ids of the preview's shuffle. The shown ids win where both could be meant (a tile that is
      # itself called e1); a list that is neither stays as sent and the grader says it cannot be read.
      def sequence_ids(check, answer, id_map)
        return answer unless %w[tiles ordering].include?(check["component"])

        ids = id_list(answer) or return answer
        return ids if ids.all? { |id| id_map.key?(id) }

        shown = id_map.invert
        ids.all? { |id| shown.key?(id) } ? ids.map { |id| shown[id] } : ids
      end

      def id_list(answer)
        list = answer.is_a?(String) ? text_ids(answer) : answer
        list if list.is_a?(Array) && list.any? && list.all?(String)
      end

      def text_ids(text)
        return text.split(/[\s,]+/).reject(&:empty?) unless text.lstrip.start_with?("[")

        JSON.parse(text)
      rescue JSON::ParserError
        nil
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
    end
  end
end
