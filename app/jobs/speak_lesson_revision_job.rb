# Makes the spoken clips of a lesson revision's «Ascolta» with the server's voices (D-359), after its render check has passed and collected the
# segments the lesson says. Never in a request, never for anything but the stored (teacher-approved) text: firm rule 1 is about no model in the
# student's path, and the student's browser only plays a file that exists. Without BANCO_TTS_URL it does nothing and says so in the log.
#
# One clip failing does not stop the others (Speech::Maker.all). A service that is down makes the job try again later (clips already made are
# skipped); a clip the service refuses is logged and left. Queue `speech`, behind the ordinary jobs (config/queue.yml).
class SpeakLessonRevisionJob < ApplicationJob
  queue_as :speech

  ATTEMPTS = 6

  retry_on Speech::Client::Unavailable, wait: ->(executions) { (executions * 5).minutes }, attempts: ATTEMPTS

  # Enqueues the job when there is a service to ask; says so in the log when there is not. Never raises.
  def self.later(revision_id)
    if Speech::Client.configured?
      perform_later(revision_id)
    else
      Rails.logger.info("speech: BANCO_TTS_URL is not set: no clips are made for lesson revision #{revision_id}")
    end
  rescue StandardError => e
    Rails.logger.warn("speech: could not enqueue the clips of lesson revision #{revision_id}: #{e.class}")
  end

  def perform(revision_id)
    client = Speech::Client.current
    unless client
      Rails.logger.info("speech: BANCO_TTS_URL is not set: no clips are made for lesson revision #{revision_id}")
      return
    end
    revision = LessonRevision.find_by(id: revision_id)
    return unless revision&.lesson2?

    entries = Speech::Plan.entries(revision)
    if entries.empty?
      Rails.logger.info("speech: lesson revision #{revision_id} has no segments to speak (no passed render with segments, or only Latin)")
      return
    end

    Speech::Maker.all(entries, client, label: "lesson revision #{revision_id}")
  end
end
