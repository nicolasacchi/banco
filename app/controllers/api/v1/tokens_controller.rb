module Api
  module V1
    # GET /api/v1/token: the token of the request as the registry knows it (D-330), never its secret. Any token role; the
    # expiry is the effective one, so a public token used today shows the date its renewal moved it to.
    class TokensController < Api::BaseController
      def show
        token = ApiToken.find_by(public_id: @token.id)
        return refuse("E-NOT-FOUND", "authorization", "this token is not in the registry", "banco token", 404) unless token

        render json: {
          public_id: token.public_id,
          role: token.role,
          teacher: token.teacher_login,
          label: token.label,
          created_at: token.created_at.utc.iso8601,
          expires_at: token.effective_expires_at&.utc&.iso8601,
          renews_on_use: token.renews_on_use?,
          lifetime_days: token.lifetime_days,
          revoked: false
        }
      end
    end
  end
end
