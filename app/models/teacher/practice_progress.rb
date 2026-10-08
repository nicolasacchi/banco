module Teacher
  # One student's practice trail in one subject, for the teacher (A10, D-217): per topic its status, per skill the
  # derived state with its why, counts, typical errors and time, the skills to recover that no topic holds, the
  # questions the student asked, and the trail of every try of a skill. Read-only. Official and trial students
  # are alike; a trial student's rows never touch the official one's.
  class PracticeProgress
    TopicRow = Data.define(:topic, :stage, :status, :skills)
    SkillRow = Data.define(:skill, :label_it, :state, :why_it, :seed, :counts, :typical, :last_at, :minutes)
    Typical = Data.define(:code, :description_it, :count)
    Question = Data.define(:at, :topic, :section, :exercise, :text_it)
    Step = Data.define(:at, :stem, :raw, :outcome, :codes, :aided, :hints, :solution_shown, :reason, :to_correct)

    attr_reader :subject, :student

    def initialize(subject, student)
      @subject = subject
      @student = student
    end

    def present? = !student.nil?
    def input = @input ||= Practice::Loader.for(student, subject: subject)

    def rows = @rows ||= Course::TopicStage.rows(subject) || {}

    def skill_keys = rows.values.flat_map { |r| r.topic["skills"] }.uniq

    def states
      @states ||= Practice::Fold.call(seeds: input.seeds, tries: input.tries, serves: input.serves, skills: skill_keys)
    end

    def topics
      @topics ||= begin
        serves = PracticeServe.where(student: student, skill_key: skill_keys).to_a.group_by(&:skill_key)
        rows.map do |key, row|
          TopicRow.new(key, row.stage, row.latest ? Course::ProgressView.topic_status(row, student, serves) : "todo",
                       row.topic["skills"].map { |s| skill_row(s) })
        end
      end
    end

    def skill_row(key)
      state = states[key]
      tries = input.tries.select { |t| t.skill == key }
      SkillRow.new(key, labels[key] || key, state.state, Practice::Messages.why_it(state.why), state.seed, state.counts, typical_of(state.counts[:typical]),
                   tries.map(&:at).max || input.serves.select { |s| s.skill == key }.map(&:at).max, (state.counts[:seconds].to_f / 60).round)
    end

    # Skills the diagnosis found to recover or learn that no topic of the map practices.
    def without_topic
      @without_topic ||= input.seeds.values.select { |s| %w[to_recover to_learn].include?(s.state) && !skill_keys.include?(s.skill) }
                              .map { |s| [ s.skill, labels[s.skill] || s.skill, s.state ] }
    end

    # The "Non ho capito" lines of the student in this subject, newest first. text_it is for the teacher only.
    def questions
      @questions ||= StudentQuestion.where(student: student).includes(topic_revision: :lesson, lesson_revision: :lesson, practice_serve: :topic_revision).order(id: :desc).filter_map do |q|
        lesson = q.topic_revision&.lesson || q.lesson_revision&.lesson || q.practice_serve&.topic_revision&.lesson
        next unless lesson && lesson.subject_id == subject.id

        Question.new(q.created_at, lesson.key, q.section, q.exercise, q.text_it)
      end
    end

    def labels
      @labels ||= begin
        course = Course::State.latest(subject)
        graph = course && JSON.parse(course.skill_graph_revision.body_json)["skills"]
        (Array(graph) + Array(course&.body&.dig("skills"))).to_h { |s| [ s["key"], s["label_it"] ] }
      end
    end

    # Every try of one skill in time order, with the instance as served, the raw answer and the outcome.
    def trail(skill)
      serves = PracticeServe.where(student: student, skill_key: skill).includes(:events, item_instance: { item_revision: :item }, attempts: :gradings).order(:id).to_a
      serves.flat_map { |serve| steps_of(serve) }.sort_by(&:at)
    end

    private

    def steps_of(serve)
      instance = serve.item_instance
      spec = Grading::Spec.from_instance(instance)
      view = InstanceView.new(instance, JSON.parse(instance.item_revision.body_json), 1)
      hints = serve.events.select { |e| e.kind == "hint_shown" }
      solved = serve.events.find { |e| e.kind == "solution_shown" }
      serve.attempts.sort_by(&:try_number).map do |attempt|
        grade = Practice::Instances.grade(attempt, spec)
        outcome = grade&.outcome || (attempt.latest_grading ? :not_a_try : :ungraded)
        Step.new(attempt.answered_at, view.stem, attempt.raw, outcome, grade&.codes || [], attempt.aided, hints.count { |e| e.at <= attempt.answered_at },
                 solved && solved.at <= attempt.answered_at ? JSON.parse(solved.payload_json || "{}")["reason"] : nil, serve.reason,
                 outcome == :undetermined || outcome == :ungraded)
      end
    end

    def typical_of(counts)
      catalogue = descriptions
      counts.sort_by { |code, n| [ -n, code ] }.map { |code, n| Typical.new(code, catalogue[code], n) }
    end

    # code => the Italian description, from the pinned items' catalogues and the course map's skill errors.
    def descriptions
      @descriptions ||= begin
        out = {}
        Array(Course::State.latest(subject)&.body&.dig("skills")).each { |s| Array(s["errors"]).each { |e| out[e["code"]] ||= e["description_it"] } }
        ids = rows.values.filter_map(&:latest).flat_map { |r| r.body["practice"].flat_map { |p| p["items"].map { |i| i["revision"] } } }
        ItemRevision.where(id: ids).each { |r| ItemCard.catalogue_of(JSON.parse(r.body_json)).each { |e| out[e["code"]] ||= e["description_it"] } }
        out
      end
    end
  end
end
