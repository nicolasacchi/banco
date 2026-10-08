module Course
  # The JSON of `banco practice progress` (A4): per skill of the subject's topics, the derived state, its counts and
  # the typical errors, for one student. No student text (D-064). The state is the fold of practice/1 (Practice::Fold
  # over Practice::Loader, as the student's pages and the teacher's page).
  module ProgressView
    RULES = Practice::Rules::V1::RULES_VERSION

    module_function

    def call(subject, student)
      course = State.latest(subject)
      rows = TopicStage.rows(subject) || {}
      released = State.released_revision_id(subject)
      visible = ->(row) { row.latest && (student.trial? || (released == course&.id && row.stage == "approved")) }
      keys = rows.values.flat_map { |r| r.topic["skills"] }.uniq
      context = Validation::CourseContext.for(subject)
      serves = PracticeServe.where(student: student, skill_key: keys).to_a.group_by(&:skill_key)
      input = Practice::Loader.for(student, subject: subject)
      states = Practice::Fold.call(seeds: input.seeds, tries: input.tries, serves: input.serves, skills: keys)
      tries = input.tries.group_by(&:skill)
      {
        subject: subject.key, student: student.key, trial: student.trial?, rules_version: RULES,
        topics: rows.map { |key, row| { topic: key, status: topic_status(row, student, serves), visible: !!visible.call(row) } },
        skills: keys.map { |key| skill_row(key, context, states[key], tries.fetch(key, [])) },
        to_recover_without_topic: input.seeds.values.select { |x| %w[to_recover to_learn].include?(x.state.to_s) && !keys.include?(x.skill) }
                                       .map { |x| { skill: x.skill, label_it: context.skill(x.skill)&.fetch("label_it", nil), state: x.state.to_s } }
      }
    end

    def topic_status(row, student, serves)
      skills = row.topic["skills"]
      lesson_opened = row.latest && PracticeEvent.exists?(student: student, kind: "lesson_opened", topic_revision_id: row.latest.id)
      skills.any? { |s| serves[s].present? } || lesson_opened ? "in_progress" : "todo"
    end

    def skill_row(key, context, state, tries)
      {
        skill: key, label_it: context.skill(key)&.fetch("label_it", nil), state: state.state,
        since: iso(state.since || tries.map(&:at).min), demonstrated_at: iso(state.demonstrated_at), consolidated_at: iso(state.consolidated_at),
        seed: state.seed && { state: state.seed.state.to_s, at: iso(state.seed.at), implied: !!state.seed.implied },
        counts: state.counts.except(:typical, :seconds).merge(seconds: state.counts[:seconds].to_i),
        typical: state.counts[:typical]
      }
    end

    def iso(time) = time&.utc&.iso8601
  end
end
