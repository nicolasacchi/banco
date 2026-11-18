# Makes the samples of «Prova le voci» with the server's voices (D-359): one short clip per voice (Speech::Samples). Run by the backfill; the same
# rules as SpeakLessonRevisionJob (never in a request, nothing without BANCO_TTS_URL, a failing clip does not stop the others).
class SpeakSamplesJob < ApplicationJob
  queue_as :speech

  retry_on Speech::Client::Unavailable, wait: ->(executions) { (executions * 5).minutes }, attempts: SpeakLessonRevisionJob::ATTEMPTS

  def perform
    client = Speech::Client.current
    unless client
      Rails.logger.info("speech: BANCO_TTS_URL is not set: no sample clips are made")
      return
    end

    Speech::Maker.all(Speech::Samples.entries, client, label: "the voice samples")
  end
end
