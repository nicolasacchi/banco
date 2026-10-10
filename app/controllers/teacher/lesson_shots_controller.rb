module Teacher
  # The screenshots of a lesson/2 revision's render check (D-249, A12): for the teacher and the guest to look at, and for
  # the operator's acceptance. A page per revision (every card, every viewport, as the student's projection drew it: no
  # answer is in a picture) and the image by content address. The strip inside the topic page is release 1.1.
  class LessonShotsController < Teacher::BaseController
    def index
      @revision = LessonRevision.find_by(id: params[:lesson_revision_id]) or return head(:not_found)
      @subject = @revision.lesson.subject
      @unit = "#{@subject.key}:topic"
      @render = LessonRender.verdict_for(@revision)
      @shots = @render ? @render.shots.sort_by { |s| [ s["card"].to_i, s["viewport"] ] } : []
      @titles = (@revision.body["cards"] || []).to_h { |c| [ c["n"], c["title_it"] ] }
    end

    def show
      revision = LessonRevision.find_by(id: params[:lesson_revision_id]) or return head(:not_found)
      return head(:not_found) unless LessonRender.where(lesson_revision_id: revision.id).any? { |r| r.shots.any? { |s| s["sha256"] == params[:sha256] } }

      bytes = LessonShots.read(params[:sha256]) or return head(:gone)
      response.headers["Cache-Control"] = "private, max-age=31536000, immutable"
      send_data bytes, type: "image/webp", disposition: "inline"
    end
  end
end
