module Comments
  # The one writer of the student's own deletion of a comment (D-397): a `student_withdrawn` row of comment_events, origin
  # student, no text. The comment and its events stay in the ledger (append-only); the state derives from the row
  # (Comment#state: "withdrawn"), his lists hide it, and the teacher and the API still see it. Only on the student's own comment
  # and only while it has no teacher reply: once the teacher has answered it is a conversation and stays. Idempotent: the row
  # carries a request_id of its own comment, so a second tap, or a second device, records one row. It changes no grade, no attempt
  # and nothing of the practice ledger.
  #
  #   Comments::StudentWithdraw.call(student: s, comment_id: 3)
  #   # => Result(status:, event:, error:)   status: :recorded (also when already withdrawn), :invalid (error "teacher_replied") or :missing
  class StudentWithdraw
    Result = Struct.new(:status, :event, :error, keyword_init: true)

    def self.call(**args) = new(**args).call

    def initialize(student:, comment_id:)
      @student = student
      @comment_id = comment_id
    end

    def call
      return Result.new(status: :invalid, error: "not a student") unless @student.kind == "student"

      CommentEvent.transaction do
        comment = Comment.includes(:events).find_by(id: Integer(@comment_id.to_s, exception: false), student_id: @student.id)
        next Result.new(status: :missing, error: "comment") unless comment
        next Result.new(status: :recorded, event: comment.events.find { |e| e.kind == "student_withdrawn" }) if comment.withdrawn?
        next Result.new(status: :invalid, error: "teacher_replied") if comment.replies.any?

        event = CommentEvent.create!(comment: comment, kind: "student_withdrawn", origin: "student", actor: @student.key, text_it: nil,
                                     request_id: "student-withdraw:#{comment.id}", remote_addr: "", payload_json: "{}", created_at: Time.current)
        Result.new(status: :recorded, event: event)
      end
    end
  end
end
