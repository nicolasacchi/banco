# The render check of a stored lesson/2 revision (A12.2, D-249): the cards drawn in the server's Chrome, the layout
# findings as errors, the screenshots stored by content. Runs on the `chrome` queue (one thread, one Chrome at a time,
# inside ChromeRunner's lock) at a priority below item validation: items gate topics, a render is for the reviewer.
# A verdict (passed, failed) is appended to lesson_renders; Chrome that cannot be reached is not a verdict: each
# attempt appends an `error` row and the job retries.
class RenderLessonRevisionJob < ApplicationJob
  queue_as :chrome
  queue_with_priority 10

  RETRYABLE = [ Validation::ChromeRunner::Busy, Validation::ChromeRunner::Unavailable, Validation::ChromeRunner::Timeout ].freeze
  ATTEMPTS = 3

  retry_on(*RETRYABLE, wait: ->(executions) { (executions * 30).seconds }, attempts: ATTEMPTS) do |job, error|
    revision = LessonRevision.find_by(id: job.arguments.first)
    Validation::LessonRenderCheck.new(revision, attempt: ATTEMPTS).record_error(error) if revision
  end

  def perform(revision_id)
    revision = LessonRevision.find_by(id: revision_id)
    return unless revision&.lesson2?
    return if settled?(revision)

    check = Validation::LessonRenderCheck.new(revision, attempt: executions)
    begin
      check.call
    rescue *RETRYABLE => e
      check.record_error(e) if executions < ATTEMPTS
      raise
    end
  end

  private

  # A verdict made by this version of the host and of the numbers is final.
  def settled?(revision)
    LessonRender.where(lesson_revision_id: revision.id, status: %w[passed failed], harness_version: Validation::Harness.lesson_version).exists?
  end
end
