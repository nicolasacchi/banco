require "test_helper"
require_relative "../../support/diagnosis_helper"

# Properties of the pure engine over random acyclic skill graphs (B-10). Every
# check names its seed in the failure message. PROP_RUNS sets the number of
# random cases per property (300 in CI, 2000 at night).
class DiagnosisPropertiesTest < ActiveSupport::TestCase
  include DiagnosisHelper

  RUNS = Integer(ENV.fetch("PROP_RUNS", 50))

  # A student with a set of known skills. noise: chance of an uncertain answer.
  class KnowingStudent
    # slip: chance a known skill is answered wrong; guess: chance an unknown one
    # is answered right. plan, when given, lets a wrong answer carry a catalogue code.
    def initialize(known, rng, noise: 0.0, slip: 0.0, guess: 0.0, plan: nil, seconds: nil, typical: false)
      @known = known
      @rng = rng
      @noise = noise
      @slip = slip
      @guess = guess
      @plan = plan
      @typical = typical
      @seconds = seconds
    end

    def confirm_short = nil

    def answer(ctx)
      inst = ctx[:instance]
      secs = @seconds || (10 + @rng.rand(400))
      return { verdict: "short_answer", seconds: secs } if inst.short_answer?
      return { verdict: "undetermined", seconds: secs } if @noise.positive? && @rng.rand < @noise
      right = @known.include?(ctx[:skill]) ? @rng.rand >= @slip : @rng.rand < @guess
      return { verdict: "correct", seconds: secs } if right

      if @typical
        codes = @plan&.skill(ctx[:skill])&.errors&.keys || []
        return { verdict: "typical_error", error_code: codes.sample(random: @rng), seconds: secs } if codes.any? && @rng.rand < 0.5
        return { verdict: "dont_know", seconds: secs } if @rng.rand < 0.1
      end

      { verdict: "wrong", seconds: secs }
    end
  end

  # A random plan and the set of skills the student knows.
  def random_case(seed, short: false, big_budget: false)
    rng = Random.new(seed)
    n = 3 + rng.rand(12)
    keys = (1..n).map { |i| "math.s#{i}" }
    skills = keys.each_with_index.to_h do |k, i|
      prereqs = keys.first(i).select { rng.rand < 0.3 }.first(3) # edges only to lower indexes: acyclic
      errors = prereqs.empty? ? {} : { "e#{i}" => prereqs.sample(1 + rng.rand(prereqs.size), random: rng) }
      errors["own#{i}"] = [] if rng.rand < 0.3
      scope = %w[studied studied studied integration_studied middle_school not_in_prima in_progress].sample(random: rng)
      [ k, { prereqs: prereqs, errors: errors, scope: scope } ]
    end
    entries = keys.sample(1 + rng.rand([ n, 6 ].min), random: rng)
    plan = build_plan(skills: skills, entries: entries, salt: "salt#{seed}",
                      minutes: big_budget ? 60 : 8 + rng.rand(15), sittings: 1 + rng.rand(2))
    if short
      plan = with_instances(plan, [ instance("sa#1", skills: [ "math.short" ], kind: "short_answer", component: "short_answer", seconds: 200) ])
    end
    known = keys.select { rng.rand < 0.5 }
    [ plan, known, rng ]
  end

  def run_case(seed, **opts)
    plan, known, rng = random_case(seed, **opts.slice(:short, :big_budget))
    student = KnowingStudent.new(known, rng, noise: opts.fetch(:noise, 0.0), slip: opts.fetch(:slip, 0.0),
                                             guess: opts.fetch(:guess, 0.0), plan: plan, typical: opts.fetch(:typical, false))
    # The teacher resolves what the grader left pending, so that every run can close.
    [ plan, known, Diagnosis::Simulator.run(plan, student, resolve_pending: "wrong") ]
  end

  def each_seed
    RUNS.times { |i| yield(7000 + i) }
  end

  # Odd seeds get a student who slips, guesses and sometimes gives an uncertain answer.
  def messy(seed) = seed.odd? ? { slip: 0.15, guess: 0.25, noise: 0.1, typical: true } : {}

  test "termination within 5 x reachable + 1 serves, and the run closes" do
    each_seed do |seed|
      plan, _known, out = run_case(seed, short: seed.odd?, **messy(seed))
      assert_equal "run_closed", out[:events].last[:kind], "seed=#{seed}"
      limit = 5 * plan.reachable.size + 1
      assert_operator out[:result][:served], :<=, limit, "seed=#{seed}"
      assert_includes Diagnosis::Rules::V1::END_REASONS, out[:result][:end_reason], "seed=#{seed}"
    end
  end

  test "without a resolution a run either closes or waits only on pending answers" do
    each_seed do |seed|
      plan, known, rng = random_case(seed, short: seed.odd?)
      student = KnowingStudent.new(known, rng, plan: plan, **messy(seed).slice(:slip, :guess, :noise, :typical))
      out = Diagnosis::Simulator.run(plan, student)
      if out[:events].last[:kind] == "run_closed"
        assert_nil out[:result][:waiting_on], "seed=#{seed}"
      else
        assert_equal "pending_answers", out[:result][:waiting_on], "seed=#{seed}"
        assert_equal false, out[:result][:closed], "seed=#{seed}"
      end
    end
  end

  test "no fingerprint is served twice in a run" do
    each_seed do |seed|
      plan, _known, out = run_case(seed, short: true, **messy(seed))
      prints = out[:events].select { |e| e[:kind] == "item_served" }.map { |e| plan.pool[e[:instance]].fingerprint }
      assert_equal prints.uniq, prints, "seed=#{seed}"
    end
  end

  test "with a noise-free student the demonstrated skills are known, and resolved unknown ones are to_recover" do
    each_seed do |seed|
      _plan, known, out = run_case(seed, big_budget: true)
      out[:result][:skills].each do |row|
        next unless row[:source] == "run"

        if row[:state] == "demonstrated"
          assert_includes known, row[:skill], "seed=#{seed} #{row[:skill]} demonstrated but unknown"
        elsif row[:state] == "to_recover"
          refute_includes known, row[:skill], "seed=#{seed} #{row[:skill]} to_recover but known"
        end
      end
    end
  end

  test "a minimal unknown skill that is reached is to_recover with unclassified evidence only" do
    each_seed do |seed|
      plan, known, out = run_case(seed, big_budget: true)
      out[:result][:skills].each do |row|
        next unless row[:state] == "to_recover" && row[:source] == "run"

        parents = plan.skill(row[:skill]).parents
        next unless parents.all? { |p| known.include?(p) }

        assert_equal %w[W W], row[:evidence], "seed=#{seed} #{row[:skill]}"
        assert_equal [], row[:error_codes], "seed=#{seed}"
      end
    end
  end

  test "never serves below a demonstrated skill, except a suspect" do
    each_seed do |seed|
      plan, _known, out = run_case(seed, big_budget: true, **messy(seed))
      out[:events].each_with_index do |ev, i|
        next unless ev[:kind] == "item_served"

        before = Diagnosis::Engine.fold(plan, out[:events].first(i))
        skill = plan.pool[ev[:instance]].skill
        next if before.origin[skill] == :suspect

        refute before.below.include?(skill), "seed=#{seed} served #{skill} below a demonstrated skill"
      end
    end
  end

  test "pending never decides: an always-uncertain student resolves nothing" do
    each_seed do |seed|
      plan, _known, rng = random_case(seed)
      student = KnowingStudent.new([], rng, noise: 1.0)
      out = Diagnosis::Simulator.run(plan, student)
      states = out[:result][:skills].map { |r| r[:state] }
      refute_includes states, "demonstrated", "seed=#{seed}"
      refute_includes states, "to_recover", "seed=#{seed}"
    end
  end

  test "pending never decides: uncertain answers never turn an unknown skill into demonstrated" do
    each_seed do |seed|
      _plan, known, out = run_case(seed, noise: 0.4, big_budget: true)
      out[:result][:skills].each do |row|
        next unless row[:state] == "demonstrated"

        assert_includes known, row[:skill], "seed=#{seed}"
        assert_equal %w[C C], row[:evidence].first(2), "seed=#{seed}" if row[:reason] == "two_of_two"
      end
    end
  end

  test "nothing is served after the budget, and the short answer comes by budget minus the reserve" do
    each_seed do |seed|
      plan, _known, out = run_case(seed, short: true, **messy(seed))
      events = out[:events]
      events.each_with_index do |ev, i|
        next unless ev[:kind] == "item_served"

        state = Diagnosis::Engine.fold(plan, events.first(i))
        sitting = state.open_sitting
        counted = state.sitting_counted_seconds(sitting)
        assert_operator counted, :<, plan.sitting_seconds, "seed=#{seed} served at #{counted}s of #{plan.sitting_seconds}"
        short_unserved = state.short_serve.nil?
        reserve_start = plan.sitting_seconds - Diagnosis::Rules::V1::OPEN_RESERVE_MINUTES * 60
        is_short = plan.pool[ev[:instance]].short_answer?
        assert is_short, "seed=#{seed} served another item at #{counted}s with the short answer due" if short_unserved && counted >= reserve_start
      end
    end
  end

  test "the derivation is pure: events are not touched and a replay gives the same answer" do
    each_seed do |seed|
      plan, _known, out = run_case(seed, short: true, **messy(seed))
      frozen = out[:events].map { |e| e.dup.freeze }.freeze
      first = Diagnosis::Derivation.result(plan, frozen)
      second = Diagnosis::Derivation.result(plan, frozen)
      assert_equal first, second, "seed=#{seed}"
      assert_equal out[:result], first, "seed=#{seed}"
    end
  end

  test "determinism for a seed: same plan, same student, same trace" do
    each_seed do |seed|
      _p, _k, a = run_case(seed, short: true, **messy(seed))
      _p, _k, b = run_case(seed, short: true, **messy(seed))
      assert_equal a[:trace], b[:trace], "seed=#{seed}"
    end
  end

  test "a prerequisite cycle is rejected" do
    each_seed do |seed|
      rng = Random.new(seed)
      n = 3 + rng.rand(6)
      keys = (1..n).map { |i| "math.c#{i}" }
      skills = keys.each_with_index.to_h { |k, i| [ k, { prereqs: i.zero? ? [] : [ keys[i - 1] ] } ] }
      skills[keys.first][:prereqs] = [ keys.last ] # close the ring
      assert_raises(Diagnosis::Plan::CycleError, "seed=#{seed}") { build_plan(skills: skills, entries: keys.first(1)) }
    end
  end
end
