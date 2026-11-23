# Comments anywhere (D-304), the student's side: POST /comments writes one comment (idempotent on
# client_comment_id, checked against what this student was shown), GET /comments is "I miei commenti", the list of
# conversations like a mailbox, GET /comments/:id is one conversation like a chat (D-349), POST /comments/:id/reply is
# her follow-up to a teacher's reply (D-342) and POST /comments/:id/withdraw deletes her own comment before any reply (D-397). Students only, official and trial; the teacher, a guest and the teacher's
# preview get 403 (the preview has no route). A comment changes no grade, no attempt, no engine path and nothing of the
# practice ledger. No model answers (firm rule 1).
class CommentsController < ApplicationController
  include StudentCourse

  before_action { response.headers["Cache-Control"] = "no-store" }

  # JSON answer for the page's outbox: "recorded" (also a repeat, of the id or of the same text and place within two minutes, D-388) or "invalid" (final, the outbox drops it).
  def create
    result = Comments::Intake.call(student: acting_student, course_view: course_view, params: params)
    if result.status == :recorded
      render json: { status: "recorded" }
    else
      render json: { status: "invalid", error: result.error.to_s }
    end
  end

  # The student's follow-up to the teacher's reply (D-342). The conversation's script asks for JSON (D-349): "recorded"
  # (also a repeat of the same client_reply_id), "invalid" with the error (final, the outbox drops it) or "missing" (404). A
  # plain form post (no script) is answered with a redirect back to the conversation. A comment that is not hers is a 404.
  def reply
    result = Comments::StudentReply.call(student: acting_student, comment_id: params[:id], text_it: params[:text_it], client_reply_id: params[:client_reply_id])
    if request.format.json?
      return render json: { status: "missing" }, status: :not_found if result.status == :missing

      return render json: (result.status == :recorded ? { status: "recorded", at: result.event.created_at.iso8601 } : { status: "invalid", error: result.error.to_s })
    end
    return head(:not_found) if result.status == :missing

    target = "/comments/#{params[:id].to_i}"
    if result.status == :recorded
      redirect_to target, status: :see_other, notice: I18n.t("comments.reply_sent")
    else
      redirect_to target, status: :see_other, alert: I18n.t("comments.reply_error.#{result.error}", default: I18n.t("comments.reply_error.other"))
    end
  end

  # He deletes his own comment while it has no teacher reply (D-397). The row stays in the ledger (a student_withdrawn event); the list and
  # the conversation no longer show it. A comment that is not his is a 404; one the teacher has answered is refused and stays.
  def withdraw
    result = Comments::StudentWithdraw.call(student: acting_student, comment_id: params[:id])
    return head(:not_found) if result.status == :missing

    if result.status == :recorded
      redirect_to "/comments", status: :see_other, notice: I18n.t("comments.withdrawn")
    else
      redirect_to "/comments/#{params[:id].to_i}", status: :see_other, alert: I18n.t("comments.withdraw_error")
    end
  end

  # The list of the student's conversations. Showing it marks nothing as seen: a reply is seen when its conversation opens.
  def index
    @inbox = Comments::StudentInbox.new(acting_student, tab: params[:tab])
  end

  # One conversation. Opening it is what marks the teacher's replies as seen (a reply_seen row of the student), so the
  # badge and the dot go away. Another student's comment is a 404.
  def show
    @comment = Comment.where(student: acting_student).includes(:events, :subject).find_by(id: params[:id])
    return page_not_found if @comment.nil? || @comment.withdrawn? # D-397: a comment he deleted is not there for him
    if @comment.unread_reply?
      CommentEvent.create!(comment: @comment, kind: "reply_seen", origin: "student", actor: acting_student.key, request_id: nil,
                           remote_addr: "", payload_json: "{}", created_at: Time.current)
      @comment.events.reset
    end
    @inbox = Comments::StudentInbox.new(acting_student, tab: params[:tab])
  end
end
