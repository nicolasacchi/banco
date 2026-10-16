module Comments
  # The teacher's inbox (D-304): comments and the student's older "Ho una domanda" rows (student_questions, read-only
  # here) in one list, newest first, with filters. A guest gets the counts only (`counts`), never a row.
  class Inbox
    Row = Struct.new(:type, :record, :at, :state, keyword_init: true)

    FILTERS = %i[state reason kind subject who type].freeze

    attr_reader :filters

    def initialize(filters = {})
      @filters = FILTERS.to_h { |k| [ k, filters[k].to_s.presence ] }
    end

    def comments
      @comments ||= begin
        scope = Comment.includes(:events, :student, :subject, :lesson_revision, :item_revision).order(id: :desc)
        scope = scope.where(reason: filters[:reason]) if Comment::REASONS.include?(filters[:reason])
        scope = scope.where(page_kind: filters[:kind]) if Comment::PAGE_KINDS.include?(filters[:kind])
        scope = scope.where(subject: Subject.where(key: filters[:subject])) if filters[:subject]
        scope = scope.where(trial: filters[:who] == "trial") if %w[official trial].include?(filters[:who])
        rows = scope.to_a
        rows = rows.select { |c| c.state == filters[:state] } if Comment::STATES.include?(filters[:state])
        rows
      end
    end

    # The older questions, only in the unfiltered list or when asked for ("type=question"); a filter on a comment's
    # own fields (state, reason, place kind) leaves them out.
    def questions
      return [] if filters[:type] == "comment"
      return [] if filters.slice(:state, :reason, :kind, :who).values.any?(&:present?)

      scope = StudentQuestion.includes(:student).order(id: :desc)
      scope = scope.where(topic_revision_id: TopicRevision.joins(lesson: :subject).where(subjects: { key: filters[:subject] })) if filters[:subject]
      scope.limit(200).to_a
    end

    def rows
      list = filters[:type] == "question" ? [] : comments.map { |c| Row.new(type: :comment, record: c, at: c.created_at, state: c.state) }
      list += questions.map { |q| Row.new(type: :question, record: q, at: q.created_at, state: nil) }
      list.sort_by { |r| -r.at.to_f }
    end

    # Counts by state, for the page head and for a guest: { "sent" => n, ..., questions: n }.
    def self.counts
      comments = Comment.includes(:events).to_a
      Comment::STATES.to_h { |s| [ s, comments.count { |c| c.state == s } ] }.merge("questions" => StudentQuestion.count)
    end
  end
end
