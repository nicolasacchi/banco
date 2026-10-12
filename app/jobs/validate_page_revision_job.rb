# The validation of a stored page revision in the server's Chrome (D-281, SPEC B7): every seed, the scripted session, the
# screenshots stored by content. Runs on the `chrome` queue (one thread, one Chrome at a time, inside ChromeRunner's lock) at a priority
# below item validation. A verdict (passed, failed) is appended to page_validations; Chrome that cannot be reached is not a verdict: each
# attempt appends an `error` row and the job retries. The kit is the newest released one unless the job is given another
# (bin/revalidate-pages --kit 1.1).
class ValidatePageRevisionJob < ApplicationJob
  queue_as :chrome
  queue_with_priority 10

  RETRYABLE = [ Validation::ChromeRunner::Busy, Validation::ChromeRunner::Unavailable, Validation::ChromeRunner::Timeout ].freeze
  ATTEMPTS = 3

  retry_on(*RETRYABLE, wait: ->(executions) { (executions * 30).seconds }, attempts: ATTEMPTS) do |job, error|
    revision = PageRevision.find_by(id: job.arguments.first)
    Validation::PageValidationCheck.new(revision, kit: job.arguments[1] || Pages::Kit.versions.last, attempt: ATTEMPTS).record_error(error) if revision
  end

  def perform(revision_id, kit = nil)
    revision = PageRevision.find_by(id: revision_id)
    return unless revision

    kit ||= Pages::Kit.versions.last
    return unless Pages::Kit.released?(kit)
    return if settled?(revision, kit)

    check = Validation::PageValidationCheck.new(revision, kit: kit, attempt: executions)
    begin
      check.call
    rescue *RETRYABLE => e
      check.record_error(e) if executions < ATTEMPTS
      raise
    end
  end

  private

  # A verdict made by this version of the host and of the numbers, with this kit, is final.
  def settled?(revision, kit)
    PageValidation.where(page_revision_id: revision.id, kit_version: kit, status: %w[passed failed], harness_version: Validation::Harness.page_version).exists?
  end
end
