# Builders for the pure practice engine: tries, seeds, serves, without a database.
module PracticeEngineHelper
  T0 = Time.utc(2026, 10, 12, 9, 0, 0)
  SKILL = "math.s".freeze

  # One try. day: days after T0 (also sets the Rome calendar date); fp names the instance.
  def try_at(day: 0, hours: 0, outcome: :correct, aided: false, low: true, fp: nil, serve: nil, try_number: 1, skill: SKILL, item_id: 1,
             revision: 1, codes: [], reseen: false, at: nil, seconds: 30)
    @engine_serial = (@engine_serial || 0) + 1
    at ||= T0 + day * 86_400 + hours * 3600
    Practice::Try.new(skill: skill, at: at, day: at.in_time_zone(Practice::Rules::V1::ZONE).to_date, serve_id: serve || @engine_serial,
                      fingerprint: fp || "fp#{@engine_serial}", item_id: item_id, item_revision_id: revision, low_guess: low,
                      try_number: try_number, aided: aided || reseen, reseen: reseen, evidence: Practice::Outcome.evidence(outcome),
                      outcome: outcome, error_codes: codes, seconds: seconds)
  end

  def seed_of(state, at: T0 - 86_400, skill: SKILL, implied: false)
    Practice::Seed.new(skill: skill, state: state, at: at, run_id: 1, implied: implied)
  end

  def fold(tries, seed: nil, skill: SKILL, serves: [])
    Practice::Fold.call(seeds: seed ? { skill => seed } : {}, tries: tries, serves: serves, skills: [ skill ]).fetch(skill)
  end

  def state_of(tries, seed: nil) = fold(tries, seed: seed).state

  # Three correct unaided answers on two days, two of them low guess: demonstrated on the third.
  def demonstrating_tries(start_day: 0)
    [ try_at(day: start_day, low: true), try_at(day: start_day, hours: 1, low: true), try_at(day: start_day + 1, low: false) ]
  end

  # A serve for the state machine tests.
  StubServe = Struct.new(:at, :reason)
  StubTry = Struct.new(:try_number, :outcome)

  def stub_serve(at: T0, reason: "next") = StubServe.new(at, reason)

  def serve_event(kind, n: nil, reason: nil, auto: false)
    Practice::ServeEvent.new(kind: kind, n: n, reason: reason, auto: auto, at: T0)
  end

  def serve_status(outcomes = [], events: [], hints_total: 3, now: T0 + 60, reason: "next")
    tries = outcomes.each_with_index.map { |o, i| StubTry.new(i + 1, o) }
    Practice::ServeState.call(serve: stub_serve(reason: reason), tries: tries, events: events, hints_total: hints_total, now: now)
  end

  # A serve being played: applies events the way the recorder does (writes what the step names),
  # so the derived status can be checked after each one.
  class Play
    include PracticeEngineHelper
    attr_reader :outcomes, :events, :hints_total, :steps

    def initialize(hints_total: 3, now: T0 + 60)
      @outcomes = []
      @events = []
      @hints_total = hints_total
      @now = now
      @steps = []
    end

    def status = serve_status(@outcomes, events: @events, hints_total: @hints_total, now: @now)

    def answer(outcome)
      st = status
      aided = Practice::ServeState.aided?(reason: "next", w: st.w, hints_shown: st.hints_shown)
      outcome = :correct_aided if outcome == :correct && aided
      step = Practice::ServeState.step(st, :answer, outcome: outcome, hints_total: @hints_total)
      @steps << step
      return step unless step.result == :accept

      @outcomes << outcome
      @events << serve_event("solution_shown", reason: step.solution_reason) if step.solution_reason
      @events << serve_event("hint_shown", n: step.hint_n, auto: true) if step.auto_hint
      step
    end

    def hint(n)
      step = Practice::ServeState.step(status, :hint, hint_n: n, hints_total: @hints_total)
      @events << serve_event("hint_shown", n: n) if step.result == :accept
      step
    end

    def solution
      step = Practice::ServeState.step(status, :solution_request)
      @events << serve_event("solution_shown", reason: step.solution_reason) if step.result == :accept
      step
    end
  end
end
