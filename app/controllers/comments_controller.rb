# Comments anywhere (D-304), the student's side: POST /comments writes one comment (idempotent on
# client_comment_id, checked against what this student was shown), GET /comments is "I miei commenti". Students only,
# official and trial; the teacher, a guest and the teacher's preview get 403 (the preview has no route). A comment
# changes no grade, no attempt, no engine path and nothing of the practice ledger. No model answers (firm rule 1).
class CommentsController < ApplicationController
  include StudentCourse

  before_action { response.headers["Cache-Control"] = "no-store" }

  # JSON answer for the page's outbox: "recorded" (also a repeat) or "invalid" (final, the outbox drops it).
  def create
    result = Comments::Intake.call(student: acting_student, course_view: course_view, params: params)
    if result.status == :recorded
      render json: { status: "recorded" }
    else
      render json: { status: "invalid", error: result.error.to_s }
    end
  end

  # The student's own comments with their state and the teacher's replies. Showing them is what marks the replies as
  # seen (a reply_seen row of the student), so the badge goes away.
  def index
    @comments = Comment.where(student: acting_student).includes(:events).order(id: :desc).to_a
    @unread = @comments.select(&:unread_reply?)
    @unread.each do |comment|
      CommentEvent.create!(comment: comment, kind: "reply_seen", origin: "student", actor: acting_student.key, request_id: nil,
                           remote_addr: "", payload_json: "{}", created_at: Time.current)
    end
  end
end
