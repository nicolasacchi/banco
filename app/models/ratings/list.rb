module Ratings
  # The student's ratings as the teacher reads them (D-365): the filtered rows newest first, and for every target of those rows the average and
  # the count of the current stars (Rating.summaries: the latest rating of each official student, trial students never counted). The one read
  # model of the teacher's page `/teacher/ratings` and of `GET /api/v1/ratings`; read-only, no query writes anything.
  #
  #   Ratings::List.new(subject: "math", topic: "ripasso.math.demo", kind: "item", target: "demo-item-1", student: "student", since: time)
  class List
    FILTERS = %i[subject topic kind target student since].freeze

    # One target of the rows: what it is, how it stands (summary nil: no official star yet) and how many rows it has in the list.
    Target = Data.define(:kind, :key, :rows, :summary)

    attr_reader :filters

    def initialize(**filters)
      @filters = filters.slice(*FILTERS).compact_blank
    end

    # The filtered rows, with what the readers show of them loaded.
    def relation
      @relation ||= begin
        scope = Rating.all
        scope = scope.of_subject(filters[:subject]) if filters[:subject]
        scope = scope.of_topic(filters[:topic]) if filters[:topic]
        scope = scope.where(target_kind: filters[:kind]) if filters[:kind]
        scope = scope.of_target(filters[:target]) if filters[:target]
        scope = scope.of_student(filters[:student]) if filters[:student]
        scope = scope.created_since(filters[:since]) if filters[:since]
        scope
      end
    end

    def total = relation.count

    # Newest first.
    def rows(limit: nil)
      scope = relation.newest_first.includes(:student, :subject, :practice_serve, topic_revision: :lesson, item_revision: :item, lesson_revision: :lesson)
      limit ? scope.limit(limit).to_a : scope.to_a
    end

    # The targets of the rows, the most recently rated first.
    def targets
      @targets ||= begin
        summaries = Rating.summaries(relation)
        counts = relation.group(:target_kind, :target_key).order(Arel.sql("MAX(ratings.id) DESC")).pluck(:target_kind, :target_key, Arel.sql("COUNT(*)"))
        counts.map { |kind, key, rows| Target.new(kind: kind, key: key, rows: rows.to_i, summary: summaries[[ kind, key ]]) }
      end
    end

    # The whole list as one average, for a page that asks about a topic or a subject: nil when no official star counts.
    def summary = Rating.summary(relation)
  end
end
