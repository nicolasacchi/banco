module Api
  module V1
    # Draw a lesson revision's render again without a new revision (D-402). Only when its latest verdict failed on the server's time limits alone
    # (LessonRender#timeout_only?): the same lesson passes when the Chrome lane is less busy, and a new revision would only change the number. The
    # content roles may ask (a bot_read or teacher token cannot POST, Api::BaseController); the job is RenderLessonRevisionJob.
    class LessonRendersController < Api::BaseController
      # POST /api/v1/lesson-revisions/:revision/render
      def create
        revision = LessonRevision.find_by(id: params[:revision])
        return refuse("E-NOT-FOUND", "revision", "no banco.lesson/2 revision #{params[:revision].to_s.first(20).inspect}", "banco lessons list --subject KEY", 404) unless revision&.lesson2?

        latest = LessonRender.latest_for(revision)
        unless latest&.timeout_only?
          return refuse("E-RETRY-REFUSED", "revision", "the latest render of revision #{revision.id} (#{latest ? latest.status : 'none'}) did not fail on the server's time limits alone: " \
                        "only that kind is drawn again without a new revision", "banco lesson status #{revision.id}", 409)
        end
        return render json: { dry_run: true, would_enqueue: true, render_id: latest.id } if dry_run?

        RenderLessonRevisionJob.perform_later(revision.id, latest.id)
        render json: { revision_id: revision.id, enqueued: true, render_id: latest.id, next: "the render runs again; ask: banco lesson status #{revision.id}" }, status: :accepted
      end
    end
  end
end
