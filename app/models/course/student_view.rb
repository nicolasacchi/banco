module Course
  # Everything the student's course pages read (A9): what the catalog shows this student, the derived state
  # of each skill (practice/1), the status of each topic, Oggi. Read-only; each page builds one and asks.
  #
  #   view = Course::StudentView.new(student)
  #   view.subjects            # visible subjects only (Catalog::SubjectView with topics)
  #   view.find_topic(key)     # => [SubjectView, TopicView] or nil when the topic is not visible to this student
  #   view.progress(sv)        # => Progress(programme:, extra:), each a Tally(total, done, in_progress; missing)
  #   view.today               # => {resume:, suggestions: [Practice::Today::Suggestion]}
  class StudentView
    DONE = Practice::Today::DONE

    attr_reader :student

    # view: :official or :drafts, for the teacher's preview student only (D-309); a real student has no view.
    def initialize(student, now: Time.current, view: nil)
      @student = student
      @now = now
      @view = view
    end

    def catalog = @catalog ||= Catalog.for(@student, view: @view)

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

    # The topics of the programme, in course order, and those outside it (D-324): optional, listed after them under
    # «Facoltativi · fuori programma», never suggested by Oggi and counted apart from the programme (D-326).
    def programme_topics(sv) = sv.topics.reject(&:extra?)
    def extra_topics(sv) = sv.topics.select(&:extra?)

    def status(topic) = Practice::Today.status(topic, states, started: started_keys.include?(topic.key))

    def recover_tag?(topic) = Practice::Today.recover_tag?(topic, states)

    def lesson_read?(topic) = opened_keys.include?(topic.key)

    # "Prima conviene fare": the first visible `after` topic that is not done. A programme topic never sends the
    # student to an extra one.
    def before(sv, topic)
      visible = topic.extra? ? sv.topics : programme_topics(sv)
      Practice::Today.before(topic, visible.to_h { |t| [ t.key, t ] }, states)
    end

    # The progress of a subject in topics (D-326): how many of its programme topics are done (mandatory) and how many of
    # its extra topics (optional). Done = Practice::Today.done?; in progress = started and not done; missing = not done.
    # One pass over the statuses already computed; Oggi, Materie and Materia read these and never count on their own.
    Tally = Data.define(:total, :done, :in_progress) do
      def missing = total - done
      def none? = total.zero?
      # Floor, so a bar never shows 100 % while one topic is missing.
      def percent = total.zero? ? 0 : (100 * done / total)
      def +(other) = Tally.new(total + other.total, done + other.done, in_progress + other.in_progress)
    end
    Progress = Data.define(:programme, :extra) do
      def +(other) = Progress.new(programme + other.programme, extra + other.extra)
    end

    def progress(sv)
      @progress ||= {}
      @progress[sv.subject.key] ||= Progress.new(tally(programme_topics(sv)), tally(extra_topics(sv)))
    end

    # The same, summed over every visible subject (Oggi's «Il tuo percorso»).
    def overall_progress
      subjects.map { |sv| progress(sv) }.reduce(Progress.new(Tally.new(0, 0, 0), Tally.new(0, 0, 0)), :+)
    end

    # Skills the diagnosis found to recover or learn that no visible topic holds.
    def skills_without_topic(sv)
      sv.skills_without_topic.select { |s| %w[to_recover to_learn].include?(states[s]&.state) }
    end

    # ---- Oggi ------------------------------------------------------------------------------------

    # Oggi reads the topics of the programme only: an extra topic is never suggested nor resumed there (D-324).
    def today
      @today ||= begin
        programme = subjects.map { |sv| sv.with(topics: programme_topics(sv)) }.select { |sv| sv.topics.any? }
        Practice::Today.call(catalog: programme, states: states, graph_order: graph_order, last_topic: last_topic)
      end
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

    def tally(topics)
      by_status = topics.map { |topic| status(topic) }.tally
      Tally.new(topics.size, by_status[:done].to_i, by_status[:in_progress].to_i)
    end

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
