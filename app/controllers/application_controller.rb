# Web listener controllers. Everything here answers only on the web listener
# (enforced by the route constraint); identity comes from EdgeTrust.
class ApplicationController < ActionController::Base
  include EdgeTrust

  # Modern browsers only: the student's computer is known, the interface uses
  # native selects and import maps.
  allow_browser versions: :modern, unless: -> { Rails.env.test? }

  helper_method :current_identity, :reader_only?, :trial_account?, :logout_url

  # A guest: reads the teacher's pages, decides nothing.
  def reader_only? = current_identity&.guest? == true

  # A trial student: adult testing the student's pages; the results do not count.
  def trial_account? = current_identity&.trial_student? == true

  def logout_url = Banco::EdgeProxy.logout_url

  private

  def require_teacher!
    render plain: "Forbidden", status: :forbidden unless current_identity&.teacher?
  end

  # Teacher or guest: the teacher's pages that only read.
  def require_reader!
    render plain: "Forbidden", status: :forbidden unless current_identity&.reader?
  end

  def require_student!
    return if current_identity&.student?

    if current_identity&.unconfigured_student?
      render "shared/not_configured", layout: false, status: :forbidden
    else
      render plain: "Forbidden", status: :forbidden
    end
  end
end
