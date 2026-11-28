module Writings
  # The teacher's corrections of the students' texts (D-407): the decisions of the kind `correct_writing`, read from the ledger. A correction is the
  # teacher's own words (firm rule 1: the API never records one and a bot only reads it); the latest decision on a text counts, so a slip in a
  # correction is mended by a new one.
  module Corrections
    KIND = "correct_writing".freeze

    # One correction as the readers need it.
    Correction = Data.define(:decision_id, :submission_id, :text_it, :at, :teacher)

    module_function

    # {submission id => Correction}, the latest for each of the texts of +submissions+ (any enumerable of WritingSubmission or ids).
    def for(submissions)
      ids = submissions.map { |s| s.respond_to?(:id) ? s.id : s.to_i }.to_set
      return {} if ids.empty?

      for_decisions(Decision.where(kind: KIND).order(:id)).slice(*ids)
    end

    # The corrections of one student's texts, by submission id.
    def of_student(student)
      return {} unless student

      for_decisions(Decision.where(kind: KIND, student_id: student.id).order(:id))
    end

    def for_decisions(decisions)
      decisions.each_with_object({}) do |decision, out|
        payload = JSON.parse(decision.payload_json)
        id = payload["writing_submission_id"].to_i
        out[id] = Correction.new(decision_id: decision.id, submission_id: id, text_it: payload["text_it"].to_s, at: decision.created_at, teacher: decision.teacher_login)
      end
    end
  end
end
