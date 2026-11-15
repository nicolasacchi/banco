# The shots of a stored item revision, drawn on demand (D-336): the instances as the student's phone shows them, in the server's Chrome. Runs on the
# `chrome` queue (one thread, one Chrome at a time, inside ChromeRunner's lock) at a priority (20) below item validation and the lesson render (10) and
# the page validations: a verdict gates topics, a shot is for the reviewer. A verdict (passed, failed) is appended to item_renders; Chrome that cannot be reached is not a verdict: the last failed attempt appends an
# `error` row and the earlier ones only retry (the request's `queued` row stands for the pending job). The job names its request (the `queued` row's id): it
# draws unless a verdict has been appended since, so a request that was forced draws again a revision that has a verdict, and two jobs for one revision draw once.
class RenderItemRevisionJob < ApplicationJob
  queue_as :chrome
  queue_with_priority 20

  RETRYABLE = [ Validation::ChromeRunner::Busy, Validation::ChromeRunner::Unavailable, Validation::ChromeRunner::Timeout ].freeze
  ATTEMPTS = 3

  retry_on(*RETRYABLE, wait: ->(executions) { (executions * 30).seconds }, attempts: ATTEMPTS) do |job, error|
    revision = ItemRevision.find_by(id: job.arguments.first)
    Validation::ItemRenderCheck.new(revision, attempt: ATTEMPTS).record_error(error) if revision
  end

  def perform(revision_id, request_id)
    revision = ItemRevision.find_by(id: revision_id)
    return unless revision
    return if answered?(revision, request_id)

    check = Validation::ItemRenderCheck.new(revision, attempt: executions)
    begin
      check.call
    rescue *RETRYABLE
      raise # retried; the last attempt's row is written by retry_on
    rescue StandardError => e
      check.record_error(e) # a crash is a row, not a `queued` row that stands for half an hour
      raise
    end
  end

  private

  # A verdict appended after the request is its answer: another job of the same revision has already drawn.
  def answered?(revision, request_id)
    ItemRender.where(item_revision_id: revision.id, status: ItemRender::VERDICTS).where("id > ?", request_id).exists?
  end
end
