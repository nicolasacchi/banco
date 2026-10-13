# The poster of a free page (SPEC B4, D-289): the validation screenshot of the page's first state, as WebP, by content address.
# For the student, the teacher and the guest (it is course material). Only a screenshot that a stored page validation names is
# served, so this is not a file server.
class PagePostersController < ApplicationController
  before_action :require_identity!

  def show
    sha = params[:sha].to_s
    return head(:not_found) unless sha.match?(PageShots::SHA) && PageValidation.where("shots_json LIKE ?", "%#{sha}%").any? { |v| v.shots.any? { |s| s["sha256"] == sha } }

    bytes = PageShots.read(sha) or return head(:gone)
    response.headers["Cache-Control"] = "private, max-age=31536000, immutable"
    send_data bytes, type: "image/webp", disposition: "inline"
  end

  private

  def require_identity!
    head :forbidden unless current_identity&.student? || current_identity&.reader?
  end
end
