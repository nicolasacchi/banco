# Web listener controllers (and the teacher's GET pages on the view listener, D-332). Everything here answers only on
# the listener its route constraint names; identity comes from EdgeTrust.
class ApplicationController < ActionController::Base
  include EdgeTrust

  # Modern browsers only: the student's computer is known, the interface uses
  # native selects and import maps.
  allow_browser versions: :modern, unless: -> { Rails.env.test? }

  # The view listener (D-332): 404 when the feature is off or the peer is not the edge proxy, 403 for any method
  # but GET and HEAD, 403 for a page without an active view session. /v skips the last (it opens the session).
  before_action :guard_view_listener, if: :view_listener?
  before_action :require_view_session, if: :view_listener?

  helper_method :current_identity, :reader_only?, :trial_account?, :logout_url, :view_session?

  # A guest: reads the teacher's pages, decides nothing.
  def reader_only? = current_identity&.guest? == true

  # A trial student: adult testing the student's pages; the results do not count.
  def trial_account? = current_identity&.trial_student? == true

  # A view link's visitor: reads like a guest, has no login to leave (the menu hides «Esci»).
  def view_session? = current_identity&.view_link? == true

  def logout_url = Banco::EdgeProxy.logout_url

  private

  # A designed page for a refusal (D-306): the status stays 403 or 404, the body says the same to everyone.
  def render_error(status)
    render "shared/error", formats: [ :html ], layout: false, status: status, locals: { status: status }
  end

  def guard_view_listener
    if !ViewLinks.enabled? || !Banco::EdgeProxy.include?(request.remote_addr)
      render_error(:not_found)
    elsif !(request.get? || request.head?)
      render_error(:forbidden)
    end
  end

  def require_view_session
    render_error(:forbidden) unless current_identity
  end

  def require_teacher!
    render_error(:forbidden) unless current_identity&.teacher?
  end

  # Teacher or guest: the teacher's pages that only read.
  def require_reader!
    render_error(:forbidden) unless current_identity&.reader?
  end

  def require_student!
    return if current_identity&.student?

    if current_identity&.unconfigured_student?
      render "shared/not_configured", layout: false, status: :forbidden
    else
      render_error(:forbidden)
    end
  end
end
