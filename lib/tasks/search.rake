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
      counts.each { |group, c| puts format("%-11s +%d ~%d -%d =%d", group, c[:added], c[:changed], c[:removed], c[:kept]) }
      puts format("%d documents in %.1fs", Search::Index.count, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      # The vectors come after the lexical index and never stop it: a service that is down leaves them for the next run.
      v = Search::Indexer.embed!
      if !v[:configured]
        puts "vectors: no embedder configured (BANCO_EMBED_URL unset): lexical search only"
      else
        puts format("vectors: %d embedded in %.1fs, %d left%s", v[:embedded], v[:seconds], v[:pending], v[:down] ? " (the embedding service did not answer: run again)" : "")
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
    end
  end
end
