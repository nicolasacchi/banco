# Validates one item revision (A-06): the Ruby phase, the Chrome phase on the
# banco-chrome sidecar, the grading round trip and verify. Runs on the `chrome`
# queue, which has two threads, and inside ChromeRunner's shared lock.
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
  # A validation that timed out inside the page on every attempt is not a verdict about the files (E-GEN-TIMEOUT with detail.server_limit): it is queued again
  # with a growing wait until the revision has TIMEOUT_DRAWS such failures in a row; then it stands, and the author may ask for another go (`banco work retry REV`).
  TIMEOUT_DRAWS = 3
  TIMEOUT_WAIT = ->(draws) { (draws * 5).minutes }

  retry_on(*RETRYABLE, wait: ->(executions) { (executions * 30).seconds }, attempts: ATTEMPTS) do |job, error|
    revision = ItemRevision.find_by(id: job.arguments.first)
    next unless revision

    validation = Validation::RevisionValidation.new(revision, attempt: ATTEMPTS)
    if error.is_a?(Validation::ChromeRunner::Timeout)
      validation.record_timeout(error)
      draws = ItemValidation.timeout_streak(revision)
      job.class.set(wait: TIMEOUT_WAIT.call(draws)).perform_later(revision.id, revision.validations.maximum(:seq).to_i) if draws < TIMEOUT_DRAWS
    else
      validation.record_error(error)
    end
  end

  # Whether the revision's job is waiting or running in Solid Queue (arguments start with the revision id). Without Solid Queue (test, development)
  # nothing is known, and the age alone says.
  def self.pending?(revision)
    return false unless ActiveJob::Base.queue_adapter_name == "solid_queue"

    SolidQueue::Job.where(class_name: name, finished_at: nil).where.missing(:failed_execution)
                   .where("arguments LIKE ? OR arguments LIKE ?", "%\"arguments\":[#{revision.id.to_i}]%", "%\"arguments\":[#{revision.id.to_i},%").exists?
  end

  # A revision with no verdict (the job was lost, a restart) for stale_minutes and no job in the queue: `banco work retry` may enqueue it again.
  def self.stuck?(revision, now: Time.current)
    return false if revision.validations.where(status: %w[passed failed]).exists?

    since = revision.latest_validation&.created_at || revision.created_at
    since < now - Validation::Rules.get(:generator, :stale_minutes).minutes && !pending?(revision)
  end

  # after_seq: the revision's latest validation row when this go was asked for (a retry): a verdict appended since is its answer, and the job does nothing.
  def perform(revision_id, after_seq = nil)
    revision = ItemRevision.find_by(id: revision_id)
    return unless revision
    return if settled_under_current_rules?(revision)
    return if after_seq && revision.validations.where(status: %w[passed failed]).where("seq > ?", after_seq).exists?

    validation = Validation::RevisionValidation.new(revision, attempt: executions)
    begin
      validation.call
    rescue *RETRYABLE => e
      validation.record_error(e) if executions < ATTEMPTS
      raise
    end
  end

  private

  # A passed or failed verdict is final, unless it was reached under older rules and the
  # revision passed then: an identical resubmission asks for a new verdict (D-154). A failure on the server's time limit alone is no verdict.
  def settled_under_current_rules?(revision)
    current = Validation::Rules.version.to_s
    revision.validations.where(status: %w[passed failed]).any? { |v| (v.status == "failed" && !v.timeout_only?) || (v.status == "passed" && (v.rules_version.blank? || v.rules_version.to_s == current)) }
  end
end
