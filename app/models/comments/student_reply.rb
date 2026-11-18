module Comments
  # The one writer of the student's follow-up to the teacher's reply (D-342): a `student_reply` row of comment_events,
  # origin student, the student's own words (1..2000 characters, Comment::TEXT_MAX). Only on the student's own comment and only once the
  # comment has a teacher reply. Idempotent on client_reply_id (the form's hidden id, a repeat of the same one by the
  # same student is recorded once; the id is the event's request_id, one per student). It changes no grade, no
  # attempt and nothing of the practice ledger; the comment's state is derived again from its events (Comment#state).
  #
  #   Comments::StudentReply.call(student: s, comment_id: 3, text_it: "Grazie, ora capisco.", client_reply_id: "r-...")
  #   # => Result(status:, event:, error:)   status: :recorded, :invalid or :missing
  class StudentReply
    Result = Struct.new(:status, :event, :error, keyword_init: true)

    def self.call(**args) = new(**args).call

    def initialize(student:, comment_id:, text_it:, client_reply_id:)
      @student = student
      @comment_id = comment_id
      @text = text_it.to_s.gsub(/\r\n?/, "\n").strip
      @client_id = client_reply_id.to_s
    end

    def call
      return Result.new(status: :invalid, error: "not a student") unless @student.kind == "student"
      return Result.new(status: :invalid, error: "client_reply_id") unless @client_id.match?(Intake::ID_FORMAT)

      comment = Comment.includes(:events).find_by(id: Integer(@comment_id.to_s, exception: false), student_id: @student.id)
      return Result.new(status: :missing, error: "comment") unless comment

      request_id = "student-reply:#{@student.id}:#{@client_id}"
      existing = CommentEvent.find_by(request_id: request_id)
      return Result.new(status: existing.comment_id == comment.id ? :recorded : :invalid, event: existing, error: ("client_reply_id" unless existing.comment_id == comment.id)) if existing

      return Result.new(status: :invalid, error: "text_it") if @text.empty? || @text.length > Comment::TEXT_MAX
      return Result.new(status: :invalid, error: "no_teacher_reply") if comment.replies.empty?

      begin
        event = CommentEvent.create!(comment: comment, kind: "student_reply", origin: "student", actor: @student.key, text_it: @text,
                                     request_id: request_id, remote_addr: "", payload_json: "{}", created_at: Time.current)
      rescue ActiveRecord::RecordNotUnique
        event = CommentEvent.find_by!(request_id: request_id, comment_id: comment.id)
      end
      Result.new(status: :recorded, event: event)
    end
  end
end
