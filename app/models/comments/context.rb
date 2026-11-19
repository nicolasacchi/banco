module Comments
  # What the teacher needs to answer one comment (D-371), read-only and never shown to the student: the item or lesson revision he saw against the
  # newest one, his tries on that serve and that item, the comments he wrote earlier on the same item or page, and the hours left of the
  # promised answer time (D-349). It is the `context` block of GET /api/v1/comments/:id, of `banco comments show` and of bin/rails
  # banco:comments:show; the one place that builds it. Nothing is written and nothing is recorded.
  #
  # words: the raw words he typed in the tries (D-346: the teacher token, and the operator's console). Without them (a bot_read token) the tries
  # keep the outcome, the error code and the try number, never `answer` nor the row an anchor points at.
  class Context
    TRIES = 20
    EARLIER = 20
    WORDS = %i[answer anchor_row].freeze

    def initialize(comment, words: false)
      @comment = comment
      @words = words
    end

    def to_h
      { revision: revision, tries: tries, earlier_comments: earlier_comments, reply: reply }.compact
    end

    private

    attr_reader :comment

    # {item: {...}, lesson: {...}}: the revision he saw against the newest of the same item or lesson; nil when the comment names neither.
    def revision
      found = { item: revision_block(comment.item_revision, ItemRevision, :item_id) { |r| r.item.key },
                lesson: revision_block(comment.lesson_revision, LessonRevision, :lesson_id) { |r| r.lesson.key } }.compact
      found.presence
    end

    def revision_block(seen, model, owner)
      return nil unless seen

      current = model.where(owner => seen[owner]).maximum(:id)
      changed = current != seen.id
      { key: yield(seen), seen_revision_id: seen.id, current_revision_id: current, changed: changed,
        note: changed ? "changed since: rev #{current}" : "unchanged: rev #{seen.id}" }
    end

    # His tries behind the comment (its serve, its instance, or the card of a lesson) and, for an exercise, his other recent tries on the item.
    def tries
      log = Attempts::Log.new(comment.student)
      behind = log.list(Attempts::Filters.new(comment: comment), limit: TRIES).rows
      item_key = comment.item_revision&.item&.key
      others = item_key ? log.list(Attempts::Filters.new(item: item_key), kinds: %w[practice diagnosis], limit: Attempts::Log::MAX_LIMIT) : nil
      return nil if behind.empty? && (others.nil? || others.total.zero?)

      out = { words: @words, behind_the_comment: behind.map { |r| strip(r) } }
      if others
        listed = behind.to_set { |r| r[:ref] }
        out[:on_the_item] = { item: item_key, total: others.total, rows: others.rows.reject { |r| listed.include?(r[:ref]) }.last(TRIES).map { |r| strip(r) } }
      end
      out
    end

    def strip(row) = @words ? row : row.except(*WORDS)

    # The comments he wrote before this one on the same item, or (a comment with no item) on the same page; each with what the teacher answered.
    def earlier_comments
      scope = Comment.where(student_id: comment.student_id).where("comments.id < ?", comment.id).includes(:events).order(:id)
      item_id = comment.item_revision&.item_id
      scope = item_id ? scope.where(item_revision_id: ItemRevision.where(item_id: item_id).select(:id)) : scope.where(page_path: comment.page_path)
      rows = scope.last(EARLIER).map do |c|
        { id: c.id, state: c.state, reason: c.reason, text_it: c.text_it, created_at: c.created_at.utc.iso8601,
          replies: c.replies.map { |e| { text_it: e.text_it, at: e.created_at.utc.iso8601 } } }.compact
      end
      rows.presence
    end

    # The promise of D-349 on this comment: from the first student message without a teacher reply after it.
    def reply
      since = comment.waiting_since
      return { within_hours: ReplyWindow.hours, waiting: false } unless since

      { within_hours: ReplyWindow.hours, waiting: true, waiting_since: since.utc.iso8601, due_in_hours: comment.due_in_hours, late: comment.late?,
        student_followup: comment.student_followup? }
    end
  end
end
