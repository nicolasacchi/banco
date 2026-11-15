module Comments
  # The only writer of the teacher's side of a comment (D-304): a reply, "read", "resolved", "reopened" (and in C2
  # "sent_back") as one append-only comment_events row. A reply is the teacher's own words, from the browser or from
  # the operator's console or, with a teacher token, the API (D-327); never a guest, a student, the preview or a content
  # agent. The guards are the decisions' guards, by the same function (DecisionRecorder.refusal): BANCO_DECISIONS_ENABLED, the web listener, a
  # peer of the edge proxy, a Remote-User of BANCO_TEACHER_USERS in the teacher group, a valid CSRF token and a
  # computer that is not the student's; or the console or API origin (BANCO_TEACHER_USERS login, flag on).
  #
  #   Comments::Responder.call(request: request, comment_id: 3, kind: "reply", text_it: "Guarda la scheda 2.")
  #
  # Raises DecisionRecorder::Refused (403), ::Missing (404), ::Invalid (422, with reasons).
  class Responder
    def self.call(**args) = new(**args).call

    def initialize(request:, comment_id:, kind:, text_it: nil, reason_it: nil, request_id: nil)
      @request = request
      @comment_id = comment_id
      @kind = kind.to_s
      @text = text_it.to_s.gsub(/\r\n?/, "\n").strip
      @reason = reason_it.to_s.strip
      @request_id = request_id
    end

    def call
      raise DecisionRecorder::Invalid, "unknown comment action #{@kind.inspect}" unless CommentEvent::TEACHER_KINDS.include?(@kind)

      reason = DecisionRecorder.refusal(@request)
      raise DecisionRecorder::Refused, reason if reason

      CommentEvent.transaction do
        comment = Comment.includes(:events).find_by(id: Integer(@comment_id.to_s, exception: false)) or raise DecisionRecorder::Missing, "no comment #{@comment_id.to_s.first(20).inspect}"
        validate!(comment)
        CommentEvent.create!(comment: comment, kind: @kind, origin: origin, actor: @request.get_header("HTTP_REMOTE_USER").to_s.strip,
                             text_it: @kind == "reply" ? @text : nil, remote_addr: @request.remote_addr.to_s.first(60),
                             request_id: @request_id.presence || @request.request_id.presence || SecureRandom.uuid,
                             payload_json: JSON.generate(payload), created_at: Time.current)
      end
    end

    private

    # The CHECK of comment_events.origin: web, console or api.
    def origin
      case @request
      when DecisionRecorder::Console then "console"
      when DecisionRecorder::Api then "api"
      else "web"
      end
    end

    # The reason, for the API the token that acted, for the console the host OS user (as a decision keeps it in its
    # user_agent: D-334).
    def payload
      doc = @reason.empty? ? {} : { "reason_it" => @reason.first(1000) }
      doc["token"] = @request.token_id if @request.is_a?(DecisionRecorder::Api)
      doc["os_user"] = @request.os_user if @request.is_a?(DecisionRecorder::Console) && @request.os_user.present?
      doc
    end

    def validate!(comment)
      state = comment.state
      case @kind
      when "reply"
        raise DecisionRecorder::Invalid, "the reply is empty" if @text.empty?
        raise DecisionRecorder::Invalid, "the reply is longer than #{CommentEvent::REPLY_MAX} characters" if @text.length > CommentEvent::REPLY_MAX
        raise DecisionRecorder::Invalid, "the comment is closed: reopen it first" if state == "closed"
      when "read" then raise DecisionRecorder::Invalid, "the comment is already #{state}" unless state == "sent"
      when "resolved" then raise DecisionRecorder::Invalid, "the comment is already closed" if state == "closed"
      when "reopened" then raise DecisionRecorder::Invalid, "the comment is not closed" unless state == "closed"
      end
    end
  end
end
