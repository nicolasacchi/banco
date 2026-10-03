# The browser posts {served_event_id, client_attempt_id, raw, source} and is told
# only {status: recorded|invalid, message_it?}: never a verdict (X-01).
class AnswersController < ApplicationController
  include ActingStudent

  before_action :require_open_diagnosis!
  before_action { response.headers["Cache-Control"] = "no-store" }

  def create
    outcome = Diagnosis::AnswerRecorder.new(student: acting_student, context: context_name).call(
      served_event_id: params[:served_event_id], client_attempt_id: params[:client_attempt_id],
      raw: params[:raw], source: params[:source]
    )
    render json: { status: outcome.status, message_it: outcome.message_it }.compact
  end

  private

  def require_open_diagnosis!
    head(:forbidden) unless preview? || Diagnosis::Release.open?
  end
end
