namespace :banco do
  namespace :search do
    # The index is derived and disposable: delete the file (storage/*_search.sqlite3 or $BANCO_DATA_DIR/production_search.sqlite3)
    # and run this to get the same rows again. RESET=1 empties it first (a new schema version does that by itself).
    desc "Rebuild the content search index from the primary database (GROUPS=items,lessons to rebuild only some)"
    task rebuild: :environment do
      Search::Schema.reset! if ENV["RESET"] == "1"
      groups = ENV["GROUPS"].to_s.split(",").map(&:strip).reject(&:empty?)
      groups = Search::Builders::GROUPS if groups.empty?
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      counts = Search::Indexer.rebuild!(groups)
      counts.each { |group, c| puts format("%-11s +%d ~%d -%d =%d", group, c[:added], c[:changed], c[:removed], c[:kept]) }
      puts format("%d documents in %.1fs", Search::Index.count, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    desc "Document counts of the content search index, by kind"
    task status: :environment do
      Search::Schema.ensure!
      rows = Search::Record.connection.select_rows("SELECT kind, COUNT(*) FROM search_documents GROUP BY kind ORDER BY kind")
      rows.each { |kind, n| puts format("%-18s %d", kind, n) }
      puts "total #{Search::Index.count}"
    end
  end
end
