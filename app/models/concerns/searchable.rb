# A row of this model changes what the content search finds: after it is created (and committed) the groups it touches are
# re-indexed by SearchIndexJob (Search::Indexer::TOUCHES). The index is derived, so this only keeps it fresh: it adds no column
# and no visibility rule, and it never fails the write.
module Searchable
  extend ActiveSupport::Concern

  included do
    after_create_commit :enqueue_search_index
  end

  private

  # Override where only some rows matter (a decision, an app event).
  def search_relevant? = true

  def enqueue_search_index
    return unless search_relevant?

    SearchIndexJob.later(Search::Indexer::TOUCHES.fetch(self.class.table_name))
  end
end
