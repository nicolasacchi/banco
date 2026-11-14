module Api
  module V1
    # What the student sees of their progress (D-328): per subject the programme topics and the extra ones with their
    # status, the entry test state and the skill states. Course::StudentProgress reads Course::StudentView and
    # Diagnosis::Availability, the same as the student's pages; read-only for every token role.
    class ProgressController < Api::BaseController
      # GET /api/v1/students/:key/progress
      def show
        student = Student.find_by(key: params[:key].to_s, kind: "student")
        return refuse("E-NOT-FOUND", "student", "no student #{params[:key].to_s.first(40).inspect}", "banco progress", 404) unless student

        render json: Course::StudentProgress.new(student)
      end
    end
  end
end
