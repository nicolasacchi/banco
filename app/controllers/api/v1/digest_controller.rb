module Api
  module V1
    # The teacher's bot in one read (D-333): the dashboard, the student's progress and next topics, the open comments, the
    # answers that wait, and what the teachers and bots did last. Every part is what its own endpoint answers for the same
    # student, built by the same builders (Teacher::ApiView.home, Course::StudentProgress, Course::StudentNext,
    # Comments::ApiRows, Teacher::PendingAnswers.api_row, Activity.recent); no query of its own and nothing written.
    # For the tokens that read (bot_read, teacher); a content agent's token is 403.
    class DigestController < Api::BaseController
      LATEST = 5
      ACTIVITY = 15
      DUE = 20

      before_action { require_token_roles("bot_read", "teacher") }

      # GET /api/v1/digest[?student=KEY]
      def show
        key = params[:student].presence&.to_s || Student::OFFICIAL_KEY
        student = Student::KEY_FORMAT.match?(key) ? Student.find_by(key: key, kind: "student") : nil
        return refuse("E-NOT-FOUND", "student", "no student #{key.first(40).inspect}", "banco digest", 404) unless student

        view = Course::StudentView.new(student)
        render json: { generated_at: Time.current.utc.iso8601, home: Teacher::ApiView.home(Teacher::Dashboard.new(student: student)),
                       progress: Course::StudentProgress.new(student, view: view), next: Course::StudentNext.new(student, view: view),
                       comments: comments, answers_pending: answers_pending(student), activity: Activity.recent(limit: ACTIVITY) }
      end

      private

      # The open comments as GET /api/v1/comments lists them (state open, every student): how many, how many are new to the teacher
      # (state sent), the latest rows, and `due` (D-371): the threads that wait for the teacher with the hours left of the 24 h promise, soonest first, and which are a follow-up of the student after the teacher's last reply.
      def comments
        rows = Comments::ApiRows.list(state: "open")
        { notice: CommentsController::NOTICE, open: rows.size, unread: rows.count { |c| c.state == "sent" },
          latest: rows.first(LATEST).map { |c| Comments::ApiRows.summary(c) },
          due: Comments::Due.api(comments: rows, limit: DUE) }
      end

      # As GET /api/v1/answers/pending?student=KEY.
      def answers_pending(student)
        entries = Teacher::PendingAnswers.call(student: student)
        { notice: AnswersController::NOTICE, count: entries.size, rows: entries.first(LATEST).map { |e| Teacher::PendingAnswers.api_row(e) } }
      end
    end
  end
end
