module Api
  # Agent API (API listener only). Token auth; Remote-* headers are ignored.
  # Every response carries X-Banco-Contract so the CLI can detect drift.
  class BaseController < ActionController::API
    before_action :set_contract_header
    before_action :authenticate!

    private

    # The agent asked for a dry run: nothing is written and no job is queued.
    def dry_run? = request.headers["X-Banco-Dry-Run"] == "1"

    # {code, field, message, next} (plus extra members) with the status of the code.
    def refuse(code, field, message, next_step, status, **extra)
      render json: { code: code, field: field, message: message, next: next_step }.merge(extra), status: status
    end

    # Answers 422 with the first error code at the top and every finding below, when
    # there is any error. Returns true when it answered.
    def refuse_findings(findings, next_step, **extra)
      first = findings.errors.first or return false

      refuse(first.code, first.field, first.message, next_step, 422,
             **extra.merge(codes: findings.codes, findings: findings.map(&:to_h)))
      true
    end

    # The session of X-Banco-Session (A-04), checked against the roles the endpoint
    # takes. Answers and returns nil when there is none, it is unknown or it has
    # another role. With item: also the provider rules of the role (A-08).
    def require_session(*roles, item: nil, next_step: "banco session new --role ROLE --agent NAME --model MODEL")
      raw = request.headers["X-Banco-Session"].to_s
      session = AgentSession.find_by(id: raw) if raw.match?(AgentSession::ID)
      unless session
        refuse("E-SESSION", "X-Banco-Session", raw.empty? ? "this command needs a session: set BANCO_SESSION" : "no session #{raw.first(20).inspect}", next_step, 422)
        return nil
      end
      if session.token_id && session.token_id != @token.id
        refuse("E-SESSION", "X-Banco-Session", "session #{session.id} belongs to another token", next_step, 422)
        return nil
      end
      unless ApiToken.session_roles(@token.role).include?(session.role)
        refuse("E-SESSION-ROLE", "X-Banco-Session", "a #{@token.role} token cannot act in a #{session.role} session", next_step, 422)
        return nil
      end
      unless roles.include?(session.role)
        refuse("E-SESSION-ROLE", "X-Banco-Session", "this command is for a #{roles.join(' or ')} session; session #{session.id} is a #{session.role} session", next_step, 422)
        return nil
      end
      reason = Providers.refusal(session, item: item)
      if reason
        refuse("E-PROVIDER-NOT-ALLOWED", "X-Banco-Session", reason, "banco session new --role #{session.role} --agent NAME --model MODEL (see config/banco/providers.yml)", 422)
        return nil
      end
      session
    end

    def parse_json_body
      body = JSON.parse(request.raw_post)
      return body if body.is_a?(Hash)

      refuse("E-FILES", "body", "the request body must be a JSON object", "banco schema", 422)
      nil
    rescue JSON::ParserError => e
      refuse("E-FILES", "body", "the request body is not JSON: #{e.message.first(80)}", "banco schema", 422)
      nil
    end

    def authenticate!
      @token = Banco::TokenAuth.authenticate(request.authorization)
      return if @token

      response.set_header("WWW-Authenticate", "Bearer")
      render json: { code: "E-AUTH", field: "authorization", message: "token missing or invalid",
                     next: "banco schema" }, status: :unauthorized
    end

    def set_contract_header
      response.set_header("X-Banco-Contract", Contract.digest)
    end
  end
end
