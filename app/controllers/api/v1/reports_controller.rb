module Api
  module V1
    # GET /api/v1/diagnosis/report[?subject=KEY]: the per-subject report of the diagnosis
    # (B-09, banco.diagnosis_report/1). Read-only; the student's own words are left out
    # (see Diagnosis::Report): the agent that reads this may not be the grader's provider.
    class ReportsController < Api::BaseController
      def show
        key = params[:subject].to_s
        subject = nil
        unless key.empty?
          subject = Subject.find_by(key: key)
          return refuse("E-NOT-FOUND", "subject", "no subject #{key.first(40).inspect}", "banco diagnosis report --json", 404) unless subject
        end
        render json: Diagnosis::Report.call(subject: subject)
      end
    end
  end
end
