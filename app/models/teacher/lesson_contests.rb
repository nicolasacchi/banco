module Teacher
  # «Per me va bene così» on a check of a lesson/2 (D-396), as the teacher reads it in «Contestazioni» (D-400): one row per lesson event
  # `check_contested` of the student, oldest first. It writes no comment, so these rows are where the teacher finds it. The row says which
  # lesson and which check (card, block, and step, exercise or part when the check has them) and his answer in the words he read (D-387's wording,
  # stored by Lessons::CheckContest as `words`), read through Lessons::Contests (no model of the teacher names the lesson ledger, D-254). A contest of before D-400 has no words: it has the comment that was written with it
  # (`comment_ids`, the inbox). Read-only.
  #
  #   Teacher::LessonContests.call(student: student, since: Time.utc(2026, 11, 1), subject: "english")
  module LessonContests
    module_function

    # since: a Time, the first moment a contest may have; subject: a subject key; nil for none.
    def call(student:, since: nil, subject: nil) = Lessons::Contests.rows(student: student, since: since, subject: subject)
  end
end
