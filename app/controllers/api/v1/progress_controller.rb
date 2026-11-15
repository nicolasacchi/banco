module Api
  module V1
    # What the student sees of their progress (D-328): per subject the programme topics and the extra ones with their
    # status, the entry test state and the skill states. Course::StudentProgress reads Course::StudentView and
    # Diagnosis::Availability, the same as the student's pages; read-only, for the tokens that read (bot_read, teacher); a content agent's
    # token is 403 (the student's progress is not content). `next` (D-333) is what the same pages propose next, per subject.
    class ProgressController < Api::BaseController
      before_action { require_token_roles("bot_read", "teacher") }

      # GET /api/v1/students/:key/progress
      def show
        student = Student.find_by(key: params[:key].to_s, kind: "student")
        return refuse("E-NOT-FOUND", "student", "no student #{params[:key].to_s.first(40).inspect}", "banco progress", 404) unless student

        render json: Course::StudentProgress.new(student)
      end

      # GET /api/v1/students/:key/next[?subject=KEY]: the topic Oggi proposes first for each subject, the skills to recover, how far the
      # programme is (Course::StudentNext over Course::StudentView; nothing written).
      def upcoming
        student = Student.find_by(key: params[:key].to_s, kind: "student")
        return refuse("E-NOT-FOUND", "student", "no student #{params[:key].to_s.first(40).inspect}", "banco next", 404) unless student

        subject = params[:subject].presence&.to_s
        if subject && (!subject.match?(/\A[a-z_]+\z/) || !Subject.exists?(key: subject))
          return refuse("E-NOT-FOUND", "subject", "no subject #{subject.first(40).inspect}", "banco status", 404)
        end

        render json: Course::StudentNext.new(student, subject: subject)
      end
    end
  end
end
