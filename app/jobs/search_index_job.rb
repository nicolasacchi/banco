# Keeps the content search index fresh (Search::Indexer): rebuilds the named groups, or all of them (the nightly task in
# config/recurring.yml), then leaves the vectors to SearchEmbedJob (D-315: the lexical index of a change is never held up by the
# embedding service). The index is derived and disposable, so a job that fails is simply run again by the next change.
class SearchIndexJob < ApplicationJob
  queue_as :default

  # Waits a little so that a burst of writes (a submit, a batch of answers) is one rebuild, not many: the jobs of the burst that
  # run after the first one began reading find their groups up to date and skip them (covered?).
  DELAY = 20.seconds

  # Called by the models that change what is searchable (Searchable). It never raises: a write must not fail because the
  # search could not be told. Does nothing where config.x.search.index_on_write is off (the test environment).
  def self.later(*groups)
    return unless Rails.configuration.x.search.index_on_write

    set(wait: DELAY).perform_later(groups.flatten.map(&:to_s))
  rescue StandardError => e
    Rails.logger.warn("search: could not enqueue the index job: #{e.class}")
  end

  def perform(groups = nil)
    groups = groups.blank? || groups == [ "all" ] ? Search::Builders::GROUPS : groups
    stale = (groups & Search::Builders::GROUPS).reject { |group| covered?(group) }
    Search::Indexer.reindex(stale) if stale.any?
    # The vectors come after the lexical index, in their own job: one embedder at a time, newest documents first, a share at a time.
    SearchEmbedJob.later if Search::Vectors.pending?(Search::Embedder.current)
  end

  private

  # True when the last build of +group+ began reading the primary database after this job was enqueued: the write that enqueued it
  # had been committed by then (Searchable enqueues after the commit), so that build holds it. A job run by hand (perform_now) has no
  # enqueue time and always rebuilds.
  def covered?(group)
    return false unless enqueued_at

    read = Search::Indexer.read_at(group)
    read.present? && read > enqueued_at
  end
end
