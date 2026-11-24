# frozen_string_literal: true

module Lessons
  # The reader of the lesson ledger's `check_contested` events (D-396, D-400): «Per me va bene così» on a check of a lesson/2, which writes no comment.
  # The teacher's pages, the dashboard's count and its digest read them here, so that no model outside the lessons names the ledger (D-254).
  # Read-only.
  #
  #   Lessons::Contests.rows(student: student, since: Time.utc(2026, 11, 1), subject: "english")   # the rows Teacher::LessonContests lists
  #   Lessons::Contests.count(student: student, since: 7.days.ago)
  module Contests
    KIND = "check_contested"
    PLACE_KEYS = %w[step ex part].freeze

    module_function

    # The student's contests, oldest first: since: a Time, the first moment a contest may have; subject: a subject key; nil for none.
    def rows(student:, since: nil, subject: nil)
      scope = LessonEvent.where(student_id: student.id, kind: KIND).includes(topic_revision: { lesson: :subject }).order(:id)
      scope = scope.where("lesson_events.at >= ?", since) if since
      found = scope.map { |event| row(event) }
      subject ? found.select { |r| r[:subject] == subject } : found
    end

    # How many contests the student made at or after `since`.
    def count(student:, since:) = LessonEvent.where(student_id: student.id, kind: KIND).where("at >= ?", since).count

    # One watermark row for Teacher::DashboardDigest: the largest id of a contest.
    def sql_watermark = "SELECT 'lesson_contests', MAX(id) FROM lesson_events WHERE kind = '#{KIND}'"

    def row(event)
      payload = event.payload
      lesson = event.topic_revision.lesson
      { kind: "lesson_check", ref: "lesson_check-#{event.id}", id: event.id, at: event.at.utc.iso8601, subject: lesson.subject.key, topic: lesson.key,
        card: event.card, block: event.block, place: payload.slice(*PLACE_KEYS), answer: payload["words"], comment_ids: Array(payload["comment_id"]) }
    end
  end
end
