# Validates one item revision (A-06): the Ruby phase, the Chrome phase on the
# banco-chrome sidecar, the grading round trip and verify. Runs on the `chrome`
# queue, which has one thread, and inside ChromeRunner's shared lock.
#
# A verdict (passed, failed) is appended to item_validations. Chrome that cannot be
# reached, a harness that does not answer and a grader worker that is down are not
# verdicts: each attempt appends an `error` row and the job retries; `error` is never
# a pass. When the last attempt still times out inside the page, the generator is
# what is slow and the revision fails with E-GEN-TIMEOUT.
class ValidateItemRevisionJob < ApplicationJob
  queue_as :chrome

  RETRYABLE = [ Validation::ChromeRunner::Busy, Validation::ChromeRunner::Unavailable, Validation::ChromeRunner::Timeout,
                Validation::Roundtrip::Unavailable ].freeze
  ATTEMPTS = 3

  retry_on(*RETRYABLE, wait: ->(executions) { (executions * 30).seconds }, attempts: ATTEMPTS) do |job, error|
    revision = ItemRevision.find_by(id: job.arguments.first)
    next unless revision

    validation = Validation::RevisionValidation.new(revision, attempt: ATTEMPTS)
    error.is_a?(Validation::ChromeRunner::Timeout) ? validation.record_timeout(error) : validation.record_error(error)
  end

  def perform(revision_id)
    revision = ItemRevision.find_by(id: revision_id)
    return unless revision
    return if revision.validations.where(status: %w[passed failed]).exists?

    validation = Validation::RevisionValidation.new(revision, attempt: executions)
    begin
      validation.call
    rescue *RETRYABLE => e
      validation.record_error(e) if executions < ATTEMPTS
      raise
    end
  end
end
