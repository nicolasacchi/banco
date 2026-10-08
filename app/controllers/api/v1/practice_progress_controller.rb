module Api
  module V1
    # What the practice trail says per skill (A4): the derived state of each skill of the subject's topics for
    # the official student, or a trial student with ?student=KEY. No student text (D-064): never raw answers.
    # The state is the practice/1 fold (Practice::Fold over Practice::Loader), the same as the student's pages.
    class PracticeProgressController < Api::BaseController
      include SubjectScoped

      before_action :load_subject

      # GET /api/v1/subjects/:subject/practice/progress?student=KEY
      def show
        key = params[:student].to_s
        student = key.empty? ? (Student.official || Student.new(key: Student::OFFICIAL_KEY, kind: "student")) : Student.real.find { |s| s.key == key }
        return refuse("E-NOT-FOUND", "student", key.empty? ? "there is no official student yet" : "no trial student #{key.first(40).inspect}", "banco practice progress --subject #{@subject.key}", 404) unless student

        render json: Course::ProgressView.call(@subject, student)
      end
    end
  end
end
