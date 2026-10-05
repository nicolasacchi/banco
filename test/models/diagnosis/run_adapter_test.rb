require "test_helper"

# The thin ActiveRecord side: rows in, the pure fold called, nothing written.
class DiagnosisRunAdapterTest < ActiveSupport::TestCase
  T0 = Time.utc(2026, 11, 2, 8, 0, 0)

  setup do
    @student = Student.create!(key: "student", kind: "student")
    @session = AgentSession.create!(label: "author", role: "author")
    @math = Subject.create!(key: "math", name_it: "Matematica", position: 1)
    @italian = Subject.create!(key: "italian", name_it: "Italiano", position: 2)
  end

  def graph_for(subject, skills)
    SkillGraphRevision.create!(subject: subject, seq: 1, author_session: @session,
                               body_json: { schema: "banco.skill_graph/1", subject: subject.key, skills: skills }.to_json)
  end

  def skill(key, prereqs: [], scope: "studied", errors: [])
    { key: key, label_it: key, layer: "core", scope: scope, prerequisites: prereqs, refs: [], errors: errors }
  end

  # An item with one revision (passed validation) and n instances.
  def make_item(subject, skill_key, name, instances: 4, extra: {})
    item = Item.create!(subject: subject, key: name, kind: "diagnosis_item")
    body = { schema: "banco.item/1", kind: "diagnosis_item", subject: subject.key, skill: skill_key, component: "number",
             expected_seconds: 60 }.merge(extra)
    rev = ItemRevision.create!(item: item, seq: 1, body_json: body.to_json, author_session: @session,
                               file_sessions_json: "{}", brief_sha256: "0" * 64)
    ItemValidation.create!(item_revision: rev, seq: 1, status: "passed")
    instances.times do |i|
      ItemInstance.create!(item_revision: rev, seed: i + 1, display_json: "{}", answer_json: "{}",
                           fingerprint: Digest::SHA256.hexdigest("#{name}-#{i}"))
    end
    rev
  end

  # descent: {skill => [revisions]} the descent pool the blueprint pins (D-034).
  def blueprint_for(subject, graph, entries, descent: {})
    body = { schema: "banco.blueprint/1", schema_version: 1, subject: subject.key, graph_revision_id: graph.id.to_s,
             entries: entries.map { |skill, revs| { skill: skill, items: revs.map { |r| r.id.to_s } } },
             descent: descent.map { |skill, revs| { skill: skill, items: revs.map { |r| r.id.to_s } } },
             budget: { sitting_minutes: 30, sittings: 2 }, depends_on_subjects: [], calculator: "no",
             intro_note_it: "x", not_measured_it: "y" }
    BlueprintRevision.create!(subject: subject, skill_graph_revision: graph, seq: 1, author_session: @session, body_json: body.to_json)
  end

  def make_run(subject, blueprint, sequence: 1, salt: "salt")
    DiagnosisRun.create!(student: @student, subject: subject, blueprint_revision: blueprint, sequence: sequence,
                         seed_salt: salt, rules_version: "diagnosis/1", engine_version: "engine/1")
  end

  # Helpers that write what the app would write.
  def log_event(run, kind, at, payload = nil)
    DiagnosisEvent.create!(diagnosis_run: run, seq: run.events.count + 1, kind: kind, at: at, payload_json: payload&.to_json)
  end

  def serve(run, at, instance, skill_key)
    event = log_event(run, "item_served", at)
    ItemServed.create!(diagnosis_event: event, item_instance: instance, skill_key: skill_key)
    event
  end

  def answer(event, at, verdict, codes: nil)
    attempt = Attempt.create!(student: @student, context: "diagnosis", served_event: event, client_attempt_id: SecureRandom.uuid,
                              item_instance: ItemServed.find_by!(diagnosis_event: event).item_instance, raw: "x", source: "web", answered_at: at)
    return attempt unless verdict

    AttemptGrading.create!(attempt: attempt, seq: 1, verdict: verdict, error_codes_json: codes&.to_json, grader: "closed",
                           grader_version: "t", source: "sync")
    attempt
  end

  def build_math
    graph = graph_for(@math, [ skill("math.a", prereqs: [ "math.b" ]), skill("math.b") ])
    @rev_a = make_item(@math, "math.a", "item-a")
    @rev_a2 = make_item(@math, "math.a", "item-a2")
    @rev_b = make_item(@math, "math.b", "item-b")
    @blueprint = blueprint_for(@math, graph, { "math.a" => [ @rev_a, @rev_a2 ] }, descent: { "math.b" => [ @rev_b ] })
    @run = make_run(@math, @blueprint)
  end

  test "an empty run asks for a first sitting, and the adapter writes nothing" do
    build_math
    adapter = Diagnosis::RunAdapter.new(@run)
    before = DiagnosisEvent.count + Attempt.count
    assert_equal :start_sitting, adapter.next_action(Diagnosis::FakeClock.new(T0)).type
    assert_equal before, DiagnosisEvent.count + Attempt.count
    assert_equal %w[not_started not_started], adapter.result[:skills].map { |s| s[:reason] }
  end

  test "rows become events and the fold derives the states: two wrong answers descend to the prerequisite" do
    build_math
    log_event(@run, "sitting_started", T0)
    insts = ItemInstance.where(item_revision: [ @rev_a, @rev_a2 ]).order(:id).to_a
    [ insts.first, insts.last ].each_with_index do |inst, i|
      s = serve(@run, T0 + i * 60, inst, "math.a")
      answer(s, T0 + i * 60 + 30, "wrong")
    end
    adapter = Diagnosis::RunAdapter.new(@run)
    assert_equal %w[to_recover two_wrong], adapter.result[:skills].find { |s| s[:skill] == "math.a" }.values_at(:state, :reason)
    action = adapter.next_action(Diagnosis::FakeClock.new(T0 + 200))
    assert_equal :serve, action.type
    assert_equal "math.b", action.skill # the prerequisite item is one the blueprint pins in its descent pool
    assert_equal 60, adapter.result[:counted_seconds]
  end

  test "an item that is not pinned is never served, even when it passed validation (D-034)" do
    graph = graph_for(@math, [ skill("math.a", prereqs: [ "math.b" ]), skill("math.b") ])
    rev = make_item(@math, "math.a", "item-a")
    rev2 = make_item(@math, "math.a", "item-a2")
    make_item(@math, "math.b", "item-b") # validated, same subject, but not pinned
    run = make_run(@math, blueprint_for(@math, graph, { "math.a" => [ rev, rev2 ] }))
    log_event(run, "sitting_started", T0)
    ItemInstance.where(item_revision: [ rev, rev2 ]).order(:id).each_with_index.select { |_, i| [ 0, 4 ].include?(i) }.each do |inst, i|
      s = serve(run, T0 + i * 20, inst, "math.a")
      answer(s, T0 + i * 20 + 10, "wrong")
    end
    adapter = Diagnosis::RunAdapter.new(run)
    assert_equal :close_run, adapter.next_action(Diagnosis::FakeClock.new(T0 + 500)).type
    assert_equal %w[not_assessed no_unseen_items], adapter.result[:skills].find { |s| s[:skill] == "math.b" }.values_at(:state, :reason)
  end

  test "a typical error code comes through the grading and routes the descent" do
    graph = graph_for(@math, [ skill("math.a", prereqs: [ "math.b", "math.c" ], errors: [ { code: "slip_b", description_it: "x", implicates: [ "math.b" ] } ]),
                               skill("math.b"), skill("math.c") ])
    rev = make_item(@math, "math.a", "item-a")
    rev2 = make_item(@math, "math.a", "item-a2")
    rev_b = make_item(@math, "math.b", "item-b")
    rev_c = make_item(@math, "math.c", "item-c")
    run = make_run(@math, blueprint_for(@math, graph, { "math.a" => [ rev, rev2 ] }, descent: { "math.b" => [ rev_b ], "math.c" => [ rev_c ] }))
    log_event(run, "sitting_started", T0)
    ItemInstance.where(item_revision: [ rev, rev2 ]).order(:id).each_with_index.select { |_, i| [ 0, 4 ].include?(i) }.each do |inst, i|
      s = serve(run, T0 + i * 20, inst, "math.a")
      answer(s, T0 + i * 20 + 10, "typical_error", codes: [ "slip_b" ])
    end
    assert_equal "math.b", Diagnosis::RunAdapter.new(run).next_action(Diagnosis::FakeClock.new(T0 + 500)).skill
  end

  test "an attempt without a grading is ungraded; a retry grading counts it" do
    build_math
    log_event(@run, "sitting_started", T0)
    inst = ItemInstance.where(item_revision: @rev_a).first
    s = serve(@run, T0, inst, "math.a")
    attempt = answer(s, T0 + 30, nil)
    assert_nil Diagnosis::RunAdapter.new(@run).result[:skills].find { |r| r[:skill] == "math.a" }[:state]
    events = Diagnosis::EventLoader.for_run(@run)
    assert_equal %w[sitting_started item_served answered], events.map { |e| e[:kind] }
    assert_equal "ungraded", events.last[:verdict]
    AttemptGrading.create!(attempt: attempt, seq: 1, verdict: "correct", grader: "closed", grader_version: "t", source: "retry")
    assert_equal "correct", Diagnosis::EventLoader.for_run(@run).last[:verdict]
  end

  test "teacher decisions enter the log: resolve_attempt, extend and close" do
    build_math
    log_event(@run, "sitting_started", T0)
    inst = ItemInstance.where(item_revision: @rev_a).first
    s = serve(@run, T0, inst, "math.a")
    attempt = answer(s, T0 + 30, "undetermined")
    decide = lambda do |kind, payload|
      Decision.create!(kind: kind, subject: @math, student: @student, payload_json: payload.to_json, request_id: SecureRandom.uuid,
                       teacher_login: "teacher", remote_addr: "127.0.0.1", created_at: T0 + 600)
    end
    decide.call("resolve_attempt", { attempt_id: attempt.id, verdict: "correct" })
    decide.call("extend_diagnosis_run", { run_id: @run.id })
    decide.call("close_diagnosis_run", { run_id: @run.id + 1000 }) # another run: not ours
    kinds = Diagnosis::EventLoader.for_run(@run).map { |e| e[:kind] }
    assert_equal %w[sitting_started item_served answered resolve_attempt extend_diagnosis_run], kinds
    state = Diagnosis::Engine.fold(Diagnosis::PlanLoader.for_run(@run), Diagnosis::EventLoader.for_run(@run))
    assert_equal 1, state.outcome("math.a").outcomes.size
    assert_equal 1, state.extends
  end

  test "a void_diagnosis_run decision makes every skill not_assessed(voided)" do
    build_math
    log_event(@run, "sitting_started", T0)
    Decision.create!(kind: "void_diagnosis_run", subject: @math, student: @student, payload_json: { run_id: @run.id }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "teacher", remote_addr: "127.0.0.1")
    assert_equal [ %w[not_assessed voided] ], Diagnosis::RunAdapter.new(@run).result[:skills].map { |s| s.values_at(:state, :reason) }.uniq
  end

  test "void_revision_attempts drops the answers on that revision" do
    build_math
    log_event(@run, "sitting_started", T0)
    inst = ItemInstance.where(item_revision: @rev_a).first
    s = serve(@run, T0, inst, "math.a")
    answer(s, T0 + 30, "correct")
    Decision.create!(kind: "void_revision_attempts", subject: @math, student: @student, payload_json: { item_revision_id: @rev_a.id }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "teacher", remote_addr: "127.0.0.1")
    kinds = Diagnosis::EventLoader.for_run(@run).map { |e| e[:kind] }
    assert_equal %w[sitting_started item_served], kinds
  end

  test "redo: instances seen in an earlier run are not served again" do
    build_math
    log_event(@run, "sitting_started", T0)
    insts = ItemInstance.where(item_revision: [ @rev_a, @rev_a2 ]).order(:id).to_a
    s = serve(@run, T0, insts.first, "math.a")
    answer(s, T0 + 30, "correct")
    log_event(@run, "run_closed", T0 + 60, { reason: "time_budget" })
    second = make_run(@math, @blueprint, sequence: 2, salt: "other")
    log_event(second, "sitting_started", T0 + 86_400)
    plan = Diagnosis::PlanLoader.for_run(second)
    assert_includes plan.seen, insts.first.fingerprint
    served = Diagnosis::RunAdapter.new(second).next_action(Diagnosis::FakeClock.new(T0 + 86_500)).instance
    refute_equal insts.first.id, served.id
  end

  test "cross subject: a skill resolved in another subject's run is reused, the subject's own graph is merged" do
    ig = graph_for(@italian, [ skill("italian.x") ])
    irev = make_item(@italian, "italian.x", "item-x")
    irev2 = make_item(@italian, "italian.x", "item-x2")
    irun = make_run(@italian, blueprint_for(@italian, ig, { "italian.x" => [ irev, irev2 ] }))
    log_event(irun, "sitting_started", T0)
    ItemInstance.where(item_revision: [ irev, irev2 ]).order(:id).each_with_index.select { |_, i| [ 0, 4 ].include?(i) }.each do |inst, i|
      s = serve(irun, T0 + i * 60, inst, "italian.x")
      answer(s, T0 + i * 60 + 30, "correct")
    end
    mg = graph_for(@math, [ skill("math.a", prereqs: [ "italian.x" ]) ])
    mrev = make_item(@math, "math.a", "item-a")
    mrev2 = make_item(@math, "math.a", "item-a2")
    mrun = make_run(@math, blueprint_for(@math, mg, { "math.a" => [ mrev, mrev2 ] }))
    plan = Diagnosis::PlanLoader.for_run(mrun)
    assert_equal({ "state" => "demonstrated", "reason" => "two_of_two" }, plan.external["italian.x"])
    assert_equal "italian", plan.skill("italian.x").subject

    # Voided, it is no longer reused.
    Decision.create!(kind: "void_diagnosis_run", subject: @italian, student: @student, payload_json: { run_id: irun.id }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "teacher", remote_addr: "127.0.0.1")
    assert_empty Diagnosis::PlanLoader.for_run(mrun).external
  end

  test "simulate --subject: the plan of a blueprint revision runs without writes" do
    build_math
    plan = Diagnosis::PlanLoader.for_blueprint_revision(@blueprint)
    before = [ DiagnosisEvent.count, Attempt.count, DiagnosisRun.count ]
    out = Diagnosis::Simulator.run(plan, Diagnosis::ScriptedStudent.new("all-wrong"))
    assert_equal "frontier_empty", out[:result][:end_reason]
    assert_equal before, [ DiagnosisEvent.count, Attempt.count, DiagnosisRun.count ]
  end

  # ---- what the engine is fed must say what Grading::Evidence says --------------

  def graded_run(extra: {}, verdict:, codes: nil, method: nil)
    graph = graph_for(@math, [ skill("math.a") ])
    rev = make_item(@math, "math.a", "item-a", extra: extra)
    rev2 = make_item(@math, "math.a", "item-a2", extra: extra)
    run = make_run(@math, blueprint_for(@math, graph, { "math.a" => [ rev, rev2 ] }))
    log_event(run, "sitting_started", T0)
    s = serve(run, T0, ItemInstance.where(item_revision: rev).first, "math.a")
    attempt = answer(s, T0 + 30, nil)
    AttemptGrading.create!(attempt: attempt, seq: 1, verdict: verdict, error_codes_json: codes&.to_json, method: method, grader: "closed",
                           grader_version: "t", source: "sync")
    run
  end

  def evidence_of_first(run)
    Diagnosis::RunAdapter.new(run).result[:skills].find { |r| r[:skill] == "math.a" }[:evidence]
  end

  test "a float-method correct is pending for the engine, as it is for Grading::Evidence (D-029)" do
    assert_not_equal [ "C" ], evidence_of_first(graded_run(verdict: "correct", method: "float"))
  end

  test "a float-method wrong is pending for the engine too" do
    assert_not_equal [ "W" ], evidence_of_first(graded_run(verdict: "wrong", method: "float"))
  end

  test "an exact-method correct stays a credit" do
    assert_equal [ "C" ], evidence_of_first(graded_run(verdict: "correct", method: "exact"))
  end

  test "an accent slip on an item with no accent_policy is wrong, not credited (D-040)" do
    assert_equal [ "W" ], evidence_of_first(graded_run(verdict: "typical_error", codes: [ "it_accents" ]))
  end

  test "an accent slip is credited when the item declares accent_policy flag" do
    assert_equal [ "C" ], evidence_of_first(graded_run(extra: { accent_policy: "flag" }, verdict: "typical_error", codes: [ "it_accents" ]))
  end

  test "an accent slip with another error code beside it is not credited" do
    assert_equal [ "W" ], evidence_of_first(graded_run(extra: { accent_policy: "flag" }, verdict: "typical_error", codes: [ "it_accents", "own_slip" ]))
  end

  test "a testlet of choice sub items is not low-guess and counts as choice (D-096)" do
    subs = %w[a b c d e].map { |id| { id: id, skill: "math.a", component: "choice" } }
    item = Item.create!(subject: @math, key: "tl", kind: "testlet")
    body = { schema: "banco.item/1", kind: "testlet", subject: "math", sub_items: subs, expected_seconds: 300 }
    rev = ItemRevision.create!(item: item, seq: 1, body_json: body.to_json, author_session: @session, file_sessions_json: "{}", brief_sha256: "0" * 64)
    ItemValidation.create!(item_revision: rev, seq: 1, status: "passed")
    ItemInstance.create!(item_revision: rev, seed: 1, display_json: { sub_items: [] }.to_json, answer_json: "{}", fingerprint: "tl-1")

    info = Validation::ItemInfo.for(rev)
    assert info.instances.none? { |i| i[:low_guess] }
    inst = Diagnosis::PlanLoader.allocate.send(:revision_instances, rev).first
    assert_not inst.low_guess
    assert inst.choice
    assert inst.choice_for("math.a")
  end
end
