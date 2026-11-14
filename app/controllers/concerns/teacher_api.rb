# What the API controllers that act as the teacher share (D-327): decisions and comment actions with a teacher token.
# The origin names the token's login, the token and the client address; the answer of a refusal maps the failure of
# DecisionConsole or Comments::Console to a status and a code of the registry.
module TeacherApi
  private

  # A DecisionRecorder::Api for this request: the teacher login stored on the token (which must still be in
  # BANCO_TEACHER_USERS, checked by the recorder), the token's public id, the address and the route for the audit row.
  def teacher_origin
    DecisionRecorder::Api.new(login: @token.teacher_login, token_id: @token.id, remote_addr: client_address, path: "#{request.method} #{request.path}",
                                  request_id: request.request_id, user_agent: request.user_agent.to_s.first(300))
  end

  # The address of the client as the edge proxy saw it, for the audit trail only: identity is the token. It never
  # decides anything; a malformed forwarding header falls back to the peer.
  def client_address
    request.remote_ip.to_s.presence || request.remote_addr
  rescue ActionDispatch::RemoteIp::IpSpoofAttackError
    request.remote_addr
  end

  # The answer of a Result that is not ok (a dry run included: it shows why nothing could be recorded). invalid_code is the
  # code of the 422 (E-DECISION-INVALID or E-COMMENT-INVALID).
  def answer_failure(result, invalid_code:, next_step:)
    case result.failure
    when :refused
      refuse("E-TEACHER-REFUSED", "authorization", "refused: #{result.reason}", "ask the operator: BANCO_DECISIONS_ENABLED and BANCO_TEACHER_USERS are the operator's", 403, reason: result.reason.to_s)
    when :missing
      refuse("E-NOT-FOUND", "id", result.errors.first, next_step, 404)
    else
      refuse(invalid_code, "params", result.errors.join("; "), next_step, result.failure == :duplicate ? 409 : 422, reasons: result.errors)
    end
  end
end
