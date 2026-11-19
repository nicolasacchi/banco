module Course
  # «I miei schemi» (D-372): for each topic the student sees, the schema that reminds him of it at a glance (the summary card of the
  # lesson revision he is shown). A schema is unlocked when its topic is done, by the one meaning the course uses (`StudentView#status`,
  # `Practice::Today.done?`: practised, or known from the entry test); before that it is only counted. The teacher's preview has no
  # progress of its own to wait for, so it opens every schema (`open_all`). Read-only, built from the student's course view: no query.
  #
  #   schemas = Course::Schemas.new(course_view, open_all: preview?)
  #   schemas.unlocked?(topic)         # the schema page opens
  #   schemas.groups                   # => [Group(subject_view:, open: [Entry], locked_count:)] by subject, in course order
  #   schemas.daily_pick(student_key)  # => an Entry or nil: the same one all day, never a model
  class Schemas
    Entry = Data.define(:subject_view, :topic)
    Group = Data.define(:subject_view, :open, :locked_count)

    def initialize(view, open_all: false)
      @view = view
      @open_all = open_all
    end

    def unlocked?(topic) = @open_all || @view.status(topic) == :done

    # Has the topic a schema at all: its lesson revision has a summary (a lesson/2's core summary card, a lesson/1's `summary_it`)? The page
    # of `SchemasController#show` is 404 without one, so nothing links to a schema that is not there.
    def exists?(topic)
      body = topic.lesson_revision.body
      return body["cards"].to_a.any? { |c| c["role"] == "summary" && c["level"] == "core" } if body["schema"] == "banco.lesson/2"

      body.dig("sections", "summary_it").present?
    end

    # Every visible subject with at least one topic, the programme first and the extra topics after it (the order of the subject page).
    def groups
      @groups ||= @view.subjects.map do |sv|
        topics = @view.programme_topics(sv) + @view.extra_topics(sv)
        open, locked = topics.partition { |topic| unlocked?(topic) }
        Group.new(subject_view: sv, open: open.map { |topic| Entry.new(subject_view: sv, topic: topic) }, locked_count: locked.size)
      end
    end

    def open_count = groups.sum { |g| g.open.size }

    def locked_count = groups.sum(&:locked_count)

    def any_open? = groups.any? { |g| g.open.any? }

    # One unlocked schema for the day: the same for a student all day (the date and his key choose it, nothing is drawn), another tomorrow.
    # It changes only when a new schema opens. nil when none is open.
    def daily_pick(student_key, on: Time.zone.today)
      entries = groups.flat_map(&:open).sort_by { |e| e.topic.key }
      return nil if entries.empty?

      entries.fetch(Digest::SHA256.hexdigest("schema|#{student_key}|#{on.iso8601}").to_i(16) % entries.size)
    end
  end
end
