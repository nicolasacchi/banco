# The redemption of a view link (D-332): GET /v?view_token=... on the view listener. A valid token sets the encrypted
# session cookie (the link's id only, host-only, no domain) and sends the visitor to the link's page; any other token
# (unknown, expired, revoked, feature off) is the same designed 410. The guards of ApplicationController run first
# (flag, edge peer, GET/HEAD; a HEAD redeems nothing). The token is a query parameter, so it is filtered from the log (view_token) and the
# page tells the browser not to send it on as a referrer or to keep it.
class ViewLinksController < ApplicationController
  skip_before_action :require_view_session
  # A refused POST is a 403 from guard_view_listener, never the forgery check's 422: there is no form on this listener.
  skip_forgery_protection

  def redeem
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
    return head(:ok) if request.head? # link unfurlers and probes: no redemption, no cookie

    token = params[:view_token]
    link = ViewLinks.redeem(token) if token.is_a?(String)
    return render_error(:gone) unless link

    cookies.encrypted[EdgeTrust::VIEW_COOKIE] = {
      value: { "id" => link.id }, expires: link.expires_at, httponly: true, secure: Rails.env.production?, same_site: :lax
    }
    redirect_to link.path, status: :see_other
  end

  # Any method but GET and HEAD on this listener: guard_view_listener has already answered 403 before this runs.
  def refuse = render_error(:forbidden)
end
