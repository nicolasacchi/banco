module Writings
  # «Correzione nuova» (D-407): a correction is new until the student opens it, which is when the topic page draws it. Like the other «seen» markers it is
  # an app event (`writing_correction_seen`, the student and the decision it names), never a decision and never a state any engine reads. A new correction
  # of the same text (the teacher mended hers) is a new decision and so is new again. The teacher's preview records nothing.
  module Seen
    KIND = "writing_correction_seen".freeze

    New = Data.define(:correction, :submission)

    module_function

    # The corrections of this student's texts that he has not opened, newest first, each with its text.
    def unseen(student)
      return [] unless student&.kind == "student"

      corrections = Writings::Corrections.of_student(student)
      return [] if corrections.empty?

      seen = seen_ids(student)
      fresh = corrections.values.reject { |c| seen.include?(c.decision_id) }
      submissions = WritingSubmission.where(id: fresh.map(&:submission_id)).includes(topic_revision: :lesson).index_by(&:id)
      fresh.sort_by { |c| -c.decision_id }.filter_map { |c| (s = submissions[c.submission_id]) && New.new(c, s) }
    end

    # Marks these corrections (Writings::Corrections::Correction) as opened; one event each, once.
    def record(student, corrections)
      return unless student&.kind == "student"

      seen = seen_ids(student)
      corrections.reject { |c| seen.include?(c.decision_id) }.each do |c|
        AppEvent.create!(kind: KIND, student: student, payload_json: { writing_submission_id: c.submission_id, decision_id: c.decision_id }.to_json)
      end
    end

    def seen_ids(student)
      AppEvent.where(kind: KIND, student_id: student.id).pluck(:payload_json).to_set { |json| JSON.parse(json)["decision_id"].to_i }
    end
  end
end
