# Keeps the content search index fresh (Search::Indexer): rebuilds the named groups, or all of them (the nightly task in
# config/recurring.yml). The index is derived and disposable, so a job that fails is simply run again by the next change.
class SearchIndexJob < ApplicationJob
  queue_as :default

  # Waits a little so that a burst of writes (a submit, a batch of answers) is one rebuild, not many.
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
    Search::Indexer.reindex(groups & Search::Builders::GROUPS)
  end
end
