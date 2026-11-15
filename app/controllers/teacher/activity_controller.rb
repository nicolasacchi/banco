module Teacher
  # Two things on this path. POST: the heartbeat of the teacher's pages (C-04): while a page is visible and used, the
  # browser posts the page's unit once a minute; at most one minute is recorded each minute (Teacher::Minutes). Not a
  # decision: it changes nothing but the measure of time.
  #
  # GET: «Chi ha fatto che cosa» (D-334), the feed of what the teachers and the bots did, read from the ledgers by
  # Activity (the same rows as GET /api/v1/activity). Read-only and for the teachers only: a guest and a view link get 403,
  # because the rows name the teachers' logins and the bots' labels (the bots read them over the API). It records nothing
  # and shows no word of the student.
  class ActivityController < Teacher::BaseController
    LIMIT = 100

    before_action :require_teacher!

    def show
      @rows = Activity.recent(limit: LIMIT)
    end

    def create
      return head(:forbidden) if request.cookies[DecisionRecorder::DEVICE_COOKIE].present?

      recorded = Teacher::Minutes.record(params[:unit].to_s)
      render json: { recorded: recorded }
    end
  end
end
