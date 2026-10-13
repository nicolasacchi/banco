# The warm-up, "prova dei comandi" (B-11, D-261): optional and always recallable, before and after the release,
# for the official and the trial students; it does not count, it never fails and nothing waits for it.
class WarmupController < ApplicationController
  include ActingStudent

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
end
