# Comments anywhere (D-304), the student's side: POST /comments writes one comment (idempotent on
# client_comment_id, checked against what this student was shown), GET /comments is "I miei commenti" and
# POST /comments/:id/reply is her follow-up to a teacher's reply (D-342). Students only,
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

  # The student's follow-up to the teacher's reply (D-342): a plain form post, answered with a redirect back to the
  # comment. A comment that is not hers is a 404; a repeat of the same form is recorded once.
  def reply
    result = Comments::StudentReply.call(student: acting_student, comment_id: params[:id], text_it: params[:text_it], client_reply_id: params[:client_reply_id])
    return head(:not_found) if result.status == :missing

    target = "/comments#comment-#{params[:id].to_i}"
    if result.status == :recorded
      redirect_to target, status: :see_other, notice: I18n.t("comments.reply_sent")
    else
      redirect_to target, status: :see_other, alert: I18n.t("comments.reply_error.#{result.error}", default: I18n.t("comments.reply_error.other"))
    end
  end

  # The student's own comments with their state and the teacher's replies. Showing them is what marks the replies as
  # seen (a reply_seen row of the student), so the badge goes away.
  def index
    @comments = Comment.where(student: acting_student).includes(:events, :subject).order(id: :desc).to_a
    @unread = @comments.select(&:unread_reply?)
    @unread.each do |comment|
      CommentEvent.create!(comment: comment, kind: "reply_seen", origin: "student", actor: acting_student.key, request_id: nil,
                           remote_addr: "", payload_json: "{}", created_at: Time.current)
    end
  end
end
