module Api
  module V1
    # GET /api/v1/status: where each subject stands (drafting, validating, in_review,
    # awaiting_teacher, approved). The content agent stops at awaiting_teacher: there
    # is no command to go further (firm rule 2).
    class StatusController < Api::BaseController
      def show
        subjects = Subject.order(:position).map { |s| SubjectStage.for(s) }
        student = Student.find_by(key: "student")
        render json: { subjects: subjects, stages: SubjectStage::STAGES,
                       warmup_completed: student ? Diagnosis::Warmup.complete?(student) : false,
                       consent_recorded: Decision.exists?(kind: "record_consent"),
                       diagnosis: { released: Diagnosis::Release.open? },
                       teacher_minutes: Teacher::Minutes.summary,
                       contract: Contract.digest }
      end
    end
  end
end
