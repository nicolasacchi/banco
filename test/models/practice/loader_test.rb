require "test_helper"
require_relative "../../support/practice_world"
require_relative "../../support/finished_run"

# The loader reads rows into the engine's input; the seeder maps the diagnosis (A8.5, A8.6).
class PracticeLoaderTest < ActiveSupport::TestCase
  include PracticeWorld

  setup do
    build_practice_world
    @instance = @revisions.first.instances.order(:id).first
    @serve_at = Time.utc(2026, 10, 24, 22, 0)
  end

  def serve_with(student: @student, at: @serve_at, instance: @instance, skill: @skill, reason: "next")
    make_serve(student, @topic, instance, skill_key: skill, at: at, reason: reason)
  end

  def load_input(student: @student, now: @serve_at + 3600) = Practice::Loader.for(student, subject: @subject, now: now)

  test "a try carries the Rome calendar day, the fingerprint, the item and the low-guess flag" do
    serve = serve_with
    make_try(serve, at: Time.utc(2026, 10, 24, 22, 30)) # 00:30 on the 25th in Rome (CEST)
    serve2 = serve_with(instance: @revisions.first.instances.order(:id).second)
    make_try(serve2, at: Time.utc(2026, 10, 25, 23, 30)) # 00:30 on the 26th (CET)
    tries = load_input(now: Time.utc(2026, 10, 26)).tries
    assert_equal [ Date.new(2026, 10, 25), Date.new(2026, 10, 26) ], tries.map(&:day)
    t = tries.first
    assert_equal [ @skill, serve.id, @instance.fingerprint, @instance.item_revision.item_id, @instance.item_revision_id, true, 1, :correct, :C ],
                 [ t.skill, t.serve_id, t.fingerprint, t.item_id, t.item_revision_id, t.low_guess, t.try_number, t.outcome, t.evidence ]
  end

  test "the evidence of a try follows the verdict through Grading::Evidence" do
    cases = { "correct" => [ :correct, :C ], "typical_error" => [ :typical_error, :W ], "wrong" => [ :unrecognised, :W ],
              "undetermined" => [ :undetermined, :N ], "near_miss" => [ :near_miss, :N ] }
    cases.each_key.with_index do |verdict, n|
      serve = serve_with(instance: @revisions.first.instances.order(:id).offset(n).first, at: @serve_at + n * 60)
      make_try(serve, verdict: verdict, error_codes: verdict == "typical_error" ? [ "slip" ] : [], at: @serve_at + n * 60 + 10)
    end
    got = load_input.tries.sort_by(&:serve_id).map { |t| [ t.outcome, t.evidence ] }
    assert_equal cases.values, got
  end

  test "Non lo so is not a try but the serve stays" do
    serve = serve_with
    make_try(serve, verdict: "dont_know")
    input = load_input
    assert_empty input.tries
    assert_equal [ serve.id ], input.serves.map(&:id)
  end

  test "an aided attempt is a correct_aided try, a re-seen serve makes every try aided" do
    serve = serve_with
    make_try(serve, aided: true)
    reseen = serve_with(reason: "reseen", instance: @revisions.first.instances.order(:id).second)
    make_try(reseen)
    a, b = load_input.tries.sort_by(&:serve_id)
    assert_equal [ :correct_aided, true, false ], [ a.outcome, a.aided, a.reseen ]
    assert_equal [ :correct, true, true ], [ b.outcome, b.aided, b.reseen ]
  end

  test "seconds run from the serve, then from the previous try, capped at 600" do
    serve = serve_with
    make_try(serve, verdict: "wrong", at: @serve_at + 45)
    make_try(serve, try_number: 2, at: @serve_at + 45 + 5000)
    assert_equal [ 45, 600 ], load_input.tries.map(&:seconds)
  end

  # ---- practice/3: near (Grading::NearText) and contested (PracticeContest) ----

  KEY = "she goes to school".freeze

  # One instance of a normalized_text item whose key is KEY; accept: the instance's own accepted forms.
  def text_instance(accept: [])
    revision = make_practice_item("text-#{Item.count}", @skill, instances: 0, component: "normalized_text")
    ItemInstance.create!(item_revision: revision, seed: 1, display_json: JSON.generate(stem_it: "Mary ___ to school."), answer_json: JSON.generate(KEY),
                         accept_json: accept.empty? ? nil : JSON.generate(accept), errors_json: JSON.generate([]), hints_json: JSON.generate([ "Un aiuto." ]),
                         solution_json: JSON.generate(steps: [], final: KEY), fingerprint: Digest::SHA256.hexdigest("text-#{revision.id}"))
  end

  # A text try with the grading's normalized (what the grader graded: the part of a whole sentence, else the normalized answer).
  def text_try(serve, raw:, normalized: nil, verdict: "wrong", try_number: 1, at: @serve_at + 30 * try_number)
    attempt = PracticeAttempt.create!(student: serve.student, practice_serve: serve, try_number: try_number, client_attempt_id: "pt-#{SecureRandom.hex(6)}", raw: raw,
                                      source: "text", hints_before: 0, aided: false, answered_at: at, created_at: at)
    PracticeGrading.create!(practice_attempt: attempt, seq: 1, verdict: verdict, error_codes_json: "[]", normalized: normalized, method: "exact",
                            grader: "closed", grader_version: "test", source: "sync", created_at: at)
    attempt
  end

  def loaded_try(serve) = load_input.tries.find { |t| t.serve_id == serve.id }

  def contest!(attempt, at: @serve_at + 90)
    PracticeContest.create!(student: attempt.student, practice_serve: attempt.practice_serve, practice_attempt: attempt, created_at: at)
  end

  test "near is derived for a stored typo: a wrong text answer one letter off the key is a near miss (N)" do
    serve = serve_with(instance: text_instance)
    text_try(serve, raw: "She goes to schol")
    t = loaded_try(serve)
    assert_equal [ :near_miss, :N, false ], [ t.outcome, t.evidence, t.contested ]
    assert_equal :open, load_input.serves.first.status.state
    assert_equal %i[retry], load_input.serves.first.status.actions # a near miss: one retry, no contest
  end

  test "near is derived for one missing or one added word, never for a substitution" do
    { "she goes school" => :near_miss, "she goes to the school" => :near_miss, "she go to school" => :unrecognised, "he goes to school" => :unrecognised,
      "she goes to the big school" => :unrecognised, "completely different" => :unrecognised }.each do |raw, outcome|
      serve = serve_with(instance: text_instance)
      text_try(serve, raw: raw)
      assert_equal outcome, loaded_try(serve).outcome, raw
    end
  end

  test "near reads the grading's normalized when it is stored, else the raw" do
    serve = serve_with(instance: text_instance)
    text_try(serve, raw: "Mary: she goes to schol, I think", normalized: "she goes to schol") # a whole sentence: the part was graded
    assert_equal :near_miss, loaded_try(serve).outcome
    other = serve_with(instance: text_instance)
    text_try(other, raw: "she goes to schol", normalized: "she goes to the zoo")
    assert_equal :unrecognised, loaded_try(other).outcome
  end

  test "near compares with the key and with the accepted forms of the instance and of the item" do
    serve = serve_with(instance: text_instance(accept: [ "he goes to school" ]))
    text_try(serve, raw: "he goes to schol")
    assert_equal :near_miss, loaded_try(serve).outcome
  end

  test "near is only for a plain wrong on a normalized_text item: a number, a declared error or a correct answer keep their outcome" do
    number = serve_with
    make_try(number, verdict: "wrong", raw: "3")
    assert_equal :unrecognised, loaded_try(number).outcome
    typical = serve_with(instance: text_instance)
    text_try(typical, raw: "she goes to schol", verdict: "typical_error")
    assert_equal :typical_error, loaded_try(typical).outcome
    right = serve_with(instance: text_instance)
    text_try(right, raw: KEY, verdict: "correct")
    assert_equal :correct, loaded_try(right).outcome
  end

  test "the same stored rows give the same near, whatever the loader (a student's, or one serve's status)" do
    serve = serve_with(instance: text_instance)
    text_try(serve, raw: "she goes to schol")
    assert_equal load_input.serves.first.status, Practice::Loader.status_of(serve.reload, now: @serve_at + 3600)
  end

  test "a try with a contest row is contested (N); the serve closes contested and offers next and back" do
    serve = serve_with(instance: text_instance)
    attempt = text_try(serve, raw: "she goes at school")
    before = load_input.serves.first.status
    assert_equal [ :open, %i[retry show_solution contest] ], [ before.state, before.actions ]
    contest!(attempt)
    t = loaded_try(serve)
    assert_equal [ :contested, :N, true ], [ t.outcome, t.evidence, t.contested ]
    st = load_input.serves.first.status
    assert_equal [ :closed, :contested, %i[next back], 0 ], [ st.state, st.closed_by, st.actions, st.w ]
  end

  test "a contest on the second try of a serve closed wrong: the first stays wrong, the second is N" do
    serve = serve_with(instance: text_instance)
    text_try(serve, raw: "she goes at school")
    second = text_try(serve, raw: "she goes in school", try_number: 2)
    before = load_input.serves.first.status
    assert_equal [ :closed, :wrong, %i[show_solution back contest] ], [ before.state, before.closed_by, before.actions ]
    contest!(second)
    tries = load_input.tries.sort_by(&:try_number)
    assert_equal [ [ :unrecognised, :W, false ], [ :contested, :N, true ] ], tries.map { |t| [ t.outcome, t.evidence, t.contested ] }
    st = load_input.serves.first.status
    assert_equal [ :closed, :contested, %i[next back], 1 ], [ st.state, st.closed_by, st.actions, st.w ]
    assert_equal st, Practice::Loader.status_of(serve.reload, now: @serve_at + 3600)
  end

  test "a contest is read for the student's own serves only" do
    mine = serve_with(instance: text_instance)
    contest!(text_try(mine, raw: "she goes at school"))
    other = practice_student("other")
    theirs = serve_with(student: other, instance: text_instance)
    text_try(theirs, raw: "she goes at school")
    assert_equal :unrecognised, load_input(student: other).tries.first.outcome
    assert_equal :contested, load_input.tries.first.outcome
  end

  test "a contested try does not count as wrong in the fold of the loaded input" do
    serve = serve_with(instance: text_instance)
    contest!(text_try(serve, raw: "she goes at school"))
    input = load_input
    state = Practice::Fold.call(seeds: input.seeds, tries: input.tries, serves: input.serves).fetch(@skill)
    assert_equal [ 0, 1, "in_study" ], [ state.counts[:wrong], state.counts[:tries], state.state ]
  end

  test "serve rows: status, hints, solution requested, fingerprint, parent" do
    serve = serve_with
    make_practice_event(@student, "hint_shown", serve: serve, payload: { n: 1, auto: false }, at: @serve_at + 5)
    make_practice_event(@student, "solution_shown", serve: serve, payload: { reason: "requested" }, at: @serve_at + 9)
    row = load_input.serves.first
    assert_equal [ serve.id, @instance.fingerprint, 1, true, :closed, :solution, "next" ], [ row.id, row.fingerprint, row.hints_shown, row.solution_requested, row.status.state, row.status.closed_by, row.reason ]
  end

  test "an abandoned serve is reported by the status at the loader's now (14 days)" do
    serve_with
    assert_equal :open, load_input(now: @serve_at + 3600).serves.first.status.state
    assert_equal :open, load_input(now: @serve_at + Practice::Rules::V4::OPEN_SERVE_HOURS * 3600).serves.first.status.state
    assert_equal :abandoned, load_input(now: @serve_at + Practice::Rules::V4::OPEN_SERVE_HOURS * 3600 + 1).serves.first.status.state
  end

  test "a serve is superseded by a newer serve of the same student on the same item, any revision" do
    old = serve_with
    other_item = serve_with(instance: @revisions.second.instances.order(:id).first, at: @serve_at + 30)
    assert_equal %i[open open], load_input.serves.map { |r| r.status.state }
    # a second revision of the first item, served later
    item = @revisions.first.item
    revision2 = ItemRevision.create!(item: item, seq: 2, body_json: @revisions.first.body_json, file_sessions_json: "{}")
    inst2 = ItemInstance.create!(@instance.attributes.except("id").merge("item_revision_id" => revision2.id, "fingerprint" => "rev2-fp"))
    newer = serve_with(instance: inst2, at: @serve_at + 60)
    by_id = load_input.serves.to_h { |r| [ r.id, r.status.state ] }
    assert_equal({ old.id => :abandoned, other_item.id => :open, newer.id => :open }, by_id)
    assert_equal :abandoned, Practice::Loader.status_of(old, now: @serve_at + 3600).state
    assert_equal :open, Practice::Loader.status_of(newer, now: @serve_at + 3600).state
  end

  test "another student's newer serve on the same item supersedes nothing" do
    mine = serve_with
    serve_with(student: practice_student("trial-s"), at: @serve_at + 60, instance: @revisions.first.instances.order(:id).second)
    assert_equal :open, Practice::Loader.status_of(mine, now: @serve_at + 3600).state
  end

  test "a closed serve stays closed when a newer serve of the item exists" do
    old = serve_with
    make_try(old, at: @serve_at + 10)
    serve_with(at: @serve_at + 60, instance: @revisions.first.instances.order(:id).second)
    assert_equal :closed, Practice::Loader.status_of(old, now: @serve_at + 3600).state
  end

  test "only the student's serves of the subject are read" do
    serve_with
    other = practice_student("trial-l")
    serve_with(student: other)
    english = Subject.create!(key: "english", name_it: "Inglese", position: 2)
    serve_with(skill: "english.verbs")
    input = load_input
    assert_equal 1, input.serves.size
    assert_equal 1, Practice::Loader.for(@student, subject: english, now: @serve_at + 60).serves.size
    assert_equal 1, Practice::Loader.for(@student, subject: @subject, skill: @skill, seeds: false, now: @serve_at + 60).serves.size
  end

  test "void_revision_attempts drops the official student's tries on that revision; the serve stays" do
    serve = serve_with
    make_try(serve)
    Decision.create!(kind: "void_revision_attempts", subject: @subject, student: @student, payload_json: JSON.generate(item_revision_id: @revisions.first.id, reason_it: "Errore."),
                     request_id: "v1", teacher_login: "teacher", remote_addr: "127.0.0.1")
    input = load_input
    assert_empty input.tries
    assert_equal [ serve.id ], input.serves.map(&:id)
    assert_equal Set[@revisions.first.id], input.voided_item_revision_ids
  end

  test "a trial student's tries are not voided by the official student's decision" do
    trial = practice_student("trial-v")
    make_try(serve_with(student: trial))
    Decision.create!(kind: "void_revision_attempts", subject: @subject, student: @student, payload_json: JSON.generate(item_revision_id: @revisions.first.id, reason_it: "Errore."),
                     request_id: "v2", teacher_login: "teacher", remote_addr: "127.0.0.1")
    assert_equal 1, load_input(student: trial).tries.size
  end

  test "the voided tries leave the states: demonstration without them" do
    instances = @revisions.first.instances.order(:id).first(3)
    instances.each_with_index do |inst, n|
      serve = serve_with(instance: inst, at: Time.utc(2026, 10, 12 + n, 9))
      make_try(serve, at: Time.utc(2026, 10, 12 + n, 9, 1))
    end
    now = Time.utc(2026, 10, 15)
    input = load_input(now: now)
    fold = ->(i) { Practice::Fold.call(seeds: i.seeds, tries: i.tries, serves: i.serves, skills: [ @skill ]).fetch(@skill) }
    assert_equal "demonstrated", fold.(input).state
    Decision.create!(kind: "void_revision_attempts", subject: @subject, student: @student, payload_json: JSON.generate(item_revision_id: @revisions.first.id, reason_it: "Errore."),
                     request_id: "v3", teacher_login: "teacher", remote_addr: "127.0.0.1")
    voided = fold.(load_input(now: now))
    assert_equal "not_seen", voided.state
  end

  test "the fold over loader input is stable when read twice" do
    serve = serve_with
    make_try(serve, verdict: "wrong")
    a = load_input
    b = load_input
    assert_equal Practice::Fold.call(seeds: a.seeds, tries: a.tries, serves: a.serves), Practice::Fold.call(seeds: b.seeds, tries: b.tries, serves: b.serves)
  end
end

class PracticeSeederTest < ActiveSupport::TestCase
  include FinishedRun

  setup do
    @world = build_ui_subject(components: %w[number fraction choice])
    @subject = @world[:subject]
    @student = @world[:student]
    @run = play_run(@student, @subject)
  end

  def rows(*specs)
    skills = specs.map { |skill, state, extra| { skill: skill, subject: "math", state: state, kind: "recover", reason: nil }.merge(extra || {}) }
    { skills: skills }
  end

  def seeds_with(result, student: @student)
    Diagnosis::Derivation.stub(:result, result) { Practice::Seeder.call(student, @subject) }
  end

  test "the run is closed and seeds the skills of the subject (smoke)" do
    assert Diagnosis::Conductor.new(@run).closed?
    seeds = Practice::Seeder.call(@student, @subject)
    assert_not_empty seeds
    assert(seeds.keys.all? { |k| k.start_with?("math.") })
    assert(seeds.values.all? { |s| Practice::Rules::V4::STATES.include?(s.state) && s.run_id == @run.id })
  end

  test "A8.6: the five rows of the seed table" do
    result = rows([ "math.a", "demonstrated" ], [ "math.b", "to_recover" ], [ "math.c", "to_recover", { kind: "learn" } ],
                  [ "math.d", "not_assessed", { reason: "below_demonstrated" } ], [ "math.e", "not_assessed", { reason: "prerequisite_to_recover" } ],
                  [ "math.f", "pending" ], [ "italian.x", "demonstrated", { subject: "italian" } ])
    seeds = seeds_with(result)
    assert_equal %w[math.a math.b math.c math.d], seeds.keys.sort
    assert_equal({ "math.a" => "demonstrated", "math.b" => "to_recover", "math.c" => "to_learn", "math.d" => "demonstrated" }, seeds.transform_values(&:state))
    assert_equal [ false, false, false, true ], %w[math.a math.b math.c math.d].map { |k| seeds[k].implied }
  end

  test "the seed time is the run's last event, in the Rome zone" do
    seeds = seeds_with(rows([ "math.a", "demonstrated" ]))
    assert_equal @run.events.maximum(:at), seeds["math.a"].at
    assert_equal Practice::Rules::V4::ZONE, seeds["math.a"].at.time_zone.tzinfo.name
  end

  test "a voided run gives no seeds; an open newer run leaves the closed one in use" do
    Decision.create!(kind: "void_diagnosis_run", subject: @subject, student: @student, payload_json: JSON.generate(run_id: @run.id, reason_it: "x"),
                     request_id: "vr1", teacher_login: "teacher", remote_addr: "127.0.0.1")
    assert_empty seeds_with(rows([ "math.a", "demonstrated" ]))
    redo_run = Diagnosis::Conductor.fresh_run(@student, @subject)
    assert_equal 2, redo_run.sequence
    assert_empty seeds_with(rows([ "math.a", "demonstrated" ]))
  end

  test "an open run alone gives no seeds, and the earlier closed run is used while the redo is open" do
    redo_run = Diagnosis::Conductor.fresh_run(@student, @subject)
    seeds = seeds_with(rows([ "math.a", "demonstrated" ]))
    assert_equal [ @run.id ], seeds.values.map(&:run_id).uniq
    assert_not_equal redo_run.id, @run.id
  end

  test "another student has no seeds from this run (trial students use their own)" do
    trial = Student.create!(key: "trial-seed", kind: "student")
    assert_empty seeds_with(rows([ "math.a", "demonstrated" ]), student: trial)
  end

  test "the seed feeds the fold: the Fold gives the diagnosis reason" do
    seeds = seeds_with(rows([ "math.a", "to_recover" ]))
    state = Practice::Fold.call(seeds: seeds, tries: []).fetch("math.a")
    assert_equal [ "to_recover", :seed_to_recover ], [ state.state, state.why[:code] ]
  end
end

# S finished the test but never opened it again, so the run has no run_closed row: the engine's next move is
# to close it (D-298) and the list already says «Fatto». The course must start from that result (D-325).
class PracticeSeederFinishedRunTest < ActiveSupport::TestCase
  include FinishedRun

  setup do
    @world = build_ui_subject(components: %w[number fraction choice])
    @subject = @world[:subject]
    @student = @world[:student]
    @run = play_run(@student, @subject, close: false)
  end

  def seed_facts = Practice::Seeder.call(@student, @subject).transform_values { |s| [ s.state, s.implied, s.run_id ] }

  test "the run is finished and not closed: the frontier is empty and no run_closed row exists" do
    conductor = Diagnosis::Conductor.new(@run)
    assert_empty @run.events.where(kind: "run_closed")
    assert_not conductor.closed?
    assert conductor.finished?
    assert conductor.completed?
    assert Diagnosis::Availability.for(@student).find { |r| r.subject == @subject }.done
  end

  test "its result seeds the course, the same as after the close row is written" do
    before = seed_facts
    assert_not_empty before
    assert_equal [ @run.id ], before.values.map(&:last).uniq

    assert_equal :final, Diagnosis::Conductor.new(@run).step!.type
    assert_equal 1, @run.events.where(kind: "run_closed").count
    assert_equal before, seed_facts
  end

  test "a voided finished run seeds nothing" do
    Decision.create!(kind: "void_diagnosis_run", subject: @subject, student: @student, payload_json: JSON.generate(run_id: @run.id, reason_it: "x"),
                     request_id: "vr-open", teacher_login: "teacher", remote_addr: "127.0.0.1")
    assert_empty seed_facts
  end
end
