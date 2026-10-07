module Teacher
  # The heartbeat of the teacher's pages (C-04): while a page is visible and used, the
  # browser posts the page's unit once a minute; at most one minute is recorded each
  # minute (Teacher::Minutes). Not a decision: it changes nothing but the measure of time.
  class ActivityController < Teacher::BaseController
    before_action :require_teacher!

    def create
      return head(:forbidden) if request.cookies[DecisionRecorder::DEVICE_COOKIE].present?

      recorded = Teacher::Minutes.record(params[:unit].to_s)
      render json: { recorded: recorded }
    end
  end
end
