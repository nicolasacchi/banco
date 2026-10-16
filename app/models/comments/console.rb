module Comments
  # The operator's console path to the teacher's side of a comment (D-304, like D-260 for decisions): bin/rails
  # banco:comments:reply|resolve|reopen|read. Never over HTTP, never an API. It builds a DecisionRecorder::Console
  # origin for a login of BANCO_TEACHER_USERS and hands the action to Comments::Responder, the only writer, so every
  # guard holds (flag on, a teacher of the list, the comment's state). A dry run (the default) runs the whole thing
  # inside a savepoint that is rolled back; confirm: true keeps the row. The reply is the operator's own words,
  # delivered as the teacher's reply with origin "console"; the row says so.
  class Console
    Result = Struct.new(:ok, :recorded, :event, :errors, keyword_init: true)

    ACTIONS = { "reply" => "reply", "read" => "read", "resolve" => "resolved", "reopen" => "reopened" }.freeze

    def self.call(**args) = new(**args).call

    def initialize(action:, id:, teacher:, text_it: nil, reason: nil, confirm: false, os_user: DecisionRecorder::Console.default_os_user)
      @action = action.to_s
      @id = id
      @teacher = teacher.to_s
      @text = text_it
      @reason = reason
      @confirm = confirm
      @os_user = os_user
    end

    def call
      kind = ACTIONS[@action] or return fail_with("unknown action #{@action.inspect}")
      origin = DecisionRecorder::Console.new(login: @teacher, os_user: @os_user)
      event = nil
      CommentEvent.transaction(requires_new: true) do
        event = Responder.call(request: origin, comment_id: @id, kind: kind, text_it: @text, reason_it: @reason)
        raise ActiveRecord::Rollback unless @confirm
      end
      Result.new(ok: true, recorded: @confirm, event: event, errors: [])
    rescue DecisionRecorder::Refused => e
      fail_with("refused: #{e.reason}")
    rescue DecisionRecorder::Missing => e
      fail_with(e.message)
    rescue DecisionRecorder::Invalid => e
      fail_with(*e.reasons)
    end

    private

    def fail_with(*errors) = Result.new(ok: false, recorded: false, errors: errors)
  end
end
