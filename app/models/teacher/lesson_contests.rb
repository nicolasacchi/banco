module Teacher
  # «Per me va bene così» on a check of a lesson/2 (D-396), as the teacher reads it in «Contestazioni» (D-400): one row per lesson event
  # `check_contested` of the student, oldest first. It writes no comment, so these rows are where the teacher finds it. The row says which
  # lesson and which check (card, block, and step, exercise or part when the check has them) and his answer in the words he read (D-387's wording,
  # stored by Lessons::CheckContest as `words`). A contest of before D-400 has no words: it has the comment that was written with it
  # (`comment_ids`, the inbox). Read-only.
  #
  #   Teacher::LessonContests.call(student: student, since: Time.utc(2026, 11, 1), subject: "english")
  module LessonContests
    PLACE_KEYS = %w[step ex part].freeze

    module_function

    # since: a Time, the first moment a contest may have; subject: a subject key; nil for none.
    def call(student:, since: nil, subject: nil)
      scope = LessonEvent.where(student_id: student.id, kind: "check_contested").includes(topic_revision: { lesson: :subject }).order(:id)
      scope = scope.where("lesson_events.at >= ?", since) if since
      rows = scope.map { |event| row(event) }
      subject ? rows.select { |r| r[:subject] == subject } : rows
    end

    def row(event)
      payload = event.payload
      lesson = event.topic_revision.lesson
      { kind: "lesson_check", ref: "lesson_check-#{event.id}", id: event.id, at: event.at.utc.iso8601, subject: lesson.subject.key, topic: lesson.key,
        card: event.card, block: event.block, place: payload.slice(*PLACE_KEYS), answer: payload["words"], comment_ids: Array(payload["comment_id"]) }
    end
  end
end
