# The public API's tokens in tests (D-327): one token per role, the request helper, and the environment the teacher
# token needs (the teacher list and the decisions flag).
module PublicApiTokens
  TEACHER_LOGIN = "nik".freeze

  def self.included(base)
    base.setup do
      @saved_public_env = ENV.to_h.slice("BANCO_TEACHER_USERS", "BANCO_DECISIONS_ENABLED")
      ENV["BANCO_TEACHER_USERS"] = TEACHER_LOGIN
      ENV["BANCO_DECISIONS_ENABLED"] = "1"
    end
    base.teardown do
      %w[BANCO_TEACHER_USERS BANCO_DECISIONS_ENABLED].each { |k| @saved_public_env.key?(k) ? ENV[k] = @saved_public_env[k] : ENV.delete(k) }
    end
  end

  # A token of the role as a string; a teacher token acts as TEACHER_LOGIN.
  def issue_token(role, expires_at: 30.days.from_now, teacher_login: nil)
    teacher_login ||= TEACHER_LOGIN if role == "teacher"
    ApiToken.issue!(role: role, label: "public api test #{role}", expires_at: expires_at, teacher_login: teacher_login)
  end

  def public_id(token) = Banco::TokenAuth::FORMAT.match(token)[1]

  # A request on the API listener with this token (nil: no Authorization header). body: a Hash sent as JSON.
  def api_as(token, path, method: :get, body: nil, headers: {}, remote_addr: "127.0.0.1")
    headers = headers.merge("Authorization" => "Bearer #{token}") if token
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil, remote_addr: remote_addr)
  end

  def json = response.parsed_body
end
