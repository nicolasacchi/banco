namespace :banco do
  # The operator's console path to a correction of the model a session declared (D-316). Never reachable over HTTP,
  # the API or the CLI; a dry run unless CONFIRM=1. The ledger is append-only: a correction is a new row of
  # agent_session_corrections, and the true model of a session is the model of its latest correction.
  #
  #   bin/rails banco:correct_session SESSION=772,773 MODEL=claude-opus-5-5 REASON="the workflow ran on Opus" [CONFIRM=1]
  #
  # The dry run prints, per session, its role, the declared and the current true model and the new model, then what
  # changes: reviews and solves that stop counting, gates that close, minor outcomes that reopen.
  desc "Correct the model of agent sessions: SESSION=id[,id...] MODEL= REASON= [CONFIRM=1]"
  task correct_session: :environment do
    ids = ENV["SESSION"].to_s.split(",")
    result = AgentSessionCorrector.call(session_ids: ids, model: ENV["MODEL"], reason: ENV["REASON"], confirm: ENV["CONFIRM"] == "1")
    unless result.ok
      warn "refused: banco:correct_session"
      result.errors.each { |e| warn "  - #{e}" }
      exit 1
    end
    puts result.lines
    if result.recorded
      puts "recorded #{result.sessions.size} correction(s) via console"
    else
      puts "dry run, nothing written; add CONFIRM=1 to record"
    end
  end
end
