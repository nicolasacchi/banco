module Api
  module V1
    # GET /api/v1/health: the parts of the installation (Health.check). 200 whether or
    # not ok is true: the body says what is wrong; the caller reads "ok".
    class HealthController < Api::BaseController
      def show
        render json: Health.check(chrome: params[:chrome] != "0")
      end
    end
  end
end
