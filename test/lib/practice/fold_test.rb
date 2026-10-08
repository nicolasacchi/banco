require "test_helper"
require_relative "../../support/practice_engine_helper"

# The skill states of practice/1 (A8.5, A8.6): an exhaustive table of short histories.
class PracticeFoldTest < ActiveSupport::TestCase
  include PracticeEngineHelper

  test "no tries and no seed is not_seen" do
    assert_equal "not_seen", state_of([])
    assert_equal :not_seen, fold([]).why[:code]
  end

  test "any try moves not_seen, to_recover and to_learn to in_study" do
    %w[not_seen to_recover to_learn].each do |from|
      %i[correct typical_error unrecognised near_miss undetermined correct_aided].each do |outcome|
        seed = from == "not_seen" ? nil : seed_of(from)
        assert_equal "in_study", state_of([ try_at(outcome: outcome) ], seed: seed), "#{from} + #{outcome}"
      end
    end
  end

  test "three correct unaided answers on one day stay in_study" do
    tries = [ try_at(hours: 0), try_at(hours: 1), try_at(hours: 2) ]
    s = fold(tries)
    assert_equal "in_study", s.state
    assert_equal({ code: :in_study, n: 3, d: 1 }, s.why)
  end

  test "three on two days with two low-guess fingerprints are demonstrated, at the third try" do
    tries = demonstrating_tries
    s = fold(tries)
    assert_equal "demonstrated", s.state
    assert_equal tries.last.at, s.demonstrated_at
    assert_equal :demonstrated, s.why[:code]
    assert_equal 2, s.why[:days]
  end

  test "choice-only answers (no low-guess fingerprint) are never enough" do
    tries = [ try_at(low: false), try_at(day: 1, low: false), try_at(day: 2, low: false), try_at(day: 3, low: true) ]
    assert_equal "in_study", state_of(tries)
    assert_equal "demonstrated", state_of(tries + [ try_at(day: 4, low: true) ])
  end

  test "only distinct fingerprints count" do
    tries = [ try_at(fp: "a"), try_at(day: 1, fp: "a", serve: 90), try_at(day: 2, fp: "a", serve: 91), try_at(day: 3, fp: "b") ]
    assert_equal "in_study", state_of(tries)
  end

  test "an aided or re-seen correct answer never counts" do
    tries = [ try_at(low: true), try_at(day: 1, low: true, aided: true, outcome: :correct_aided), try_at(day: 2, reseen: true), try_at(day: 3, low: true) ]
    assert_equal "in_study", state_of(tries)
  end

  test "a wrong try in study changes nothing; the later corrects still count" do
    tries = [ try_at(outcome: :typical_error, codes: [ "slip" ]), *demonstrating_tries(start_day: 0) ]
    assert_equal "demonstrated", state_of(tries)
  end

  test "near misses and undetermined tries are tries but neither credit nor wrong" do
    s = fold([ try_at(outcome: :near_miss), try_at(outcome: :undetermined) ])
    assert_equal "in_study", s.state
    assert_equal 0, s.counts[:wrong]
    assert_equal({ near_miss: 1, undetermined: 1 }, s.counts.slice(:near_miss, :undetermined))
  end

  test "the days are Rome calendar days: 2026-10-25 has 25 hours" do
    # 22:30 UTC on 24 Oct is 00:30 Rome on the 25th; 00:30 UTC on 25 Oct is 02:30 Rome (still CEST until 03:00).
    a = try_at(at: Time.utc(2026, 10, 24, 22, 30))
    b = try_at(at: Time.utc(2026, 10, 25, 0, 30))
    assert_equal a.day, b.day
    # 23:30 UTC on the 25th is 00:30 Rome on the 26th: a different day (CET).
    c = try_at(at: Time.utc(2026, 10, 25, 23, 30))
    assert_equal Date.new(2026, 10, 26), c.day
    assert_equal Date.new(2026, 10, 25), b.day
    # 00:30 UTC on the 25th and 23:30 UTC on the 25th are two days, so two correct tries there plus a third demonstrate.
    d = try_at(at: Time.utc(2026, 10, 25, 12, 0), low: true)
    assert_equal "demonstrated", state_of([ b.with(low_guess: true), d, c.with(low_guess: false) ])
    assert_equal "in_study", state_of([ b.with(low_guess: true), d.with(fingerprint: "x"), try_at(at: Time.utc(2026, 10, 25, 20, 0), low: false) ])
  end

  test "demonstrated consolidates at a correct unaided try on a fresh fingerprint 14 days later" do
    base = demonstrating_tries
    due = base.last.at + 14 * 86_400
    early = try_at(at: due - 60, serve: 500)
    assert_equal "demonstrated", state_of(base + [ early ])
    s = fold(base + [ try_at(at: due, serve: 501) ])
    assert_equal "consolidated", s.state
    assert_equal due, s.consolidated_at
  end

  test "a re-seen or aided try never consolidates" do
    base = demonstrating_tries
    due = base.last.at + 20 * 86_400
    assert_equal "demonstrated", state_of(base + [ try_at(at: due, reseen: true) ])
    assert_equal "demonstrated", state_of(base + [ try_at(at: due, aided: true, outcome: :correct_aided) ])
  end

  test "a wrong unaided try after demonstrated or consolidated goes to to_review and remembers" do
    base = demonstrating_tries
    s = fold(base + [ try_at(day: 5, outcome: :unrecognised) ])
    assert_equal "to_review", s.state
    assert_equal :demonstrated, s.why[:previous].to_sym
    cons = base + [ try_at(at: base.last.at + 15 * 86_400, serve: 600) ]
    s2 = fold(cons + [ try_at(at: base.last.at + 16 * 86_400, outcome: :typical_error, codes: [ "c" ]) ])
    assert_equal "to_review", s2.state
    assert_equal "consolidated", s2.why[:previous].to_s
  end

  test "a wrong aided try after demonstrated changes nothing" do
    base = demonstrating_tries
    assert_equal "demonstrated", state_of(base + [ try_at(day: 5, outcome: :unrecognised, aided: true) ])
    assert_equal "demonstrated", state_of(base + [ try_at(day: 5, outcome: :unrecognised, reseen: true) ])
  end

  test "two correct unaided answers on distinct fingerprints bring to_review back" do
    base = demonstrating_tries + [ try_at(day: 5, outcome: :typical_error, codes: [ "c" ]) ]
    assert_equal "to_review", state_of(base)
    assert_equal "to_review", state_of(base + [ try_at(day: 6) ])
    assert_equal "to_review", state_of(base + [ try_at(day: 6, fp: "same"), try_at(day: 7, fp: "same", serve: 700) ])
    assert_equal "demonstrated", state_of(base + [ try_at(day: 6), try_at(day: 7) ])
    assert_equal "to_review", state_of(base + [ try_at(day: 6), try_at(day: 7, aided: true, outcome: :correct_aided) ])
  end

  test "the correct tries made before the review do not count towards leaving it" do
    base = demonstrating_tries + [ try_at(day: 5, outcome: :typical_error, codes: [ "c" ]) ]
    assert_equal "to_review", state_of(base)
  end

  test "diagnosis seeds" do
    assert_equal "demonstrated", state_of([], seed: seed_of("demonstrated"))
    assert_equal :seed_demonstrated, fold([], seed: seed_of("demonstrated")).why[:code]
    assert_equal :seed_implied, fold([], seed: seed_of("demonstrated", implied: true)).why[:code]
    assert_equal :seed_to_recover, fold([], seed: seed_of("to_recover")).why[:code]
    assert_equal :seed_to_learn, fold([], seed: seed_of("to_learn")).why[:code]
  end

  test "a seeded demonstrated consolidates 14 days after the diagnosis, and goes to review on a wrong unaided try" do
    seed = seed_of("demonstrated", at: T0 - 20 * 86_400)
    assert_equal "consolidated", state_of([ try_at ], seed: seed)
    assert_equal "to_review", state_of([ try_at(outcome: :unrecognised) ], seed: seed)
    young = seed_of("demonstrated", at: T0 - 5 * 86_400)
    assert_equal "demonstrated", state_of([ try_at ], seed: young)
  end

  test "a seeded demonstrated that never leaves keeps the seed as its reason" do
    s = fold([ try_at(aided: true, outcome: :correct_aided) ], seed: seed_of("demonstrated"))
    assert_equal :seed_demonstrated, s.why[:code]
  end

  test "counts" do
    serves = [ Struct.new(:id, :skill, :fingerprint, :hints_shown, :solution_requested, :status).new(
      9, SKILL, "z", 2, true, Practice::ServeState::Status.new(state: :abandoned, closed_by: nil, w: 0, near_misses: 0, hints_shown: 2,
                                                              solution_sent: false, next_try_number: 1, actions: [])) ]
    tries = [ try_at(serve: 1, seconds: 20), try_at(serve: 2, outcome: :typical_error, codes: [ "c1" ], seconds: 5000),
              try_at(serve: 3, outcome: :correct_aided, aided: true), try_at(serve: 4, outcome: :unrecognised, try_number: 1) ]
    c = fold(tries, serves: serves).counts
    assert_equal 5, c[:serves]
    assert_equal 4, c[:tries]
    assert_equal({ serves: 5, tries: 4, correct_unaided: 1, correct_aided: 1, wrong: 2, typical: { "c1" => 1 }, unrecognised: 1, near_miss: 0,
                   undetermined: 0, hints: 2, solutions_requested: 1, abandoned: 1, seconds: 20 + 600 + 30 + 30 }, c)
  end

  test "tries given out of order give the same states" do
    tries = demonstrating_tries + [ try_at(day: 5, outcome: :unrecognised) ]
    assert_equal fold(tries), fold(tries.reverse)
  end

  test "skills are folded apart" do
    out = Practice::Fold.call(seeds: {}, tries: [ try_at(skill: "math.a"), try_at(skill: "math.b", outcome: :near_miss) ])
    assert_equal %w[math.a math.b], out.keys.sort
  end
end
