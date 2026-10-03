# The warm-up, "prova dei comandi" (B-11): before the release, once; it does not
# count and it never fails. After the release it is not offered again.
class WarmupController < ApplicationController
  include ActingStudent

  before_action :before_release_only
  before_action { response.headers["Cache-Control"] = "no-store" }

  def show; end

  def tasks
    render json: { tasks: Diagnosis::Warmup.public_tasks, done: Diagnosis::Warmup.done_ids(acting_student) }
  end

  def answer
    status = Diagnosis::Warmup.answer!(acting_student, params[:task_id], params[:raw].to_s)
    render json: { status: status }
  end

  def complete
    render json: { completed: Diagnosis::Warmup.complete!(acting_student) }
  end

  private

  def before_release_only
    redirect_to "/diagnosis" if Diagnosis::Release.open?
  end
end
