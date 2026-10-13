module Teacher
  # The screenshots of a page validation (D-290, SPEC B7): for the teacher and the guest to look at (every seed, the narrow
  # state, reduced motion, the fallback, the three states of the scripted session), and the image by content address. Read-only.
  class PageShotsController < Teacher::BaseController
    def index
      @revision = PageRevision.find_by(id: params[:page_revision_id]) or return head(:not_found)
      @subject = @revision.page.subject
      @unit = "#{@subject.key}:topic"
      @validation = @revision.verdict
      @shots = @validation ? @validation.shots : []
    end

    def show
      revision = PageRevision.find_by(id: params[:page_revision_id]) or return head(:not_found)
      return head(:not_found) unless revision.validations.any? { |v| v.shots.any? { |s| s["sha256"] == params[:sha256] } }

      bytes = PageShots.read(params[:sha256]) or return head(:gone)
      response.headers["Cache-Control"] = "private, max-age=31536000, immutable"
      send_data bytes, type: "image/webp", disposition: "inline"
    end
  end
end
