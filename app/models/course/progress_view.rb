module Course
  # The JSON of `banco practice progress` (A4): per skill of the subject's topics, the derived state, its counts and
  # the typical errors, for one student. No student text (D-064). The state is the fold of practice/1 (track S2:
  # Practice::Fold); until it is integrated this view derives the two states it can tell without the rules
  # (not_seen, in_study) from the ledger and says so in `rules_version`.
  module ProgressView
    RULES = "practice/1 (provisional: states other than not_seen and in_study come with the S2 fold)".freeze

    module_function

    def call(subject, student)
      course = State.latest(subject)
      rows = TopicStage.rows(subject) || {}
      released = State.released_revision_id(subject)
      visible = ->(row) { row.latest && (student.trial? || (released == course&.id && row.stage == "approved")) }
      keys = rows.values.flat_map { |r| r.topic["skills"] }.uniq
      context = Validation::CourseContext.for(subject)
      serves = PracticeServe.where(student: student, skill_key: keys).to_a.group_by(&:skill_key)
      {
        subject: subject.key, student: student.key, trial: student.trial?, rules_version: RULES,
        topics: rows.map { |key, row| { topic: key, status: topic_status(row, student, serves), visible: !!visible.call(row) } },
        skills: keys.map { |key| skill_row(key, context, serves[key].to_a) },
        to_recover_without_topic: []
      }
    end

    def topic_status(row, student, serves)
      skills = row.topic["skills"]
      lesson_opened = row.latest && PracticeEvent.exists?(student: student, kind: "lesson_opened", topic_revision_id: row.latest.id)
      skills.any? { |s| serves[s].present? } || lesson_opened ? "in_progress" : "todo"
    end

    def skill_row(key, context, serves)
      attempts = PracticeAttempt.where(practice_serve_id: serves.map(&:id)).includes(:gradings).to_a
      graded = attempts.map { |a| [ a, a.latest_grading ] }
      typical = graded.flat_map { |_, g| g ? JSON.parse(g.error_codes_json) : [] }.tally
      events = PracticeEvent.where(practice_serve_id: serves.map(&:id)).group(:kind).count
      {
        skill: key, label_it: context.skill(key)&.fetch("label_it", nil), state: attempts.empty? ? "not_seen" : "in_study",
        since: attempts.map(&:answered_at).min&.utc&.iso8601, demonstrated_at: nil, consolidated_at: nil, seed: nil,
        counts: { serves: serves.size, tries: attempts.size,
                  correct_unaided: graded.count { |a, g| g&.verdict == "correct" && !a.aided }, correct_aided: graded.count { |a, g| g&.verdict == "correct" && a.aided },
                  wrong: graded.count { |_, g| g&.verdict == "wrong" }, hints: events["hint_shown"].to_i, solutions_requested: events["solution_shown"].to_i },
        typical: typical
      }
    end
  end
end
