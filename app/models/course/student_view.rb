module Course
  # Everything the student's course pages read (A9): what the catalog shows this student, the derived state
  # of each skill (practice/1), the status of each topic, Oggi. Read-only; each page builds one and asks.
  #
  #   view = Course::StudentView.new(student)
  #   view.subjects            # visible subjects only (Catalog::SubjectView with topics)
  #   view.find_topic(key)     # => [SubjectView, TopicView] or nil when the topic is not visible to this student
  #   view.today               # => {resume:, suggestions: [Practice::Today::Suggestion]}
  class StudentView
    DONE = Practice::Today::DONE

    attr_reader :student

    def initialize(student, now: Time.current)
      @student = student
      @now = now
    end

    def catalog = @catalog ||= Catalog.for(@student)

    # The subjects with at least one visible topic.
    def subjects = catalog.select { |sv| sv.topics.any? }

    # An official student's subject whose course was withdrawn after a release (listed, with no topics).
    def closed_subjects = catalog.reject { |sv| sv.topics.any? }

    def subject(key) = subjects.find { |sv| sv.subject.key == key.to_s }

    def find_topic(key)
      subjects.each do |sv|
        topic = sv.topics.find { |t| t.key == key.to_s }
        return [ sv, topic ] if topic
      end
      nil
    end

    # ---- skills ----------------------------------------------------------------------------------

    # {skill => Practice::SkillState} for the skills of every visible topic.
    def states
      @states ||= subjects.each_with_object({}) do |sv, all|
        input = Practice::Loader.for(@student, subject: sv.subject, now: @now)
        all.merge!(Practice::Fold.call(seeds: input.seeds, tries: input.tries, serves: input.serves, skills: sv.topics.flat_map(&:skills).uniq))
      end
    end

    def state(skill) = states[skill]

    # The label of a graph or course skill of a visible subject.
    def label(skill)
      labels[skill] || skill
    end

    def labels
      @labels ||= subjects.each_with_object({}) do |sv, all|
        graph_skills(sv).each { |s| all[s["key"]] = s["label_it"] }
      end
    end

    # ---- topics ----------------------------------------------------------------------------------

    def status(topic) = Practice::Today.status(topic, states, started: started_keys.include?(topic.key))

    def recover_tag?(topic) = Practice::Today.recover_tag?(topic, states)

    def lesson_read?(topic) = opened_keys.include?(topic.key)

    # "Prima conviene fare": the first visible `after` topic that is not done.
    def before(sv, topic)
      Practice::Today.before(topic, sv.topics.to_h { |t| [ t.key, t ] }, states)
    end

    # The counts of the "Materie" page, over the skills of the visible topics of the subject.
    def counts(sv)
      skills = sv.topics.flat_map(&:skills).uniq
      tally = skills.map { |s| states[s]&.state || "not_seen" }.tally
      { demonstrated: tally["demonstrated"].to_i + tally["consolidated"].to_i, in_study: tally["in_study"].to_i,
        to_recover: tally["to_recover"].to_i + tally["to_review"].to_i, not_seen: tally["not_seen"].to_i + tally["to_learn"].to_i }
    end

    # Skills the diagnosis found to recover or learn that no visible topic holds.
    def skills_without_topic(sv)
      sv.skills_without_topic.select { |s| %w[to_recover to_learn].include?(states[s]&.state) }
    end

    # ---- Oggi ------------------------------------------------------------------------------------

    def today
      @today ||= Practice::Today.call(catalog: subjects, states: states, graph_order: graph_order, last_topic: last_topic)
    end

    def last_topic
      serve = PracticeServe.where(student: @student).order(:id).last
      opened = PracticeEvent.where(student: @student, kind: "lesson_opened").order(:id).last
      pick = [ serve && [ serve.created_at, serve.topic_revision ], opened && [ opened.at, opened.topic_revision ] ].compact.max_by(&:first)
      pick&.last&.lesson&.key
    end

    def graph_order
      Practice::GraphOrder.call(subjects.flat_map { |sv| graph_skills(sv) })
    end

    private

    def graph_skills(sv)
      graph = JSON.parse(sv.course_revision.skill_graph_revision.body_json)["skills"]
      graph + sv.course_revision.body["skills"]
    end

    def started_keys
      @started_keys ||= (served_keys + opened_keys.to_a).to_set
    end

    def served_keys
      PracticeServe.where(student: @student).joins(topic_revision: :lesson).distinct.pluck("lessons.key")
    end

    def opened_keys
      @opened_keys ||= PracticeEvent.where(student: @student, kind: "lesson_opened").joins(topic_revision: :lesson).distinct.pluck("lessons.key").to_set
    end
  end
end
