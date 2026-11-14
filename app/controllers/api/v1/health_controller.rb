module Api
  module V1
    # GET /api/v1/health: the parts of the installation (Health.check). 200 whether or
    # not ok is true: the body says what is wrong; the caller reads "ok".
    #
    # A reader token (bot_read, teacher) or a request through the public edge (D-327) never starts the browser probes (they hold
    # one of the five threads for up to 30 s each) and never sees an exception's class or message: chrome, chrome_egress and
    # harness say "skipped", a failing part says only "error".
    class HealthController < Api::BaseController
      def show
        outside = reader? || Banco::EdgeProxy.include?(request.remote_addr)
        report = Health.check(chrome: params[:chrome] != "0" && !outside)
        render json: outside ? Health.redact(report) : report
      end
    end
  end
end
