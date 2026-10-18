module Search
  # Builds the index from the primary database. Nothing here decides who may see what: that is Search::Scope, at query time.
  #
  #   Search::Indexer.rebuild!              # every group (bin/rails banco:search:rebuild, the nightly job)
  #   Search::Indexer.reindex(%w[items])    # the groups a change touched (SearchIndexJob)
  #   Search::Indexer.embed!(deadline: 120, limit: 160)   # a share of the vectors, one embedder at a time (SearchEmbedJob, D-315)
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

    # The vectors of the content documents that have no current one (D-300), separate from the lexical index so that an embedding
    # service that is down never stops it. One embedder at a time (Search::Lease, D-315): when another holds the lease this returns
    # {busy: true} at once (or after +wait+ seconds), and the holder looks again for new work once it has given the lease back.
    # Returns Vectors.build!'s counts (configured: false where no embedder is configured). +options+ go to Vectors.build!.
    def embed!(deadline: nil, limit: nil, wait: 0, **options)
      embedder = Embedder.current
      return Vectors.build!(nil) unless embedder

      lease = Lease.take(ttl: Vectors.lease_ttl(embedder, retry_wait: options[:retry_wait].to_i), wait: wait)
      return { embedded: 0, pending: 0, down: false, seconds: 0.0, configured: true, skipped: 0, busy: true } unless lease

      begin
        Vectors.build!(embedder, deadline: deadline, limit: limit, lease: lease, **options)
      ensure
        lease.release
      end
    end

    # +groups+ are read and written one after the other; each records when its read began (`read_GROUP`), which lets SearchIndexJob skip
    # a group that a later read has already brought up to date.
    def reindex(groups)
      Schema.ensure!
      Array(groups).map(&:to_s).uniq.to_h do |group|
        read_at = Time.current
        [ group, Index.replace_group(group, Builders.docs(group), read_at: read_at) ]
      end
    end

    # When the last build of +group+ began reading the primary database (nil before the first).
    def read_at(group)
      value = Index.meta("read_#{group}")
      value && Time.iso8601(value)
    rescue ArgumentError
      nil
    end
  end
end
