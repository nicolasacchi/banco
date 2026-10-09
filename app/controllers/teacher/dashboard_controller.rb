module Teacher
  # The dashboard's two small endpoints (D-240), for the teacher and the guest: the digest of the ledger watermarks
  # (what the open page polls) and the body of the dashboard (what it fetches when the digest changed).
  class DashboardController < Teacher::BaseController
    before_action { response.headers["Cache-Control"] = "no-store" }

    def state
      render json: { digest: params[:fresh] == "1" ? DashboardDigest.current : DashboardDigest.cached, at: Time.current.utc.iso8601 }
    end

    def fragment
      @dashboard = Dashboard.new(student: viewed_student)
      render partial: "teacher/dashboard/body", locals: { dashboard: @dashboard }
    end
  end
end
