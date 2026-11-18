namespace :banco do
  namespace :speech do
    # D-359. The clips are made by jobs on the `speech` queue (never in a request); this finds what is missing for the lessons that matter now.
    desc "Make the server voices' clips for the lesson revisions the official student sees and the approved ones, and the voice samples (CONFIRM=1 to enqueue; a dry run lists)"
    task backfill: :environment do
      confirm = ENV["CONFIRM"] == "1"
      rows = Speech::Backfill.rows
      rows.each do |row|
        what = case row.action
        when :speak then "#{row.missing} of #{row.total} clips to make"
        when :complete then "all #{row.total} clips are there"
        when :render then "to be drawn again to collect what it says (the render check, then the clips)"
        else "its render check failed: left alone"
        end
        puts format("%-44s revision %-5d %s", row.revision.lesson.key, row.revision.id, what)
      end
      if confirm && !Speech::Client.configured?
        abort "banco:speech:backfill: BANCO_TTS_URL is not set: nothing would be generated, so nothing is enqueued"
      end

      s = Speech::Backfill.run(confirm: confirm, rows: rows)
      puts "#{s[:revisions]} lesson revisions: #{s[:speak]} with #{s[:missing_clips]} clips to make, #{s[:render]} to draw again, #{s[:complete]} complete, #{s[:render_failed]} with a failed render"
      puts "voice samples: #{s[:samples_missing]} clips to make"
      puts(confirm ? "enqueued on the speech and chrome queues" : "dry run: CONFIRM=1 enqueues the jobs (needs BANCO_TTS_URL)")
    end
  end
end
