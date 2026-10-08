require "test_helper"
require_relative "../../support/practice_engine_helper"

# Properties of the pure practice engine over random histories. Every check names its seed in the
# failure message. PROP_RUNS sets the number of random cases per property (300 in CI).
class PracticePropertiesTest < ActiveSupport::TestCase
  include PracticeEngineHelper

  RUNS = Integer(ENV.fetch("PROP_RUNS", 50))
  OUTCOMES = %i[correct correct correct correct_aided typical_error unrecognised form near_miss undetermined].freeze

  # A random history of one skill: serves in order, each with 1-3 tries.
  def history(rng)
    serve = 0
    at = T0
    Array.new(1 + rng.rand(14)) do
      serve += 1
      at += rng.rand(1..40) * 3600 * (rng.rand < 0.2 ? 24 : 1)
      fp = "f#{rng.rand(7)}"
      Array.new(1 + rng.rand(3)) do |i|
        outcome = OUTCOMES.sample(random: rng)
        aided = outcome == :correct_aided || rng.rand < 0.15
        try_at(at: at + i * 60, serve: serve, try_number: i + 1, fp: "#{fp}-s#{serve}", outcome: outcome, aided: aided, low: rng.rand < 0.6,
               codes: outcome == :typical_error ? [ "e#{rng.rand(3)}" ] : [])
      end
    end.flatten
  end

  def each_case
    RUNS.times { |i| yield i, Random.new(i * 7919 + 13) }
  end

  test "replaying the same rows gives the same states, whatever the order they are listed in" do
    each_case do |i, rng|
      tries = history(rng)
      seed = [ nil, seed_of("demonstrated"), seed_of("to_recover") ].sample(random: rng)
      assert_equal fold(tries, seed: seed), fold(tries.shuffle(random: rng), seed: seed), "seed #{i}"
    end
  end

  test "counts only grow when tries are added" do
    each_case do |i, rng|
      tries = history(rng)
      previous = nil
      tries.each_index do |n|
        counts = fold(tries.first(n + 1)).counts
        if previous
          %i[serves tries correct_unaided correct_aided wrong unrecognised near_miss undetermined seconds].each do |k|
            assert_operator counts[k], :>=, previous[k], "seed #{i}: #{k} after #{n + 1} tries"
          end
        end
        previous = counts
      end
    end
  end

  test "taking tries away (voids) never adds to any count" do
    each_case do |i, rng|
      tries = history(rng)
      kept = tries.reject { rng.rand < 0.3 }
      full = fold(tries).counts
      less = fold(kept).counts
      %i[serves tries correct_unaided correct_aided wrong unrecognised near_miss undetermined seconds].each do |k|
        assert_operator less[k], :<=, full[k], "seed #{i}: #{k}"
      end
      less[:typical].each { |code, n| assert_operator n, :<=, full[:typical].fetch(code, 0), "seed #{i}: #{code}" }
    end
  end

  test "states are always among the seven, and a state implies its facts" do
    each_case do |i, rng|
      tries = history(rng)
      s = fold(tries)
      assert_includes Practice::Rules::V1::STATES, s.state, "seed #{i}"
      assert s.demonstrated_at, "seed #{i}: #{s.state} without demonstrated_at" if %w[demonstrated consolidated].include?(s.state)
      assert s.consolidated_at, "seed #{i}: consolidated without consolidated_at" if s.state == "consolidated"
      assert_equal "not_seen", s.state, "seed #{i}" if tries.empty?
      assert_not_equal "not_seen", s.state, "seed #{i}: tries but not_seen" if tries.any?
    end
  end

  test "aided and re-seen tries alone never demonstrate" do
    each_case do |i, rng|
      tries = history(rng).map { |t| rng.rand < 0.5 ? t.with(aided: true) : t.with(reseen: true, aided: true) }
      assert_includes %w[in_study], fold(tries).state, "seed #{i}"
    end
  end

  test "demonstrating needs three fingerprints, two days and two low-guess ones: dropping the low-guess flags removes the state" do
    each_case do |i, rng|
      tries = history(rng)
      flat = fold(tries.map { |t| t.with(low_guess: false) }).state
      assert_equal "in_study", flat, "seed #{i}" if tries.any?
    end
  end

  test "a seed that is not demonstrated cannot be left except through in_study" do
    each_case do |i, rng|
      s = fold(history(rng), seed: seed_of("to_recover")).state
      assert_includes %w[in_study demonstrated consolidated to_review], s, "seed #{i}"
      assert_equal "to_recover", fold([], seed: seed_of("to_recover")).state
    end
  end

  test "the serve state machine never stores more than three tries and never reopens" do
    each_case do |i, rng|
      play = PracticeEngineHelper::Play.new(hints_total: rng.rand(0..4))
      closed = false
      30.times do
        event = %i[answer answer answer hint solution].sample(random: rng)
        case event
        when :answer then play.answer(%i[correct typical_error unrecognised form near_miss undetermined invalid].sample(random: rng))
        when :hint then play.hint(rng.rand(0..5))
        else play.solution
        end
        status = play.status
        assert_operator play.outcomes.size, :<=, 3, "seed #{i}"
        assert_equal(true, status.state == :closed) if closed
        closed ||= status.state == :closed
        assert_nil status.next_try_number unless status.state == :open
        assert_operator status.hints_shown, :<=, play.hints_total, "seed #{i}"
      end
    end
  end

  Candidate = Practice::Selector::Candidate

  test "choose never repeats a fingerprint while an unseen one exists, and is stable" do
    each_case do |i, rng|
      pool = Array.new(rng.rand(1..14)) { |n| Candidate.new(n + 1, 1 + n % 3, 10 + n % 3, "fp#{n}", rng.rand < 0.3 ? [ "c" ] : []) }
      seen = Set.new
      last = {}
      serve = 0
      credit = Hash.new(0)
      pool.size.times do
        pick = Practice::Selector.choose(pool: pool, student_id: 4, seen: seen, last_serve: last, item_last_serve: {}, credit_by_item: credit)
        assert_equal "next", pick.reason, "seed #{i}"
        assert_not_includes seen, pick.candidate.fingerprint, "seed #{i}"
        again = Practice::Selector.choose(pool: pool, student_id: 4, seen: seen, last_serve: last, item_last_serve: {}, credit_by_item: credit)
        assert_equal pick, again, "seed #{i}"
        serve += 1
        seen << pick.candidate.fingerprint
        last[pick.candidate.fingerprint] = serve
        credit[pick.candidate.item_id] += 1 if rng.rand < 0.5
      end
      pick = Practice::Selector.choose(pool: pool, student_id: 4, seen: seen, last_serve: last, item_last_serve: {}, credit_by_item: credit)
      assert_equal "reseen", pick.reason, "seed #{i}"
      assert_equal last.min_by { |_, v| v }.last, last[pick.candidate.fingerprint], "seed #{i}: the oldest is re-seen"
    end
  end
end
