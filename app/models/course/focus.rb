module Course
  # The subject the teacher recommends the student start from (D-399): derived, never stored. The decision `set_focus_subject`
  # (params {subject: KEY}, or {subject: ""} to clear it) is recorded against the official student; the latest one wins. Oggi
  # (Course::StudentView#today) reads it for every student it shows, the official student and the trial and preview students that
  # follow his rule; the teacher's course page reads it to say which subject is recommended now.
  module Focus
    KIND = "set_focus_subject".freeze

    module_function

    # The key of the recommended subject, or nil when none is.
    def subject_key
      student = Student.official or return nil
      decision = Decision.where(kind: KIND, student: student).order(:id).last or return nil
      JSON.parse(decision.payload_json)["subject"].presence
    end

    # The recommended Subject, or nil.
    def subject
      key = subject_key
      key && Subject.find_by(key: key)
    end
  end
end
