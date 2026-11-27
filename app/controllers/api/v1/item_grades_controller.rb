module Api
  module V1
    # Read-only grading of answers to the stored instances of an item revision, for the reviewer and the blind solver (`banco item grade REV --instance N --answer "…"`,
    # D-402 round 8). A reviewer who infers from the accept list that an answer is refused is often wrong (contractions, brackets, punctuation, case, accents), so
    # the server says it: each answer goes through exactly the student's path (Grading::Spec.from_instance, then Grading.grade: Grading::Closed or Grading::Expression)
    # and comes back with the verdict, what it matched (the key, an accept entry, a declared error value or the entry a slip is of), the error code and the message the
    # student would read on a first try. Nothing is stored: no attempt, no event, no ledger row. Every token role may ask: it is a POST only because it carries the
    # answers (Api::BaseController reader_grants), it writes nothing.
    class ItemGradesController < Api::BaseController
      include RawAnswer

      self.reader_grants = true

      MAX_ANSWERS = 100

      # The instances of a draft (D-403, round 9): the rows the dry run builds, numbered as `review open` numbers a stored revision's.
      Draft = Struct.new(:instances) do
        def instance_row(number) = number.is_a?(Integer) && number >= 1 ? instances[number - 1] : nil
      end

      before_action :load_revision, only: :create

      # POST /api/v1/item-revisions/:revision/grade {answers: [{instance: N, answer: "…"}]}
      def create
        body = parse_json_body or return
        text = Review::ItemText.new(@revision, all: true)
        grade_answers(text, body["answers"], "banco item grade #{@revision.id}", "revision #{@revision.id}", revision_id: @revision.id, item: @revision.item.key)
      end

      # POST /api/v1/item-grade {files: {"item.json": "…", "generator.mjs": "…"}, answers: [{instance: N, answer: "…"}]} (D-403, round 9): the instances of an item that is not stored
      # yet, so an author tests variants before submitting. The files are read and run as `work submit --dry-run` reads and runs them (Validation::Submission with
      # draft: true, Validation::DryRun): the same instances, in the same order, graded by the student's own path. Nothing is stored and no session is needed:
      # every role may ask. An item the dry run refuses is refused here with its findings.
      def file
        body = parse_json_body or return
        submission = Validation::Submission.new(key: nil, base: nil, files: body["files"], session: nil, draft: true).prepare!
        result = Validation::DryRun.call(submission.subject, submission.files)
        unless result.passed? || waiting_for_verifier?(result)
          first = result.findings.errors.first
          return refuse(first.code, first.field, first.message, "fix the files and run banco work submit DIR --dry-run again", 422, codes: result.codes, findings: result.findings.map(&:to_h))
        end

        draft = Draft.new(instances_of(submission, result))
        grade_answers(draft, body["answers"], "banco item grade --file DIR", "the item", draft: true)
      rescue Validation::Submission::Refused => e
        refuse(e.code, e.field, e.message, e.next_step, e.http)
      rescue Validation::ChromeRunner::Busy
        refuse("E-CHROME-BUSY", "chrome", "Chrome is busy", "retry in 30 s", 409)
      rescue Validation::ChromeRunner::Unavailable, Validation::ChromeRunner::Timeout, Validation::Roundtrip::Unavailable => e
        refuse("E-CHROME-UNAVAILABLE", "chrome", "Chrome or the grader did not answer: #{e.message.first(120)}", "retry in 30 s; banco health", 503)
      end

      private

      def grade_answers(text, answers, command, what, **head)
        unless answers.is_a?(Array) && answers.any? && answers.size <= MAX_ANSWERS && answers.all? { |a| a.is_a?(Hash) && a["instance"].is_a?(Integer) && a.key?("answer") && !a["answer"].nil? }
          return refuse("E-FILES", "answers", "send {answers: [{instance: N, answer: …}]}: between 1 and #{MAX_ANSWERS} answers, each with the instance number and the answer",
                        "#{command} --instance 1 --answer \"…\"", 422)
        end
        answers.each_with_index do |a, i|
          next if text.instance_row(a["instance"])

          return refuse("E-NOT-FOUND", "answers/#{i}/instance", "#{what} has no instance #{a['instance']} (it has #{text.instances.size}: 1-#{text.instances.size})",
                        "banco review open #{head[:revision_id] || 'REV'}", 404)
        end

        results = answers.map { |a| grade_one(text, a) }
        render json: { **head, read_only: true, results: results,
                       next: "nothing was stored: no attempt, no event; to file a finding quote the verdict and the matched value" }.compact
      rescue Grading::Expression::Unavailable => e
        refuse("E-CHROME-UNAVAILABLE", "grader", "the expression grader did not answer: #{e.message.first(120)}", "retry in 30 s; banco health", 503)
      end

      # In-memory instance rows of a draft, with the columns the grader reads (display, answer, errors, solution, accept, hints), as the job would have stored them.
      def instances_of(submission, result)
        revision = ItemRevision.new(body_json: submission.files.fetch("item.json"))
        result.instances.map do |i|
          ItemInstance.new(item_revision: revision, seed: i[:seed], display_json: JSON.generate(i[:display]), answer_json: JSON.generate(i[:answer]),
                           errors_json: (JSON.generate(i[:errors]) unless i[:errors].nil?), solution_json: (JSON.generate(i[:solution]) unless i[:solution].nil?),
                           accept_json: (JSON.generate(i[:accept]) if i[:accept].present?), hints_json: (JSON.generate(i[:hints]) if i[:hints].present?))
        end
      end

      def waiting_for_verifier?(result)
        result.codes.any? && (result.codes - ItemValidation::WAITING_FOR_VERIFIER).empty?
      end

      def grade_one(text, given)
        row = text.instance_row(given["instance"])
        spec = Grading::Spec.from_instance(row)
        raw = raw_answer(given["answer"], testlet: spec.component == "testlet")
        result = Grading.grade(row, raw, source: "text")
        out = { instance: given["instance"], answer: given["answer"], verdict: result.verdict, matched: matched(spec, result),
                error_code: result.error_codes.first, error_codes: result.error_codes, form_violations: result.form_violations, normalized: result.normalized }
        out[:invalid_code] = result.invalid_code if result.invalid?
        out[:observation] = result.observation if result.observation
        out[:answer_part] = result.answer_part if result.answer_part
        out.merge(student_sees(row, spec, result, raw).compact)
      end

      # What the grader matched: the one it recorded (normalized_text), else the key of a right answer or the declared error value of a typical error.
      def matched(spec, result)
        return result.matched if result.matched

        case result.verdict
        when "correct", "nearly_correct" then spec.answer.nil? ? nil : { kind: "key", value: spec.answer }
        when "typical_error"
          code = result.error_codes.first
          value = spec.error_values.find { |c, _| c == code }&.last
          value.nil? ? nil : { kind: "error", value: value, code: code }
        end
      end

      # The outcome of the practice engine on a first, unaided try and the sentence the student reads for it: the same Practice::Messages the page uses (the catalogue
      # message of the error in the language the item teaches and its Italian, else the page's own sentence). An answer that cannot be read is not a try: its message.
      def student_sees(row, spec, result, raw)
        return { message_it: result.message_it } if result.invalid?

        key = Grading::Evidence.key(verdict: result.verdict, spec: spec, error_codes: result.error_codes, method: result.grading_method)
        return {} unless Practice::Outcome.try?(key)

        near = Practice::Instances.near_kind(spec, key, result.normalized.presence || raw)
        outcome = Practice::Outcome.call(evidence_key: key, aided: false, near: near)
        code = result.error_codes.first
        message = Practice::Messages.feedback_keys(outcome, code && Practice::Instances.catalogue_entry(row, code), violations: result.form_violations, near: near)
        note = [ Practice::Messages.note(key, violations: result.form_violations, pair_note: key == "nearly_correct" ? Grading::PairNote.line(spec.display, result.normalized) : nil),
                 result.observation == "full_sentence" ? Practice::Messages.full_sentence_note(result.answer_part) : nil ].compact.join(" ").presence
        { outcome: outcome.to_s, **message, note_it: note }
      end

      def load_revision
        @revision = ItemRevision.find_by(id: params[:revision])
        return if @revision

        refuse("E-NOT-FOUND", "revision", "no item revision #{params[:revision].to_s.first(20).inspect}", "banco work open ITEM", 404)
      end
    end
  end
end
