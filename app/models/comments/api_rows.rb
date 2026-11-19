module Comments
  # The student's comments as the API lists them (D-327, GET /api/v1/comments) and the digest repeats them (D-333): the
  # filtered list and the one-line row. One place for both, so the digest never has a second query or a second shape.
  # Read-only.
  module ApiRows
    module_function

    # Newest first; state "open" (the default) is every state but closed. Filters are the controller's checked values.
    def list(state: "open", subject: nil, who: nil, reason: nil, kind: nil)
      inbox = Comments::Inbox.new(subject: subject, who: who, reason: reason, kind: kind, type: "comment", state: (state if Comment::STATES.include?(state)))
      rows = inbox.comments
      state == "open" ? rows.reject { |c| c.state == "closed" } : rows
    end

    def summary(comment)
      { id: comment.id, state: comment.state, reason: comment.reason, student: comment.student.key, trial: comment.trial, page_kind: comment.page_kind,
        page_path: comment.page_path, subject: comment.subject&.key, text_it: comment.text_it, replies: comment.replies.size,
        unread_reply: comment.unread_reply?, created_at: comment.created_at.utc.iso8601,
        # D-371: only for a comment that waits for the teacher: hours left of the promised answer time (negative once late), and whether the student wrote after the last reply.
        due_in_hours: comment.due_in_hours, student_followup: (true if comment.student_followup?) }.compact
    end
  end
end
