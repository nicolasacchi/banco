# Grades an attempt the expression worker could not grade (timeout or crash).
# Scheduled 30 s after the failure (Grading::Recorder.schedule_retry); if that run
# fails too it waits 2 minutes, then 10 minutes, then gives up: the attempt
# becomes verdict_pending for the teacher. Each success appends a row with source
# retry; nothing is ever updated.
class GradePendingJob < ApplicationJob
  queue_as :default

  retry_on Grading::Expression::Unavailable, attempts: 3,
           wait: ->(executions) { Grading::Recorder::RETRY_WAITS.fetch(executions, Grading::Recorder::RETRY_WAITS.last) } do |job, _error|
    attempt = Attempt.find_by(id: job.arguments.first)
    Grading::Recorder.give_up(attempt) if attempt && Grading::Recorder.pending?(attempt)
  end

  def perform(attempt_id)
    attempt = Attempt.find_by(id: attempt_id)
    return if attempt.nil? || !Grading::Recorder.pending?(attempt)

    Grading::Recorder.grade_attempt(attempt, source: "retry")
  end
end
