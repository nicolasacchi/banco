module Search
  # Builds the index from the primary database. Nothing here decides who may see what: that is Search::Scope, at query time.
  #
  #   Search::Indexer.rebuild!              # every group (bin/rails banco:search:rebuild, the nightly job)
  #   Search::Indexer.reindex(%w[items])    # the groups a change touched (SearchIndexJob)
  module Indexer
    # What a change to a table touches: the groups to rebuild (SearchIndexJob.later).
    TOUCHES = {
      "item_revisions" => %w[items skills findings answers], "item_validations" => %w[items], "review_findings" => %w[findings],
      "lesson_revisions" => %w[lessons topics], "topic_revisions" => %w[lessons topics items], "course_revisions" => %w[topics],
      "skill_graph_revisions" => %w[skills], "blueprint_revisions" => %w[items], "decisions" => %w[lessons topics items skills],
      "reference_texts" => %w[references], "attempts" => %w[answers], "practice_attempts" => %w[answers],
      "app_events" => %w[answers]
    }.freeze

    module_function

    def rebuild!(groups = Builders::GROUPS)
      reindex(groups)
    end

    # The vectors of the content documents that have no current one (D-300). Separate from the rebuild so that an embedding service
    # that is down never stops the lexical index: it is built first and the vectors are left for the next run. Returns Vectors.build!'s
    # counts; does nothing, and says so, where no embedder is configured.
    def embed!(deadline: nil) = Vectors.build!(Embedder.current, deadline: deadline)

    def reindex(groups)
      Schema.ensure!
      Array(groups).map(&:to_s).uniq.to_h { |group| [ group, Index.replace_group(group, Builders.docs(group)) ] }
    end
  end
end
