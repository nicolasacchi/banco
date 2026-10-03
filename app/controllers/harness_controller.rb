# The harness listener (port 3200, internal): the page and the files Chrome loads to
# run an agent's generator or verify (A-02). It is a plain ActionController::API:
# no session, no cookie, no CSRF token, nothing of the app's own is reachable from
# the page. The run token in the address is the only capability.
class HarnessController < ActionController::API
  before_action :harden_headers

  # GET /h/:token/:file
  def show
    payload = Validation::Harness.verify(params[:token])
    return head :not_found unless payload

    name = params[:file]
    text =
      if Validation::Harness::PAGES.include?(name) then Validation::Harness.file(name)
      elsif Validation::Harness::MODULES.include?(name) then Validation::Harness.source(payload, name)
      end
    return head :not_found unless text

    response.set_header("Content-Security-Policy", Validation::Harness::CSP) if name == "harness.html"
    send_data text, type: Validation::Harness.content_type(name), disposition: "inline"
  end

  # GET /lib/:file: the two libraries a generator may import.
  def lib
    name = params[:file]
    return head :not_found unless Validation::Harness::LIBS.include?(name)

    send_data Validation::Harness.file(name), type: Validation::Harness.content_type(name), disposition: "inline"
  end

  private

  def harden_headers
    response.set_header("Cache-Control", "no-store")
    response.set_header("X-Content-Type-Options", "nosniff")
    response.set_header("Referrer-Policy", "no-referrer")
  end
end
