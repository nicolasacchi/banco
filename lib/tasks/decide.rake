namespace :banco do
  # The operator's console path to a teacher decision (D-260). Never reachable over HTTP; a dry run unless CONFIRM=1.
  #
  #   bin/rails banco:decide KIND=approve_skill_graph SUBJECT=history TEACHER=<login> REASON="..." [REVISION=id] [CONFIRM=1]
  #   bin/rails banco:decide KIND=dispose_finding TEACHER=<login> REASON="..." PARAMS='{"finding_id":3,"disposition":"dismissed"}' CONFIRM=1
  #
  # TEACHER must be in BANCO_TEACHER_USERS and BANCO_DECISIONS_ENABLED=1. PARAMS is a JSON object with the
  # other parameters of the kind, as the teacher's form would send them.
  #
  # approve_topic only: ATTEST_IT="<the operator's own words>" waives the single requirement that the topic review page
  # was opened (every other requirement of the gate holds) and records the words in the decision.
  desc "Record a teacher decision from the console: KIND= TEACHER= [SUBJECT=] [REVISION=] [REASON=] [PARAMS=json] [ATTEST_IT=words] [CONFIRM=1]"
  task decide: :environment do
    kind = ENV["KIND"].presence or abort "KIND=#{DecisionRecorder::KINDS.join('|')} is required"
    teacher = ENV["TEACHER"].presence or abort "TEACHER=<login from BANCO_TEACHER_USERS> is required"
    extra = ENV["PARAMS"].present? ? (JSON.parse(ENV["PARAMS"]) rescue abort("PARAMS is not valid JSON")) : {}
    abort "PARAMS must be a JSON object" unless extra.is_a?(Hash)
    confirm = ENV["CONFIRM"] == "1"

    result = DecisionConsole.call(kind: kind, teacher: teacher, subject: ENV["SUBJECT"], revision: ENV["REVISION"], reason: ENV["REASON"],
                                  params: extra, attest_it: ENV["ATTEST_IT"], confirm: confirm)
    unless result.ok
      warn "refused: #{kind}"
      result.errors.each { |e| warn "  - #{e}" }
      exit 1
    end
    if result.recorded
      puts "recorded decision #{result.decision.id} (#{kind}) as #{teacher} via console"
    else
      puts "dry run, nothing written; the gate allows #{kind}; add CONFIRM=1 to record"
    end
    puts JSON.pretty_generate(result.payload)
  end
end
