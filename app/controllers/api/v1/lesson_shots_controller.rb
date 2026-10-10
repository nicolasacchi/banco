module Api
  module V1
    # The screenshots of the render check of a lesson revision (D-249, A12.2): the list, and a file by its content
    # address. For the agent that wrote or reviews the lesson, so that a multimodal model looks at every card
    # (`banco lesson shots REV --dir D`). Nothing here decides.
    class LessonShotsController < Api::BaseController
      before_action :load_revision

      # GET /api/v1/lesson-revisions/:revision/shots
      def index
        row = LessonRender.verdict_for(@revision)
        return refuse("E-NOT-FOUND", "shots", "revision #{@revision.id} has no render yet", "banco lesson status #{@revision.id}", 404) unless row

        shots = row.shots.map do |s|
          s.slice("card", "level", "viewport", "sha256", "bytes", "width", "height").merge("available" => LessonShots.exist?(s["sha256"]),
                                                                                         "path" => "/api/v1/lesson-revisions/#{@revision.id}/shots/#{s['sha256']}")
        end
        render json: { revision_id: @revision.id, lesson: @revision.lesson.key, render_id: row.id, status: row.status, errors: row.errors_list, shots: shots }
      end

      # GET /api/v1/lesson-revisions/:revision/shots/:sha
      def show
        known = LessonRender.where(lesson_revision_id: @revision.id).any? { |r| r.shots.any? { |s| s["sha256"] == params[:sha] } }
        return refuse("E-NOT-FOUND", "sha", "revision #{@revision.id} has no such image", "banco lesson shots #{@revision.id} --dir DIR", 404) unless known

        bytes = LessonShots.read(params[:sha])
        return refuse("E-NOT-FOUND", "sha", "the image was removed by the purge (immagine rimossa)", "banco lesson status #{@revision.id}", 404) unless bytes

        send_data bytes, type: "image/webp", disposition: "inline"
      end

      private

      def load_revision
        @revision = LessonRevision.find_by(id: params[:revision])
        return if @revision&.lesson2?

        refuse("E-NOT-FOUND", "revision", "no banco.lesson/2 revision #{params[:revision].to_s.first(20).inspect}", "banco lessons list --subject KEY", 404)
      end
    end
  end
end
