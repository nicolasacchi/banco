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

      before_action :load_revision

      # POST /api/v1/item-revisions/:revision/grade {answers: [{instance: N, answer: "…"}]}
      def create
        body = parse_json_body or return
        answers = body["answers"]
        unless answers.is_a?(Array) && answers.any? && answers.size <= MAX_ANSWERS && answers.all? { |a| a.is_a?(Hash) && a["instance"].is_a?(Integer) && a.key?("answer") && !a["answer"].nil? }
          return refuse("E-FILES", "answers", "send {answers: [{instance: N, answer: …}]}: between 1 and #{MAX_ANSWERS} answers, each with the instance number and the answer",
                        "banco item grade #{@revision.id} --instance 1 --answer \"…\"", 422)
        end
        text = Review::ItemText.new(@revision, all: true)
        answers.each_with_index do |a, i|
          next if text.instance_row(a["instance"])

          return refuse("E-NOT-FOUND", "answers/#{i}/instance", "revision #{@revision.id} has no instance #{a['instance']} (it has #{text.instances.size}: 1-#{text.instances.size})",
                        "banco review open #{@revision.id}", 404)
        end

        results = answers.map { |a| grade_one(text, a) }
        render json: { revision_id: @revision.id, item: @revision.item.key, read_only: true, results: results,
                       next: "nothing was stored: no attempt, no event; to file a finding quote the verdict and the matched value" }
      rescue Grading::Expression::Unavailable => e
        refuse("E-CHROME-UNAVAILABLE", "grader", "the expression grader did not answer: #{e.message.first(120)}", "retry in 30 s; banco health", 503)
      end

      private

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
