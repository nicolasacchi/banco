module Teacher
  # What the teacher has read on a topic page (D-240): "Ho letto la lezione" (part=lesson) and an exercise seen
  # (part=exercise, item_revision_id). An app event like the views the gates read, never a decision; a guest, the
  # student's computer and a topic revision that is not the latest write nothing.
  class SeenController < Teacher::BaseController
    before_action :require_teacher!

    def create
      return head(:forbidden) if request.cookies[DecisionRecorder::DEVICE_COOKIE].present?

      revision = TopicRevision.find_by(id: params[:revision_id]) or return head(:not_found)
      return render(json: { status: "stale" }, status: :conflict) unless revision.lesson.topic_revisions.maximum(:seq) == revision.seq

      case params[:part].to_s
      when "lesson" then Teacher::TopicSeen.record_lesson(revision)
      when "exercise" then return head(:not_found) unless Teacher::TopicSeen.record_exercise(revision, params[:item_revision_id].to_i)
      else return head(:unprocessable_entity)
      end
      render json: { status: "ok", part: params[:part].to_s }
    end
  end
end
