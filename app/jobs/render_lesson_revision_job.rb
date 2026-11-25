# The render check of a stored lesson/2 revision (A12.2, D-249): the cards drawn in the server's Chrome, the layout
# findings as errors, the screenshots stored by content. Runs on the `chrome` queue (two threads, two Chrome runs at a time,
# inside ChromeRunner's lock) at a priority below item validation: items gate topics, a render is for the reviewer.
# A verdict (passed, failed) is appended to lesson_renders; Chrome that cannot be reached is not a verdict: each
# attempt appends an `error` row and the job retries. A render that passed hands the revision to SpeakLessonRevisionJob (D-359).
class RenderLessonRevisionJob < ApplicationJob
  queue_as :chrome
  queue_with_priority 10

  RETRYABLE = [ Validation::ChromeRunner::Busy, Validation::ChromeRunner::Unavailable, Validation::ChromeRunner::Timeout ].freeze
  ATTEMPTS = 3
  # A render that failed on its time limits only is not a verdict about the lesson (the server was busy): it is queued again with a growing wait, until the
  # revision has TIMEOUT_DRAWS such failures in a row (the first job, then two more); after that the failure stands, and the author may ask for another draw
  # (`banco lesson render REV --retry`, Api::V1::LessonRendersController).
  TIMEOUT_DRAWS = 3
  TIMEOUT_WAIT = ->(draws) { (draws * 5).minutes }

  retry_on(*RETRYABLE, wait: ->(executions) { (executions * 30).seconds }, attempts: ATTEMPTS) do |job, error|
    revision = LessonRevision.find_by(id: job.arguments.first)
    Validation::LessonRenderCheck.new(revision, attempt: ATTEMPTS).record_error(error) if revision
  end

  # after_id: the latest render row when this draw was asked for (a retry): a verdict appended since is its answer, and the job does nothing.
  def perform(revision_id, after_id = nil)
    revision = LessonRevision.find_by(id: revision_id)
    return unless revision&.lesson2?
    return if settled?(revision)
    return if after_id && LessonRender.where(lesson_revision_id: revision.id, status: %w[passed failed]).where("id > ?", after_id).exists?

    check = Validation::LessonRenderCheck.new(revision, attempt: executions)
    begin
      row = check.call
      # a passed render has the segments the lesson says aloud: the clips of the server's voices are made from them (D-359)
      SpeakLessonRevisionJob.later(revision.id) if row.passed?
      draw_again(revision, row) if row.timeout_only?
    rescue *RETRYABLE => e
      check.record_error(e) if executions < ATTEMPTS
      raise
    end
  end

  private

  # A verdict made by this version of the host and of the numbers is final, unless it is a failure on the time limits only: that one is drawn again.
  def settled?(revision)
    latest = LessonRender.where(lesson_revision_id: revision.id, status: %w[passed failed], harness_version: Validation::Harness.lesson_version).order(:id).last
    latest && !latest.timeout_only?
  end

  def draw_again(revision, row)
    draws = LessonRender.timeout_streak(revision)
    return if draws >= TIMEOUT_DRAWS

    Rails.logger.warn("lesson render of revision #{revision.id} timed out (#{draws} in a row); queued again in #{TIMEOUT_WAIT.call(draws).inspect}")
    self.class.set(wait: TIMEOUT_WAIT.call(draws)).perform_later(revision.id, row.id)
  end
end
