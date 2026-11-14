module Api
  # Agent API (API listener only). Token auth; Remote-* headers are ignored.
  # Every response carries X-Banco-Contract so the CLI can detect drift.
  #
  # Token roles (D-327): the content agents (agent_claude, agent_omp, ci) read and write content under their sessions;
  # bot_read only reads (any non-GET answers 403 E-AUTH, reason read_only_token); teacher reads the same and writes only
  # where a controller says teacher_writes (decisions and comment actions), never content.
  class BaseController < ActionController::API
    class_attribute :teacher_writes, instance_accessor: false, default: false

    # Nothing of the API is cached: answers carry the student's words and the teacher's views (D-327).
    before_action :set_no_store
    before_action :authenticate!
    # The contract digest goes to a caller that holds a token; a wrong token gets 401 and nothing else.
    before_action :set_contract_header
    before_action :enforce_token_scope!
    # A public token renews itself on use (D-330): only a request that passed the checks above renews it.
    before_action :renew_token!

    private

    # A renewal that fails (the database busy or locked) is logged and the request goes on: the token is still valid, and
    # the next request renews it.
    def renew_token!
      @token.renew!
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("token #{@token.id}: renewal failed (#{e.class}: #{e.message.first(200)}); the request goes on")
    end

    # A token of the public API's reading roles (bot_read, teacher): it needs no session to read, since a session only
    # attributes writes (D-327), and it sees every opinion and every answer the teacher's pages show.
    def reader? = ApiToken.reader?(@token.role)

    # The commands only these token roles may use; any other role is 403 E-AUTH (reason token_role).
    def require_token_roles(*roles)
      return true if roles.include?(@token.role)

      refuse("E-AUTH", "authorization", "a #{@token.role} token cannot use this command: it needs a #{roles.join(' or ')} token", "banco schema", 403, reason: "token_role")
      false
    end

    # A request that came through the edge proxy (Traefik, api.banco.scc.im) is the Internet's: only the public roles
    # (bot_read, teacher) may use it, so a leaked content-agent token does nothing from outside. The local agents reach
    # the listener on loopback and are not affected. bot_read never writes; teacher writes only through a controller with
    # teacher_writes; a teacher token whose login is no longer in BANCO_TEACHER_USERS is refused even to read (the operator
    # removes a teacher from the list to cut the token).
    def enforce_token_scope!
      if !reader? && Banco::EdgeProxy.include?(request.remote_addr)
        return refuse("E-AUTH", "authorization", "a #{@token.role} token cannot be used through the public host", "use a bot_read or teacher token here; content agents use the local listener", 403, reason: "not_public_role")
      end
      return unless reader?

      unless teacher_login_listed?
        return refuse("E-AUTH", "authorization", "the teacher of this token is no longer on the teacher list", "ask the operator for a new token", 403, reason: "teacher_not_listed")
      end
      return if request.get? || request.head?

      if @token.role == "bot_read"
        refuse("E-AUTH", "authorization", "a bot_read token only reads: #{request.method} is refused", "use a teacher token to decide or answer a comment", 403, reason: "read_only_token")
      elsif !self.class.teacher_writes
        refuse("E-AUTH", "authorization", "a teacher token only decides and answers comments: this command writes content", "use a content agent's token", 403, reason: "teacher_token_no_content")
      end
    end

    def teacher_login_listed? = @token.role != "teacher" || Banco::EdgeProxy.teacher_users.include?(@token.teacher_login.to_s)

    # The agent asked for a dry run: nothing is written and no job is queued.
    def dry_run? = request.headers["X-Banco-Dry-Run"] == "1"

    # The reserved dry run (lesson submit --dry-run --allow-reserved): honoured only together with the dry run header, so a request
    # that stores can never carry a reserved piece.
    def allow_reserved? = dry_run? && request.headers["X-Banco-Allow-Reserved"] == "1"

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
    def require_session(*roles, item: nil, finding: nil, next_step: "banco session new --role ROLE --agent NAME --model MODEL")
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
      reason = Providers.refusal(session, item: item, finding: finding)
      if reason
        refuse("E-PROVIDER-NOT-ALLOWED", "X-Banco-Session", reason, "banco session new --role #{session.role} --agent NAME --model MODEL (see config/banco/providers.yml)", 422)
        return nil
      end
      session
    end

    # For the endpoints that do not need a session (graph and blueprint submits, D-152):
    # no X-Banco-Session is fine (returns [true, nil]); a header that is not a session of
    # this token in an author role is refused, so a shell variable that holds an error
    # message is never taken for "no session". Returns [ok, session].
    def optional_author_session
      return [ true, nil ] if request.headers["X-Banco-Session"].to_s.strip.empty?

      session = require_session("author")
      [ !session.nil?, session ]
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
      render json: { code: "E-AUTH", field: "authorization", message: "token missing, invalid, expired or revoked",
                     next: "banco schema" }, status: :unauthorized
    end

    def set_contract_header
      response.set_header("X-Banco-Contract", Contract.digest)
    end

    def set_no_store
      response.set_header("Cache-Control", "no-store")
    end
  end
end
