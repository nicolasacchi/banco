module Attempts
  # The student's comments next to a try (D-346): the comment as the API shows it and, when the try's exercise has a shown order, the row its anchor
  # points at (Attempts::Shown#anchor_row). Read-only.
  module Comments
    module_function

    # The comment with its refs and anchor; shown/raw: the try's Attempts::Shown and answer, for the row the anchor points at.
    def block(comment, shown = nil, raw = nil)
      out = { id: comment.id, state: comment.state, reason: comment.reason, anchor: comment.anchor, text_it: comment.text_it, practice_serve_id: comment.practice_serve_id,
              served_event_id: comment.served_event_id, item_instance_id: comment.item_instance_id, item_revision_id: comment.item_revision_id,
              lesson_revision_id: comment.lesson_revision_id, card: comment.card, created_at: comment.created_at.utc.iso8601 }
      row = shown&.anchor_row(comment.anchor, raw)
      out[:anchor_row] = row if row
      out.compact
    end

    # The student's comments chosen by the block (given the scope of the student's comments); with `only`, that comment if the block
    # chose it, else none (the caller answers 404: the comment is not about this answer).
    def list(student, only, shown, raw)
      scope = yield(Comment.where(student_id: student.id).includes(:events).order(:id))
      scope = scope.where(id: only.id) if only
      scope.map { |c| block(c, shown, raw) }
    end
  end
end
