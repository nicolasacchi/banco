module Teacher
  # The evening screen (B-06, operator G): what waits for the teacher's word.
  #
  #   short answers   each with the grader's proposal and the student's text, the quotes
  #                   of the proposal marked in it: confirm, edit or reject
  #   verdicts        answers the grader cannot settle (undetermined, floating point,
  #                   a one-letter slip that counts for nothing until you say so): resolve
  #
  # Read-only; the buttons post decisions (confirm_grade, reject_grade, resolve_attempt).
  class Corrections
    ShortAnswer = Data.define(:attempt, :item_key, :subject, :prompt, :segments, :rubric, :proposal, :points, :model_answer_it, :status)
    Verdict = Data.define(:attempt, :item_key, :subject, :skill, :prompt, :given, :key, :verdict, :error_codes, :near_miss)

    def self.call = new

    def short_answers
      @short_answers ||= attempts.filter_map { |a| short_answer(a) }
    end

    def verdicts
      @verdicts ||= attempts.filter_map { |a| verdict(a) }
    end

    def count = short_answers.size + verdicts.size

    # Splits the normalized text into [[text, marked?], ...] around the quotes.
    def self.segments(text, quotes)
      text = Review::GradeCheck.normalize(text)
      ranges = quotes.compact.filter_map do |quote|
        q = Review::GradeCheck.normalize(quote)
        at = q.empty? ? nil : text.index(q)
        at && (at...(at + q.length))
      end.sort_by(&:begin)
      merged = ranges.each_with_object([]) do |r, out|
        if out.last && r.begin <= out.last.end then out[-1] = (out.last.begin...[ out.last.end, r.end ].max)
        else out << r
        end
      end
      cursor = 0
      parts = []
      merged.each do |r|
        parts << [ text[cursor...r.begin], false ] if r.begin > cursor
        parts << [ text[r], true ]
        cursor = r.end
      end
      parts << [ text[cursor..], false ] if cursor < text.length
      parts.empty? ? [ [ text, false ] ] : parts
    end

    private

    def attempts
      @attempts ||= Attempt.where(context: "diagnosis").includes(:gradings, item_instance: { item_revision: { item: :subject } }).order(:id)
                           .reject { |a| settled?(a) || voided?(a) }
    end

    def decisions
      @decisions ||= Decision.where(kind: %w[confirm_grade reject_grade resolve_attempt void_revision_attempts]).order(:id).map { |d| [ d.kind, JSON.parse(d.payload_json) ] }
    end

    def resolved_attempts = @resolved_attempts ||= decisions.select { |k, _| k == "resolve_attempt" }.map { |_, p| p["attempt_id"].to_i }.to_set
    def confirmed_proposals = @confirmed_proposals ||= decisions.select { |k, _| k == "confirm_grade" }.map { |_, p| p["grade_proposal_id"].to_i }.to_set
    def rejected_proposals = @rejected_proposals ||= decisions.select { |k, _| k == "reject_grade" }.map { |_, p| p["grade_proposal_id"].to_i }.to_set
    def voided_revisions = @voided_revisions ||= decisions.select { |k, _| k == "void_revision_attempts" }.map { |_, p| p["item_revision_id"].to_i }.to_set

    def proposals_by_attempt = @proposals_by_attempt ||= GradeProposal.order(:id).group_by(&:attempt_id)

    def settled?(attempt)
      resolved_attempts.include?(attempt.id) || proposals_by_attempt.fetch(attempt.id, []).any? { |p| confirmed_proposals.include?(p.id) }
    end

    def voided?(attempt) = voided_revisions.include?(attempt.item_instance.item_revision_id)

    def latest(attempt) = attempt.gradings.max_by(&:seq)

    def served_of(attempt) = ItemServed.includes(item_instance: :item_revision).find_by(diagnosis_event_id: attempt.served_event_id)

    def prompt_of(body, instance)
      display = JSON.parse(instance.display_json)
      [ body.dig("prompt", "stem_it"), display["stem_it"], (body["passage_it"] if body["kind"] == "testlet") ].compact.join(" ")
    end

    def short_answer(attempt)
      revision = attempt.item_instance.item_revision
      body = JSON.parse(revision.body_json)
      return nil unless body["kind"] == "short_answer" && latest(attempt)&.verdict == "short_answer"

      proposal = proposals_by_attempt.fetch(attempt.id, []).reject { |p| rejected_proposals.include?(p.id) }.last
      points = proposal ? proposal.points : []
      quotes = points.map { |p| p["quote"] }
      ShortAnswer.new(attempt, revision.item.key, revision.item.subject, prompt_of(body, attempt.item_instance), self.class.segments(attempt.raw, quotes),
                      body["rubric"], proposal, points, body.dig("rubric", "model_answer_it"), proposal ? :proposed : :waiting)
    end

    def verdict(attempt)
      grading = latest(attempt) or return nil
      return nil if grading.verdict == "short_answer"

      spec = Grading::Spec.from_instance(attempt.item_instance)
      return nil unless Grading::Evidence.for_grading(grading, spec) == :pending

      revision = attempt.item_instance.item_revision
      served = served_of(attempt)
      body = JSON.parse(revision.body_json)
      given = served ? Diagnosis::AnswerText.call(attempt, served) : attempt.raw
      Verdict.new(attempt, revision.item.key, revision.item.subject, spec.skill, prompt_of(body, attempt.item_instance), given,
                  InstanceView.new(attempt.item_instance, body, 1).key, grading.verdict, JSON.parse(grading.error_codes_json || "[]"), grading.verdict == "near_miss")
    end
  end
end
