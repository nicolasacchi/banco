# Embeds the content documents that have no current vector (D-300, D-315), never in a request: the newest documents first, a bounded
# share a run (DOCUMENTS documents or SECONDS seconds, whichever comes first); when some are left it enqueues itself again, so a backlog
# is worked through in short runs and what an author has just submitted gets its vector within minutes.
#
# One embedder at a time (Search::Lease): a run that finds another at work (a run of this job, the rebuild task) returns at once; the
# one at work looks for new work after it has given the lease back, so nothing written meanwhile is left behind. Its queue `search`
# comes after `default` in the worker (config/queue.yml), so the grading never waits behind it. A service that is down is asked again
# DOWN_WAIT later, DOWN_TRIES times; after that the next change or the nightly rebuild tries again.
class SearchEmbedJob < ApplicationJob
  queue_as :search

  SECONDS = 120
  DOCUMENTS = 160
  DOWN_WAIT = 10.minutes
  DOWN_TRIES = 3

  # Never raises, does nothing without an embedder or where config.x.search.index_on_write is off (the test environment).
  def self.later(wait: nil, tries: DOWN_TRIES)
    return unless Rails.configuration.x.search.index_on_write && Search::Embedder.configured?

    (wait ? set(wait: wait) : self).perform_later(tries)
  rescue StandardError => e
    Rails.logger.warn("search: could not enqueue the embed job: #{e.class}")
  end

  def perform(tries = DOWN_TRIES)
    result = Search::Indexer.embed!(deadline: SECONDS, limit: DOCUMENTS)
    return if result[:busy] || result[:lost] || !result[:configured]

    if result[:down]
      self.class.later(wait: DOWN_WAIT, tries: tries - 1) if tries > 1
    elsif progressed?(result) && Search::Vectors.pending?(Search::Embedder.current)
      self.class.later
    end
  end

  private

  # Some documents were embedded, or none was waiting when the run began (what waits now came meanwhile). A run that took documents
  # and embedded none, with the service answering, does not go round again.
  def progressed?(result) = result[:embedded].positive? || (result[:embedded] + result[:pending]).zero?
end
