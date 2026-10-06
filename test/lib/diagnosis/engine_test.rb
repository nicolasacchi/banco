require "test_helper"
require_relative "../../support/diagnosis_helper"

# Named tests of B-10 (descent, sequencing, evidence, testlets, short answer,
# redo), on a fake clock and with no database.
class DiagnosisEngineTest < ActiveSupport::TestCase
  include DiagnosisHelper

  A = "math.a".freeze
  B = "math.b".freeze
  C = "math.c".freeze
  D = "math.d".freeze

  def chain_plan(**opts)
    build_plan(skills: {
                 A => { prereqs: [ B ], errors: { "slip_b" => [ B ], "own_slip" => [] } },
                 B => { prereqs: [ C ] },
                 C => { prereqs: [] }
               }, **opts)
  end

  def run_to(driver, *verdicts)
    verdicts.each { |v| driver.play(v) }
  end

  # ---- descent -------------------------------------------------------------

  test "unclassified_wrong_descends_to_all_direct_prerequisites" do
    plan = build_plan(skills: { A => { prereqs: [ B, C ] }, B => {}, C => {} })
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "wrong", "wrong")
    assert_equal %w[to_recover two_wrong], d.state(A)
    assert_equal B, d.next_skill
    run_to(d, "correct", "correct")
    assert_equal C, d.next_skill
  end

  test "typical_error_descends_only_to_implicated_skill" do
    plan = build_plan(skills: { A => { prereqs: [ B, C ], errors: { "slip_b" => [ B ] } }, B => {}, C => {} })
    # Both W carry the code slip_b: only B is a target, not the other prerequisite C.
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    2.times { d.play("typical_error", error_code: "slip_b") }
    assert_equal %w[to_recover two_wrong], d.state(A)
    assert_equal B, d.next_skill
    run_to(d, "correct", "correct")
    d.finish!
    assert_equal "frontier_empty", d.end_reason
    assert_equal %w[not_assessed not_needed], d.state(C)
  end

  test "own_skill_typical_error_does_not_descend" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    2.times { d.play("typical_error", error_code: "own_slip") }
    assert_equal %w[to_recover two_wrong], d.state(A)
    d.finish!
    assert_equal "frontier_empty", d.end_reason
    assert_equal 2, d.result[:served]
    assert_equal %w[not_assessed not_needed], d.state(B)
  end

  test "dont_know_first_item_resolves_and_descends" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    d.play("dont_know")
    assert_equal %w[to_recover dont_know], d.state(A)
    assert_equal B, d.next_skill # D is an unclassified outcome: all direct prerequisites
  end

  test "descent is depth first: the targets of a skill go to the head" do
    plan = build_plan(skills: { A => { prereqs: [ B ] }, B => { prereqs: [ C ] }, C => {}, D => {} }, entries: [ A, D ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "wrong", "wrong") # A to_recover, B queued before D
    assert_equal B, d.next_skill
    run_to(d, "wrong", "wrong")
    assert_equal C, d.next_skill # C before the second entry D
    run_to(d, "wrong", "wrong")
    assert_equal D, d.next_skill
  end

  test "descent only happens when a skill resolves to_recover" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    run_to(d, "correct", "wrong") # mixed: one more item of the same skill, no descent yet
    assert_equal A, d.next_skill
  end

  test "never_serves_below_demonstrated" do
    plan = build_plan(skills: { A => { prereqs: [ B ] }, B => { prereqs: [ C ] }, C => {} }, entries: [ A, B, C ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "correct", "correct") # A demonstrated: B and C are below it
    d.finish!
    assert_equal %w[demonstrated two_of_two], d.state(A)
    assert_equal %w[not_assessed below_demonstrated], d.state(B)
    assert_equal %w[not_assessed below_demonstrated], d.state(C)
    assert_equal 2, d.result[:served]
  end

  test "implicated but demonstrated: a prerequisite implicated on a demonstrated skill goes to the tail as a suspect" do
    plan = build_plan(skills: { A => { prereqs: [ B ], errors: { "slip_b" => [ B ] } }, B => {}, C => {} }, entries: [ A, C ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    d.play("typical_error", error_code: "slip_b")
    d.play("correct")
    d.play("correct") # A: W C C -> hmm needs low-guess C among three: demonstrated two_of_three
    assert_equal %w[demonstrated two_of_three], d.state(A)
    assert_equal [ B ], d.result[:suspects]
    assert_equal C, d.next_skill # the other entry first, the suspect at the tail
    run_to(d, "correct", "correct")
    assert_equal B, d.next_skill # a suspect is served although it is below a demonstrated skill
  end

  test "descent never goes into a block still in study (scope in_progress)" do
    plan = build_plan(skills: { A => { prereqs: [ B ] }, B => { scope: "in_progress" } })
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "wrong", "wrong")
    d.finish!
    assert_equal "frontier_empty", d.end_reason
    assert_equal %w[not_assessed not_needed], d.state(B)
  end

  test "gate on learn chains: an entry whose prerequisite is to_recover with kind learn is not served" do
    skills = { A => { prereqs: [ B ] }, B => { scope: "not_in_prima" } }
    plan = build_plan(skills: skills, entries: [ B, A ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "dont_know") # B resolves to_recover (kind learn)
    d.finish!
    assert_equal %w[to_recover dont_know], d.state(B)
    assert_equal %w[not_assessed prerequisite_to_recover], d.state(A)
    assert_equal "frontier_empty", d.end_reason
  end

  test "a kind_override turns a learn skill into recover, so the gate does not apply" do
    skills = { A => { prereqs: [ B ] }, B => { scope: "not_in_prima" } }
    overrides = [ { "skill" => B, "kind" => "recover", "reason_it" => "gia visto" } ]
    plan = build_plan(skills: skills, entries: [ B, A ], overrides: overrides)
    assert_equal "recover", plan.skill(B).kind
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    d.play("dont_know")
    assert_equal A, d.next_skill
  end

  test "kind: in_progress and not_in_prima are learn, middle_school and the rest are recover" do
    plan = build_plan(skills: { A => { scope: "in_progress" }, B => { scope: "not_in_prima" }, C => { scope: "middle_school" },
                                D => { scope: "integration_studied" } })
    assert_equal %w[learn learn recover recover], [ A, B, C, D ].map { |k| plan.skill(k).kind }
  end

  test "composite skill: its parts are descent targets" do
    plan = build_plan(skills: { A => { composite_of: [ B, C ] }, B => {}, C => {} })
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "wrong", "wrong")
    assert_equal B, d.next_skill
  end

  test "cross subject: a resolved target in another run is reused, otherwise cross_subject_unavailable" do
    skills = { A => { prereqs: [ "italian.x", "italian.y" ] }, "italian.x" => {}, "italian.y" => {} }
    ext = { "italian.x" => { "state" => "demonstrated", "reason" => "two_of_two" } }
    plan = build_plan(skills: skills, external: ext)
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "wrong", "wrong")
    d.finish!
    assert_equal "frontier_empty", d.end_reason
    assert_equal %w[demonstrated two_of_two], d.state("italian.x")
    assert_equal %w[not_assessed cross_subject_unavailable], d.state("italian.y")
    assert_equal [ { skill: "italian.y", check: "cross_subject_unavailable" } ], d.result[:checks]
    assert_equal 2, d.result[:served]
  end

  test "guest starting skill: served here unless it is already resolved elsewhere" do
    skills = { A => {}, "italian.g" => {} }
    plan = build_plan(skills: skills, entries: [ "italian.g", A ], guests: { "italian.g" => "italian" })
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    assert_equal "italian.g", d.next_skill

    reused = build_plan(skills: skills, entries: [ "italian.g", A ], guests: { "italian.g" => "italian" },
                        external: { "italian.g" => { "state" => "to_recover", "reason" => "two_wrong" } })
    r = DiagnosisHelper::Driver.new(reused)
    r.start
    assert_equal A, r.next_skill
    assert_equal %w[to_recover two_wrong], r.state("italian.g")
  end

  # ---- per-skill sequencing --------------------------------------------------

  test "two_correct_distinct_instances_demonstrates" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    s1 = d.play("correct")
    s2 = d.play("correct")
    refute_equal s1.instance.id, s2.instance.id
    assert_equal %w[demonstrated two_of_two], d.state(A)
  end

  test "the second item is another item when the pool has one" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    first = d.play("correct")
    second = d.play("correct")
    refute_equal first.instance.item, second.instance.item
  end

  test "choice_only_pair_is_weaker_reason" do
    items = { A => %w[ch1 ch2] }
    pool = { "ch1" => { "component" => "choice", "instances" => 2 }, "ch2" => { "component" => "choice", "instances" => 2 } }
    plan = build_plan(skills: { A => {} }, items: items, pool: pool, choice_only: [ A ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "correct", "correct")
    assert_equal %w[demonstrated two_of_two_choice], d.state(A)
  end

  test "item 1 is low-guess unless the skill is choice-only" do
    pool = { "ch" => { "component" => "choice", "instances" => 3 }, "ty" => { "component" => "number", "instances" => 3 } }
    plan = build_plan(skills: { A => {} }, items: { A => %w[ch ty] }, pool: pool)
    10.times do |i|
      p2 = build_plan(skills: { A => {} }, items: { A => %w[ch ty] }, pool: pool, salt: "s#{i}")
      d = DiagnosisHelper::Driver.new(p2)
      d.start
      assert d.action.instance.low_guess, "salt s#{i}"
    end
    assert plan
  end

  test "mixed_pair_third_item_is_low_guess" do
    pool = { "ch" => { "component" => "choice", "instances" => 4 }, "ty" => { "component" => "number", "instances" => 4 } }
    10.times do |i|
      plan = build_plan(skills: { A => {} }, items: { A => %w[ch ty] }, pool: pool, salt: "t#{i}")
      d = DiagnosisHelper::Driver.new(plan)
      d.start
      run_to(d, "correct", "wrong")
      third = d.action
      assert_equal A, third.skill
      assert third.instance.low_guess, "third item must be low-guess (salt t#{i})"
      d.play("correct")
      assert_equal %w[demonstrated two_of_three], d.state(A)
    end
  end

  test "mixed pair with no low-guess item left ends as to_recover(mixed)" do
    pool = { "ch" => { "component" => "choice", "instances" => 3 } }
    plan = build_plan(skills: { A => { prereqs: [ B ] }, B => {} }, items: { A => %w[ch] }, pool: pool, choice_only: [ A ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "correct", "wrong")
    assert_equal %w[to_recover mixed], d.state(A)
    assert_equal B, d.next_skill # mixed is to_recover: the descent follows
  end

  test "one C and one W that reaches the serve cap ends to_recover(mixed), not not_assessed(item_cap) (D-073)" do
    pool = { "ty" => { "component" => "number", "instances" => 8 } }
    plan = build_plan(skills: { A => {} }, items: { A => %w[ty] }, pool: pool)
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    run_to(d, "correct", "wrong")
    refute_equal "to_recover", d.state(A).first, "a third low-guess item is still available"
    3.times do # the third, fourth and fifth serves are left open and abandoned: the cap of 5 is reached
      s = d.serve!
      d.push("item_abandoned", serve: s[:seq])
    end
    assert_equal %w[to_recover mixed], d.state(A)
  end

  test "mixed then a wrong third is to_recover(mixed)" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    run_to(d, "correct", "wrong", "wrong")
    assert_equal %w[to_recover mixed], d.state(A)
  end

  test "outcomes_after_resolution_ignored" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    first = d.serve!
    second = nil
    d.answer(first, "undetermined") # pending
    second = d.serve!
    d.answer(second, "correct")
    third = d.serve!
    d.answer(third, "correct") # A demonstrated: C C
    assert_equal %w[demonstrated two_of_two], d.state(A)
    # The teacher resolves the first answer as wrong, after the skill resolved: logged, ignored.
    d.push("resolve_attempt", serve: first[:seq], verdict: "wrong")
    assert_equal %w[demonstrated two_of_two], d.state(A)
    assert_equal 2, d.result[:skills].find { |r| r[:skill] == A }[:evidence].size
  end

  # ---- evidence -------------------------------------------------------------

  test "pending_counts_neither_way" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    3.times { d.play("undetermined") }
    assert_nil d.state(A)[0]
    assert_equal A, d.next_skill # another instance is served
    d.play("near_miss")
    d.play("float_method")
    assert_equal 5, d.result[:skills].find { |r| r[:skill] == A }[:served]
    d.finish!
    # Answers are still pending: the run is held open, not closed as frontier_empty.
    assert_nil d.end_reason
  end

  test "a run never closes frontier_empty while an answer is pending or ungraded" do
    d = DiagnosisHelper::Driver.new(build_plan(skills: { A => {} }))
    d.start
    first = d.serve!
    d.answer(first, "ungraded", retry_state: "running")
    4.times { d.play("undetermined") } # per-skill cap: nothing left to serve
    held = d.action
    assert_equal :wait, held.type
    assert_equal :pending_answers, held.reason
    assert_equal "pending_answers", d.result[:waiting_on]
    assert_equal false, d.result[:closed]

    # The grader answers on a retry: the pending answers that remain still hold it.
    d.push("grading", serve: first[:seq], verdict: "wrong")
    assert_equal :wait, d.action.type
    # Each one is resolved (here by the teacher); only then does the run close.
    d.events.select { |e| e[:kind] == "item_served" }.drop(1).each do |e|
      d.push("resolve_attempt", serve: e[:seq], verdict: "wrong")
    end
    closing = d.action
    assert_equal :close_run, closing.type
    assert_equal "frontier_empty", closing.reason
    d.finish!
    assert_equal "frontier_empty", d.end_reason
    assert_nil d.result[:waiting_on]
  end

  test "a teacher close ends a run that is waiting on pending answers" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    5.times { d.play("undetermined") }
    assert_equal :wait, d.action.type
    d.push("close_diagnosis_run")
    assert_equal :none, d.action.type
    assert_equal "teacher_close", d.end_reason
  end

  test "an answer on a skill that already resolved does not hold the run" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    first = d.serve!
    d.answer(first, "undetermined")
    d.play("correct")
    d.play("correct") # A resolved: the first answer is ignored from now on
    d.finish!
    assert_equal "frontier_empty", d.end_reason
  end

  test "at the cap with ungraded answers the state is pending with its reason" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    4.times { d.play("ungraded", retry_state: "running") }
    d.play("ungraded", retry_state: "exhausted")
    d.finish!

    running = DiagnosisHelper::Driver.new(chain_plan)
    running.start
    5.times { running.play("ungraded", retry_state: "running") }
    running.finish!
    assert_equal %w[pending grader_unavailable], running.state(A)
  end

  test "retry_verdict_counts_without_decision" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    first = d.serve!
    d.answer(first, "ungraded", retry_state: "running")
    assert_nil d.state(A)[0]
    d.play("correct")
    d.clock.advance(30)
    d.push("grading", serve: first[:seq], verdict: "correct") # the grader answers on retry
    assert_equal %w[demonstrated two_of_two], d.state(A)
  end

  test "uncertain_verdict_needs_decision_row" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    first = d.serve!
    d.answer(first, "undetermined")
    d.play("correct")
    assert_nil d.state(A)[0] # one credit and a pending answer: not demonstrated
    d.play("correct") # a distinct certain credit is what counts
    assert_equal %w[demonstrated two_of_two], d.state(A)

    solo = DiagnosisHelper::Driver.new(chain_plan)
    solo.start
    one = solo.serve!
    solo.answer(one, "undetermined")
    solo.push("resolve_attempt", serve: one[:seq], verdict: "correct") # the decision row
    solo.play("correct")
    assert_equal %w[demonstrated two_of_two], solo.state(A)
  end

  test "a teacher resolution of an answer that already counted is applied in place" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    first = d.serve!
    d.answer(first, "correct")
    d.push("resolve_attempt", serve: first[:seq], verdict: "wrong") # the grader was wrong
    d.play("wrong")
    assert_equal %w[to_recover two_wrong], d.state(A)
  end

  test "wrong_form_routes_form_skill: a declared form is credited and the form skill becomes a suspect" do
    plan = build_plan(skills: { A => { prereqs: [ B ] }, B => {}, C => {} }, entries: [ A, C ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    d.play("wrong_form", form: "declared", form_skill: B)
    d.play("correct")
    assert_equal %w[demonstrated two_of_two], d.state(A)
    assert_equal [ B ], d.result[:suspects]
    assert_equal [ { skill: B, about: A, kind: "wrong_form_declared" } ], d.result[:observations]
    assert_equal C, d.next_skill
  end

  test "wrong_form on the skill itself is a W; undeclared is pending" do
    plan = build_plan(skills: { A => {} })
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    2.times { d.play("wrong_form", form: "skill") }
    assert_equal %w[to_recover two_wrong], d.state(A)

    u = DiagnosisHelper::Driver.new(plan)
    u.start
    u.play("wrong_form")
    assert_nil u.state(A)[0]
  end

  test "wrong_form on the skill itself with a declared code stays in the node; an undeclared code descends" do
    declared = build_plan(skills: { A => { prereqs: [ B ], errors: { "not_fully_factored" => [] } }, B => {} })
    d = DiagnosisHelper::Driver.new(declared)
    d.start
    2.times { d.play("wrong_form", form: "skill", error_code: "not_fully_factored") }
    assert_equal %w[to_recover two_wrong], d.state(A)
    assert_nil d.state(B)[0]

    undeclared = build_plan(skills: { A => { prereqs: [ B ] }, B => {} })
    u = DiagnosisHelper::Driver.new(undeclared)
    u.start
    2.times { u.play("wrong_form", form: "skill", error_code: "lowest_terms") }
    assert_equal B, u.next_skill
  end

  test "orthography_masks_form: an accent slip is credit with an observation and no descent" do
    plan = build_plan(skills: { A => { prereqs: [ B ], errors: { "es_accents" => [ B ] } }, B => {} })
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    2.times { d.play("typical_error", error_code: "es_accents", orthography_slip: true, orthography_skill: B) }
    assert_equal %w[demonstrated two_of_two], d.state(A)
    assert_equal 2, d.result[:observations].size
    assert_equal [], d.result[:suspects]
  end

  # ---- testlets -----------------------------------------------------------------

  test "testlet_counts_one_outcome_per_skill" do
    testlet = instance("tl#1", skills: [ A, A, B ], kind: "testlet", seconds: 120)
    plan = with_instances(build_plan(skills: { A => {}, B => {} }, items: { A => %w[x1] }, pool: { "x1" => { "instances" => 1 } }), [ testlet ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    serve = d.push("item_served", instance: "tl#1", skill: A)
    # two sub-items on A, one on B: A counts once, B once
    d.answer(serve, "correct", skill: A)
    d.push("answered", serve: serve[:seq], skill: A, verdict: "correct")
    d.push("answered", serve: serve[:seq], skill: B, verdict: "wrong")
    a = d.result[:skills].find { |r| r[:skill] == A }
    assert_equal [ "C" ], a[:evidence]
    assert_nil d.state(A)[0] # one counted outcome only: the second must come from another item
    b = d.result[:skills].find { |r| r[:skill] == B }
    assert_equal [ "W" ], b[:evidence]
  end

  test "one passage is served once per run (D-099)" do
    tls = [ instance("tl#1", skills: [ A ], kind: "testlet", seconds: 120, item: "tl"), instance("tl#2", skills: [ A ], kind: "testlet", seconds: 120, item: "tl") ]
    base = build_plan(skills: { A => {} }, items: { A => %w[x1] }, pool: { "x1" => { "instances" => 1 } })
    8.times do |salt|
      p2 = Diagnosis::Plan.new(subject: base.subject, entries: base.entries, skills: base.skills, pool: tls.to_h { |i| [ i.id, i ] },
                               sitting_seconds: base.sitting_seconds, sittings: base.sittings, seed_salt: "s#{salt}")
      d = DiagnosisHelper::Driver.new(p2)
      d.start
      6.times { d.play("wrong", skill: A) if d.action.type == :serve }
      served = d.events.select { |e| e[:kind] == "item_served" }.map { |e| e[:instance] }
      assert_equal 1, served.size, "salt #{salt}: #{served.inspect}"
    end
  end

  test "a testlet sibling skill is not charged a serve it never answers (D-098)" do
    tl = instance("tl#1", skills: [ A ], kind: "testlet", seconds: 120)
    plan = with_instances(build_plan(skills: { A => {}, B => {} }, items: { A => %w[x1] }, pool: { "x1" => { "instances" => 1 } }), [ tl ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    s = d.push("item_served", instance: "tl#1", skill: A)
    d.answer(s, "correct", skill: A)
    assert_equal 0, d.result[:skills].find { |r| r[:skill] == B }&.fetch(:served, 0).to_i
  end

  test "a pending testlet answer holds the skill: no second testlet until it is settled (D-130)" do
    tls = %w[a b c].map { |n| instance("tl-#{n}#1", skills: [ A ], kind: "testlet", seconds: 300, item: "tl-#{n}") }
    base = build_plan(skills: { A => {} }, items: { A => %w[x1] }, pool: { "x1" => { "instances" => 1 } })
    plan = Diagnosis::Plan.new(subject: base.subject, entries: base.entries, skills: base.skills, pool: tls.to_h { |i| [ i.id, i ] },
                               sitting_seconds: base.sitting_seconds, sittings: base.sittings, seed_salt: "s")
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    d.play("undetermined", skill: A)
    a = d.action
    assert_equal :wait, a.type
    assert_equal :pending_answers, a.reason
    assert_equal 1, d.events.count { |e| e[:kind] == "item_served" }
  end

  test "a testlet decides low_guess and choice per skill from its sub items (D-096)" do
    flags = { A => { low_guess: false, choice: true } }
    tl = Diagnosis::Plan::Instance.new(id: "tl#1", item: "tl", skills: [ A ], component: "number", low_guess: true, choice: false,
                                       expected_seconds: 120, fingerprint: "tlfp", kind: "testlet", flags: flags)
    assert_not tl.low_guess_for(A)
    assert tl.choice_for(A)
    base = build_plan(skills: { A => {} }, items: { A => %w[x1] }, pool: { "x1" => { "instances" => 2, "component" => "choice" } })
    plan = with_instances(base, [ tl ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    s1 = d.push("item_served", instance: "tl#1", skill: A)
    d.answer(s1, "correct", skill: A)
    s2 = d.push("item_served", instance: "x1#1", skill: A)
    d.answer(s2, "correct", skill: A)
    assert_equal %w[demonstrated two_of_two_choice], d.state(A)
  end

  test "testlet_not_started_when_budget_insufficient" do
    testlet = instance("tl#1", skills: [ A ], kind: "testlet", seconds: 700)
    base = build_plan(skills: { A => {} }, items: { A => %w[x1] }, pool: { "x1" => { "instances" => 2, "component" => "choice" } },
                      minutes: 10)
    plan = with_instances(base, [ testlet ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    # 10 minute sitting: remaining 600 - 420 reserve = 180 s: the 700 s testlet does not start.
    a = d.action
    refute a.instance.testlet?, "the testlet must not be chosen while its expected time does not fit"
    only_testlet = build_plan(skills: { A => {} }, items: { A => %w[x1] }, pool: { "x1" => { "instances" => 1 } }, minutes: 10)
    only_testlet = with_instances(Diagnosis::Plan.new(subject: only_testlet.subject, entries: only_testlet.entries, skills: only_testlet.skills,
                                                       pool: {}, sitting_seconds: 600, sittings: 2), [ testlet ])
    t = DiagnosisHelper::Driver.new(only_testlet)
    t.start
    assert_equal :end_sitting, t.action.type
    assert_equal "time_budget", t.action.reason
  end

  test "a testlet that does not fit ends the sitting instead of repeating the item already used (no_fit)" do
    entries = [ Diagnosis::Plan::Entry.new(skill: A, guest_of: nil, choice_only: false) ]
    base = Diagnosis::Plan.new(subject: "math", entries: entries, skills: { A => Diagnosis::Plan.flat_skill(A, {}) }, pool: {},
                               sitting_seconds: 1500, sittings: 2)
    plan = with_instances(base, [ instance("x#1", skills: [ A ], component: "number", seconds: 60, item: "x"), instance("x#2", skills: [ A ], component: "number", seconds: 60, item: "x"),
                                  instance("x#3", skills: [ A ], component: "number", seconds: 60, item: "x"),
                                  instance("tl#1", skills: [ A ], kind: "testlet", component: "choice", low_guess: false, seconds: 600) ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    d.play("correct", seconds: 600) # 1500 - 600 - 420 = 480 s left: the 600 s testlet does not fit
    a = d.action
    assert_equal :end_sitting, a.type
    assert_equal "time_budget", a.reason
  end

  test "a testlet that fits is served as one unit" do
    testlet = instance("tl#1", skills: [ A ], kind: "testlet", seconds: 120)
    plan = with_instances(Diagnosis::Plan.new(subject: "math", entries: [ Diagnosis::Plan::Entry.new(skill: A, guest_of: nil, choice_only: false) ],
                                              skills: { A => Diagnosis::Plan.flat_skill(A, {}) }, pool: {}, sitting_seconds: 1800, sittings: 2), [ testlet ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    a = d.action
    assert_equal "tl#1", a.instance.id
  end

  test "flat_graph_is_fixed_form: only the entries are served, in order" do
    plan = build_plan(skills: { A => {}, B => {}, C => {} }, entries: [ A, B, C ])
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    order = []
    6.times { order << d.play("wrong").skill }
    d.finish!
    assert_equal [ A, A, B, B, C, C ], order
    assert_equal "frontier_empty", d.end_reason
  end

  # ---- short answer, redo -----------------------------------------------------------

  def short_plan(minutes: 30, sittings: 2)
    skills = { A => {}, B => {}, C => {}, D => {}, "math.e" => {}, "math.s" => {} }
    base = build_plan(skills: skills, entries: [ A, B, C, D, "math.e" ], minutes: minutes, sittings: sittings)
    short = instance("sa#1", skills: [ "math.s" ], kind: "short_answer", component: "short_answer", seconds: 300)
    with_instances(base, [ short ])
  end

  def no_fit_plan(sittings:)
    entries = [ B, A ].map { |k| Diagnosis::Plan::Entry.new(skill: k, guest_of: nil, choice_only: false) }
    skills = { A => Diagnosis::Plan.flat_skill(A, {}), B => Diagnosis::Plan.flat_skill(B, {}), "math.s" => Diagnosis::Plan.flat_skill("math.s", {}) }
    base = Diagnosis::Plan.new(subject: "math", entries: entries, skills: skills, pool: {}, sitting_seconds: 1500, sittings: sittings)
    with_instances(base, [ instance("b#1", skills: [ B ], component: "choice", seconds: 60), instance("b#2", skills: [ B ], component: "choice", seconds: 60),
                           instance("tl#1", skills: [ A ], kind: "testlet", seconds: 600),
                           instance("sa#1", skills: [ "math.s" ], kind: "short_answer", component: "short_answer", seconds: 300) ])
  end

  test "a testlet that does not fit does not stop the short answer from being served" do
    d = DiagnosisHelper::Driver.new(no_fit_plan(sittings: 1))
    d.start
    2.times { d.play("correct", seconds: 300) } # 600 s counted: 1500 - 600 - 420 = 480 s left, the 600 s testlet does not fit
    a = d.action
    assert_equal :serve, a.type
    assert_equal "short_answer", a.reason
  end

  test "short_answer_served_at_open_reserve" do
    d = DiagnosisHelper::Driver.new(short_plan)
    d.start
    # Fill 23 minutes (30 - 7 reserve) with slow items, then the short answer comes before anything else.
    seen = []
    until d.action.reason == "short_answer"
      seen << d.action.skill
      d.play("correct", seconds: 300)
      break if seen.size > 10
    end
    assert_equal "short_answer", d.action.reason
    assert_operator d.result[:counted_seconds], :>=, 23 * 60
  end

  test "an abandoned short answer is served again, not closed as not_needed" do
    d = DiagnosisHelper::Driver.new(short_plan)
    d.start
    10.times { d.play("correct", seconds: 20) }
    s = d.serve!
    assert_equal "sa#1", s[:instance]
    d.clock.advance(Diagnosis::Rules::V1::ABANDON_GAP_SECONDS)
    assert_equal :abandon_item, d.action.type
    d.push("item_abandoned", serve: s[:seq])
    a = d.action
    assert_equal :serve, a.type
    assert_equal "short_answer", a.reason
    s2 = d.serve!
    d.answer(s2, "short_answer")
    d.finish!
    assert_equal %w[pending grade_unconfirmed], d.state("math.s")
  end

  test "short answer is served at frontier empty when the budget is not reached" do
    d = DiagnosisHelper::Driver.new(short_plan)
    d.start
    10.times { d.play("correct", seconds: 20) } # every entry demonstrated
    assert_equal "short_answer", d.action.reason
    s = d.serve!
    d.answer(s, "short_answer")
    d.finish!
    assert_nil d.end_reason # held open until the teacher confirms the grade
    assert_equal %w[pending grade_unconfirmed], d.state("math.s")
    d.push("confirm_grade", serve: s[:seq], passed: true)
    assert_equal %w[demonstrated short_answer_above_threshold], d.state("math.s")
    d.finish!
    assert_equal "frontier_empty", d.end_reason
  end

  test "confirm_grade below the threshold is to_recover" do
    d = DiagnosisHelper::Driver.new(short_plan)
    d.start
    10.times { d.play("correct", seconds: 20) }
    s = d.serve!
    d.answer(s, "short_answer")
    d.push("confirm_grade", serve: s[:seq], passed: false)
    assert_equal %w[to_recover short_answer_below_threshold], d.state("math.s")
  end

  test "short_answer_carried_to_second_sitting" do
    d = DiagnosisHelper::Driver.new(short_plan)
    d.start
    d.push("sitting_closed", reason: "item_cap") # the first sitting ended before the short answer
    d.clock.advance_to(Date.new(2026, 11, 3))
    d.push("sitting_started")
    a = d.action
    assert_equal "short_answer", a.reason
  end

  test "short answer unserved when the run closes: not_assessed(time_budget)" do
    d = DiagnosisHelper::Driver.new(short_plan(sittings: 1))
    d.start
    d.push("close_diagnosis_run")
    assert_equal %w[not_assessed not_started], d.state("math.s")

    t = DiagnosisHelper::Driver.new(short_plan(minutes: 10, sittings: 1))
    t.start
    t.push("run_closed", reason: "time_budget")
    assert_equal %w[not_assessed time_budget], t.state("math.s")
  end

  test "redo_never_serves_seen_instance" do
    plan = chain_plan
    first = DiagnosisHelper::Driver.new(plan)
    first.start
    served = Set.new
    2.times { served << first.play("correct").instance.fingerprint }
    replay = chain_plan(seen: served.to_a)
    r = DiagnosisHelper::Driver.new(replay)
    r.start
    2.times { refute_includes served, r.play("correct").instance.fingerprint }
  end

  test "a skill with no unseen instance is not_assessed(no_unseen_items)" do
    all = chain_plan.pool.values.select { |i| i.skills == [ A ] }.map(&:fingerprint)
    plan = chain_plan(seen: all)
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    d.finish!
    assert_equal %w[not_assessed no_unseen_items], d.state(A)
  end

  # ---- teacher decisions --------------------------------------------------------------

  test "close_diagnosis_run ends the run with teacher_close and the unserved skills are not_started" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    d.play("wrong")
    d.push("close_diagnosis_run")
    assert_equal :none, d.action.type
    assert_equal "teacher_close", d.end_reason
    assert_equal %w[not_assessed time_budget], d.state(A)
  end

  test "a voided run has every skill not_assessed(voided)" do
    d = DiagnosisHelper::Driver.new(chain_plan)
    d.start
    2.times { d.play("correct") }
    states = Diagnosis::Derivation.states(chain_plan, d.events, voided: true)
    assert_equal [ %w[not_assessed voided] ], states.values.uniq
  end

  test "a skill with a cycle in the graph is rejected" do
    assert_raises(Diagnosis::Plan::CycleError) do
      build_plan(skills: { A => { prereqs: [ B ] }, B => { prereqs: [ A ] } })
    end
  end

  test "events may carry string keys and no seq" do
    plan = chain_plan
    served = plan.instances_for(A).first
    log = [ { "kind" => "sitting_started", "at" => Diagnosis::FakeClock::START },
            { "kind" => "item_served", "at" => Diagnosis::FakeClock::START, "instance" => served.id },
            { "kind" => "answered", "at" => Diagnosis::FakeClock::START + 30, "serve" => 2, "verdict" => "correct" } ]
    state = Diagnosis::Engine.fold(plan, log)
    assert_equal 1, state.outcome(A).outcomes.size
  end
end
