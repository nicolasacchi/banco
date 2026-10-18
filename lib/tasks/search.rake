namespace :banco do
  namespace :search do
    # The index is derived and disposable: delete the file (storage/*_search.sqlite3 or $BANCO_DATA_DIR/production_search.sqlite3)
    # and run this to get the same rows again. RESET=1 empties it first (a new schema version does that by itself).
    desc "Rebuild the content search index from the primary database, then embed what has no vector (GROUPS=items,lessons to rebuild only some)"
    task rebuild: :environment do
      Search::Schema.reset! if ENV["RESET"] == "1"
      groups = ENV["GROUPS"].to_s.split(",").map(&:strip).reject(&:empty?)
      groups = Search::Builders::GROUPS if groups.empty?
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      counts = Search::Indexer.rebuild!(groups)
      counts.each { |group, c| puts format("%-11s +%d ~%d -%d =%d (%d vectors kept for an unchanged text)", group, c[:added], c[:changed], c[:removed], c[:kept], c[:reused]) }
      puts format("%d documents in %.1fs", Search::Index.count, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      # The vectors come after the lexical index and never stop it: a service that is down leaves them for the next run.
      # A slow batch does not stop the rebuild: it waits (the service drains the abandoned work), retries, then skips (D-303).
      # One embedder at a time (D-315): the task waits for a SearchEmbedJob to finish its share; a job that finds the task at work leaves it the work.
      embedder = Search::Embedder.current
      embedder.document_timeout = Float(ENV["BANCO_EMBED_DOCUMENT_TIMEOUT"].presence || 180) if embedder.respond_to?(:document_timeout=)
      lease_wait = Integer(ENV["BANCO_EMBED_LEASE_WAIT"].presence || 600)
      progress = lambda do |embedded:, total:, skipped:, seconds:|
        rate = seconds.positive? ? embedded / (seconds / 60.0) : 0
        eta = rate.positive? ? ((total - embedded) / rate * 60).round : nil
        puts format("vectors: %d of %d, %d/min, eta %s%s", embedded, total, rate.round, eta ? format("%dh%02d", eta / 3600, eta % 3600 / 60) : "-",
                    skipped.positive? ? ", #{skipped} batches skipped" : "")
        $stdout.flush
      end
      v = Search::Indexer.embed!(wait: lease_wait, retries: Integer(ENV["BANCO_EMBED_RETRIES"].presence || 3), retry_wait: Float(ENV["BANCO_EMBED_RETRY_WAIT"].presence || 60),
                                 every: Integer(ENV["BANCO_EMBED_PROGRESS_EVERY"].presence || 10), progress: progress)
      if !v[:configured]
        puts "vectors: no embedder configured (BANCO_EMBED_URL unset): lexical search only"
      elsif v[:busy]
        holder = Search::Lease.holder
        puts "vectors: another embedder is at work#{" until #{holder[:expires_at].utc.iso8601}" if holder} (a SearchEmbedJob or another rebuild): " \
             "it goes on by itself; run again to wait for it"
      else
        puts format("vectors: %d embedded in %.1fs, %d left%s%s%s", v[:embedded], v[:seconds], v[:pending],
                    v[:skipped].to_i.positive? ? ", #{v[:skipped]} batches skipped (#{v[:skipped_documents]} documents: run again)" : "",
                    v[:down] ? " (the embedding service did not answer: run again)" : "",
                    v[:lost] ? " (the lease was lost to another embedder, which goes on)" : "")
        # What is left (a skipped batch, documents written meanwhile) goes to the job, in short runs.
        SearchEmbedJob.later if Search::Vectors.pending?(embedder)
      end
    end

    desc "Document counts of the content search index, by kind"
    task status: :environment do
      Search::Schema.ensure!
      rows = Search::Record.connection.select_rows("SELECT kind, COUNT(*) FROM search_documents GROUP BY kind ORDER BY kind")
      rows.each { |kind, n| puts format("%-18s %d", kind, n) }
      puts "total #{Search::Index.count}"
      v = Search::Vectors.status
      puts format("vectors: %d of %d documents have a current vector (%d missing); model %s; stored: %s, dimension %s", v[:current], v[:eligible], v[:missing],
                  v[:embedder] || "none configured", v[:models].join(", ").presence || "none", v[:dimension] || "-")
      holder = Search::Lease.holder
      puts "embedding: at work until #{holder[:expires_at].utc.iso8601} unless renewed (SearchEmbedJob or a rebuild)" if holder && holder[:expires_at] > Time.current
    end
  end
end
