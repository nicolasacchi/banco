# Web listener controllers. Everything here answers only on the web listener
# (enforced by the route constraint); identity comes from EdgeTrust.
class ApplicationController < ActionController::Base
  include EdgeTrust

  # Modern browsers only: the student's computer is known, the interface uses
  # native selects and import maps.
  allow_browser versions: :modern, unless: -> { Rails.env.test? }

  private

  def require_teacher!
    render plain: "Forbidden", status: :forbidden unless current_identity&.teacher?
  end

  def require_student!
    render plain: "Forbidden", status: :forbidden unless current_identity&.student?
  end
end
