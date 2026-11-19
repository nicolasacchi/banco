module Course
  # Everything the student's course pages read (A9): what the catalog shows this student, the derived state
  # of each skill (practice/6), the status of each topic, Oggi. Read-only; each page builds one and asks.
  #
  #   view = Course::StudentView.new(student)
  #   view.subjects            # visible subjects only (Catalog::SubjectView with topics)
  #   view.find_topic(key)     # => [SubjectView, TopicView] or nil when the topic is not visible to this student
  #   view.progress(sv)        # => Progress(programme:, extra:), each a Tally(total, done, in_progress, known, minutes_left; missing, exercises, hours_left)
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

    # The skill graph's description of one of the skill's typical errors (nil when it has none), for the reminder's fallback (D-358).
    def error_description(skill, code)
      subjects.each do |sv|
        found = graph_skills(sv).find { |s| s["key"] == skill && Array(s["errors"]).any? }
        entry = found && Array(found["errors"]).find { |e| e["code"] == code }
        return entry["description_it"] if entry
      end
      nil
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
    def recover_kind(topic) = Practice::Today.recover_kind(topic, states)

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
    #
    # Honest progress (D-367), additive: `known` is the done topics that the entry test showed (every skill still in the state the
    # diagnosis seeded, never studied) and `exercises` the other done ones, so done = known + exercises; `minutes_left` is the sum of
    # the `minutes` of the topics not done, and `hours_left` that time in kind round hours. No count of `done` changes.
    Tally = Data.define(:total, :done, :in_progress, :known, :minutes_left) do
      def initialize(total:, done:, in_progress:, known: 0, minutes_left: 0) = super
      def missing = total - done
      def none? = total.zero?
      # The done topics the student studied with the exercises (not shown by the entry test).
      def exercises = done - known
      # Floor, so a bar never shows 100 % while one topic is missing.
      def percent = total.zero? ? 0 : (100 * done / total)

      # The time still to study in round hours, never a false precision: 0 is «less than an hour» (or nothing, when missing is
      # zero); up to 19 h the nearest hour, from 20 h the nearest 5.
      def hours_left
        hours = minutes_left / 60.0
        return 0 if hours < 0.75

        hours < 20 ? hours.round : (hours / 5).round * 5
      end

      def +(other)
        Tally.new(total: total + other.total, done: done + other.done, in_progress: in_progress + other.in_progress,
                  known: known + other.known, minutes_left: minutes_left + other.minutes_left)
      end
    end
    Progress = Data.define(:programme, :extra) do
      def +(other) = Progress.new(programme + other.programme, extra + other.extra)
    end

    def progress(sv)
      @progress ||= {}
      @progress[sv.subject.key] ||= Progress.new(tally(programme_topics(sv)), tally(extra_topics(sv)))
    end

    # The same, summed over every visible subject (Oggi's «I tuoi progressi»).
    def overall_progress
      subjects.map { |sv| progress(sv) }.reduce(Progress.new(Tally.new(total: 0, done: 0, in_progress: 0), Tally.new(total: 0, done: 0, in_progress: 0)), :+)
    end

    # The right answers the student gave in a subject (D-367): the skills of its visible topics, each unaided or aided; every
    # right answer ends its serve, so this is the number of exercises answered right. It reads the folded counts and counts nothing new.
    def correct_exercises(sv)
      sv.topics.flat_map(&:skills).uniq.sum { |skill| (state = states[skill]) ? state.counts[:correct_unaided].to_i + state.counts[:correct_aided].to_i : 0 }
    end

    # Skills the diagnosis found to recover or learn that no visible topic holds.
    def skills_without_topic(sv)
      sv.skills_without_topic.select { |s| %w[to_recover to_learn].include?(states[s]&.state) }
    end

    # ---- Oggi ------------------------------------------------------------------------------------

    # Oggi reads the topics of the programme only: an extra topic is never suggested nor resumed there (D-324).
    def today
      @today ||= Practice::Today.call(**today_input)
    end

    # What Oggi proposes first for a subject (D-333, `banco next`): the topic the student left, when it is of this subject, else
    # the first of the whole ranked suggestions that is (Oggi keeps the first SUGGESTIONS_MAX of the same list, rounds robin over
    # the subjects). nil when every programme topic of the subject is done. reason: :resume or Practice::Today's.
    NextTopic = Data.define(:topic, :reason, :skill)

    def next_topic(sv)
      topics = programme_topics(sv).to_h { |t| [ t.key, t ] }
      resume = ranked_today[:resume]
      return NextTopic.new(topic: topics.fetch(resume), reason: :resume, skill: nil) if topics.key?(resume)

      pick = ranked_today[:suggestions].find { |s| topics.key?(s.topic_key) } or return nil
      NextTopic.new(topic: topics.fetch(pick.topic_key), reason: pick.reason, skill: pick.skill)
    end

    # The skills of a subject the pages call «Dal test: da ripassare» (Practice::Today::RECOVER) on a programme topic, as [skill, topic key],
    # then those the diagnosis found to recover or learn that no topic holds (the line «Dal test: da ripassare, ancora senza argomento»), as [skill, nil].
    def skills_to_recover(sv)
      held = programme_topics(sv).flat_map { |t| t.skills.select { |s| Practice::Today::RECOVER.include?(states[s]&.state) }.map { |s| [ s, t.key ] } }
      held.uniq(&:first) + skills_without_topic(sv).map { |s| [ s, nil ] }
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

    def today_input
      programme = subjects.map { |sv| sv.with(topics: programme_topics(sv)) }.select { |sv| sv.topics.any? }
      { catalog: programme, states: states, graph_order: graph_order, last_topic: last_topic }
    end

    # The whole ranked list of Oggi, not cut at SUGGESTIONS_MAX.
    def ranked_today = @ranked_today ||= Practice::Today.call(**today_input, limit: nil)

    def tally(topics)
      by_status = topics.map { |topic| status(topic) }.tally
      known = topics.count { |topic| status(topic) == :done && known_from_entry?(topic) }
      minutes_left = topics.sum { |topic| status(topic) == :done ? 0 : topic.minutes.to_i }
      Tally.new(total: topics.size, done: by_status[:done].to_i, in_progress: by_status[:in_progress].to_i, known: known, minutes_left: minutes_left)
    end

    # A done topic the entry test showed (D-367): it has skills and each is still in the state the diagnosis seeded it in (demonstrated, since
    # the seed), so nothing the student did with the exercises moved it.
    def known_from_entry?(topic)
      topic.skills.any? && topic.skills.all? do |skill|
        state = states[skill]
        seed = state&.seed
        seed && seed.state.to_s == "demonstrated" && state.state == "demonstrated" && state.since == seed.at
      end
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
