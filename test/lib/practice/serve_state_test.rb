require "test_helper"
require_relative "../../support/practice_engine_helper"

# The serve state machine of practice/3 (A8.3): every row of the table, every (state, event) pair
# that is not in it, and the bound of three stored tries.
class PracticeServeStateTest < ActiveSupport::TestCase
  include PracticeEngineHelper

  def play(*outcomes, hints_total: 3)
    PracticeEngineHelper::Play.new(hints_total: hints_total).tap { |p| outcomes.each { |o| p.answer(o) } }
  end

  test "row 1: a correct answer closes the serve, sends the solution, offers next and back" do
    p = PracticeEngineHelper::Play.new
    step = p.answer(:correct)
    assert_equal [ :accept, :correct, "after_correct" ], [ step.result, step.closes_as, step.solution_reason ]
    st = p.status
    assert_equal [ :closed, :correct, true, nil, %i[next back] ], [ st.state, st.closed_by, st.solution_sent, st.next_try_number, st.actions ]
  end

  test "row 2: a typical error closes the serve at once without the solution" do
    p = PracticeEngineHelper::Play.new
    step = p.answer(:typical_error)
    assert_equal [ :accept, :wrong, nil, false ], [ step.result, step.closes_as, step.solution_reason, step.auto_hint ]
    st = p.status
    assert_equal [ :closed, :wrong, false, %i[prova_questo show_solution back contest] ], [ st.state, st.closed_by, st.solution_sent, st.actions ]
  end

  test "row 3: an unrecognised answer opens the second try with the next unseen hint" do
    p = PracticeEngineHelper::Play.new
    step = p.answer(:unrecognised)
    assert_equal [ :accept, nil, nil, true, 1 ], [ step.result, step.closes_as, step.solution_reason, step.auto_hint, step.hint_n ]
    st = p.status
    assert_equal [ :open, 1, 1, 2, %i[retry show_solution contest] ], [ st.state, st.w, st.hints_shown, st.next_try_number, st.actions ]
  end

  test "row 3: with no hint left, no hint is sent" do
    p = PracticeEngineHelper::Play.new(hints_total: 1)
    p.hint(1)
    step = p.answer(:unrecognised)
    assert_not step.auto_hint
    assert_nil step.hint_n
    assert_equal 1, p.status.hints_shown
  end

  test "row 4: a wrong form opens the second try without a hint" do
    p = PracticeEngineHelper::Play.new
    step = p.answer(:form)
    assert_equal [ :accept, false ], [ step.result, step.auto_hint ]
    st = p.status
    assert_equal [ :open, 1, 0, %i[retry show_solution contest] ], [ st.state, st.w, st.hints_shown, st.actions ]
  end

  test "row 5: a correct second try closes the serve (aided by rule)" do
    p = play(:unrecognised)
    step = p.answer(:correct)
    assert_equal [ :accept, :correct, "after_correct" ], [ step.result, step.closes_as, step.solution_reason ]
    st = p.status
    assert_equal [ :closed, :correct, %i[next back] ], [ st.state, st.closed_by, st.actions ]
    assert_equal :correct_aided, p.outcomes.last
  end

  test "row 6: a second wrong answer closes the serve and sends the solution" do
    { typical_error: %i[prova_questo after_solution back contest], unrecognised: %i[after_solution back contest], form: %i[after_solution back contest] }.each do |outcome, actions|
      p = play(:unrecognised)
      step = p.answer(outcome)
      assert_equal [ :accept, :wrong, "after_last_try" ], [ step.result, step.closes_as, step.solution_reason ], outcome.to_s
      st = p.status
      assert_equal [ :closed, :wrong, true, actions ], [ st.state, st.closed_by, st.solution_sent, st.actions ], outcome.to_s
    end
    p = play(:form)
    p.answer(:typical_error)
    assert_equal %i[prova_questo after_solution back contest], p.status.actions
  end

  test "row 7: a first near miss keeps the serve open and the aid unchanged" do
    p = PracticeEngineHelper::Play.new
    step = p.answer(:near_miss)
    assert_equal [ :accept, nil, nil ], [ step.result, step.closes_as, step.solution_reason ]
    st = p.status
    assert_equal [ :open, 0, 1, 2, %i[retry contest] ], [ st.state, st.w, st.near_misses, st.next_try_number, st.actions ]
    assert_not Practice::ServeState.aided?(reason: "next", w: st.w, hints_shown: st.hints_shown)
  end

  test "row 8: a second near miss closes the serve and sends the solution" do
    p = play(:near_miss)
    step = p.answer(:near_miss)
    assert_equal [ :accept, :near_miss, "after_last_try" ], [ step.result, step.closes_as, step.solution_reason ]
    st = p.status
    assert_equal [ :closed, :near_miss, %i[after_solution next back contest] ], [ st.state, st.closed_by, st.actions ]
  end

  test "row 9: undetermined closes the serve and sends the solution" do
    p = PracticeEngineHelper::Play.new
    step = p.answer(:undetermined)
    assert_equal [ :accept, :undetermined, "after_undetermined" ], [ step.result, step.closes_as, step.solution_reason ]
    assert_equal [ :closed, %i[next back] ], [ p.status.state, p.status.actions ]
    p2 = play(:near_miss)
    p2.answer(:undetermined)
    assert_equal :undetermined, p2.status.closed_by
  end

  test "row 10: an invalid answer is not a try" do
    p = play(:unrecognised)
    before = p.status
    assert_equal :noop, p.answer(:invalid).result
    assert_equal before, p.status
  end

  test "row 11: a hint is written when n is shown + 1 and within the total" do
    p = PracticeEngineHelper::Play.new
    assert_equal :accept, p.hint(1).result
    assert_equal [ 1, 1 ], [ p.status.hints_shown, p.status.next_try_number ]
    assert_equal :accept, p.hint(2).result
    assert_equal :accept, p.hint(3).result
    assert_equal :bad_hint, p.hint(4).result
    assert_equal 3, p.status.hints_shown
  end

  test "row 11: later tries are aided after a hint" do
    p = PracticeEngineHelper::Play.new
    p.hint(1)
    assert Practice::ServeState.aided?(reason: "next", w: 0, hints_shown: p.status.hints_shown)
  end

  test "row 11: a hint that skips one, or n below 1 or not a number, is refused; one already shown is returned again" do
    p = PracticeEngineHelper::Play.new
    assert_equal :bad_hint, p.hint(2).result
    assert_equal :bad_hint, p.hint(0).result
    assert_equal :bad_hint, p.hint("1").result
    assert_equal :bad_hint, p.hint(nil).result
    p.hint(1)
    step = p.hint(1)
    assert_equal [ :noop, 1 ], [ step.result, step.hint_n ]
    assert_equal 1, p.status.hints_shown
  end

  test "row 12: asking for the solution closes an open serve" do
    p = PracticeEngineHelper::Play.new
    step = p.solution
    assert_equal [ :accept, :solution, "requested" ], [ step.result, step.closes_as, step.solution_reason ]
    st = p.status
    assert_equal [ :closed, :solution, true, %i[after_solution back] ], [ st.state, st.closed_by, st.solution_sent, st.actions ]
    p2 = play(:unrecognised)
    p2.solution
    assert_equal :solution, p2.status.closed_by
  end

  test "row 13: the solution after a typical error is sent without a new try" do
    p = play(:typical_error)
    step = p.solution
    assert_equal [ :accept, nil, "after_wrong" ], [ step.result, step.closes_as, step.solution_reason ]
    st = p.status
    assert_equal [ :closed, :wrong, true, %i[after_solution back contest] ], [ st.state, st.closed_by, st.solution_sent, st.actions ]
  end

  test "row 14: the solution again is returned without an event" do
    [ [ :correct ], [ :typical_error ], [ :undetermined ], [ :near_miss, :near_miss ], [ :unrecognised, :unrecognised ] ].each do |outcomes|
      p = play(*outcomes)
      p.solution if p.status.solution_sent == false
      count = p.events.size
      before = p.status
      assert_equal :noop, p.solution.result, outcomes.inspect
      assert_equal count, p.events.size
      assert_equal before, p.status
    end
    p = play(:correct)
    p.solution
    p.solution
    assert_equal 1, p.events.count { |e| e.kind == "solution_shown" }
    q = PracticeEngineHelper::Play.new
    q.solution
    assert_equal :noop, q.solution.result
  end

  test "row 15: a closed serve refuses answers and hints with 409" do
    [ [ :correct ], [ :typical_error ], [ :near_miss, :near_miss ], [ :undetermined ], [ :unrecognised, :form ] ].each do |outcomes|
      p = play(*outcomes)
      assert_equal :closed, p.answer(:correct).result
      assert_equal :closed, p.answer(:invalid).result
      assert_equal :closed, p.hint(1).result
    end
  end

  test "row 15: an open serve older than 14 days (336 hours) is abandoned and refuses everything" do
    window = Practice::Rules::V6::OPEN_SERVE_HOURS * 3600
    assert_equal 14 * 24 * 3600, window
    old = serve_status([], now: T0 + window + 1)
    assert_equal [ :abandoned, nil, [] ], [ old.state, old.closed_by, old.actions ]
    assert_equal :open, serve_status([], now: T0 + window).state
    assert_equal :open, serve_status([], now: T0 + 25 * 3600).state, "a day-old serve is still open"
    %i[correct unrecognised].each { |o| assert_equal :closed, Practice::ServeState.step(old, :answer, outcome: o, hints_total: 3).result }
    assert_equal :closed, Practice::ServeState.step(old, :hint, hint_n: 1, hints_total: 3).result
    assert_equal :closed, Practice::ServeState.step(old, :solution_request).result
  end

  test "row 15: a serve superseded by a newer serve of the item is abandoned at any age, and refuses everything" do
    fresh = serve_status([], now: T0 + 60, superseded: true)
    assert_equal [ :abandoned, nil, [] ], [ fresh.state, fresh.closed_by, fresh.actions ]
    assert_nil fresh.next_try_number
    assert_equal :open, serve_status([], now: T0 + 60, superseded: false).state
    %i[correct unrecognised].each { |o| assert_equal :closed, Practice::ServeState.step(fresh, :answer, outcome: o, hints_total: 3).result }
    assert_equal :closed, Practice::ServeState.step(fresh, :hint, hint_n: 1, hints_total: 3).result
    assert_equal :closed, Practice::ServeState.step(fresh, :solution_request).result
  end

  test "D-377: an open serve whose topic revision was replaced is replaced at any age, keeps its tries and refuses everything" do
    fresh = serve_status([ :unrecognised ], now: T0 + 60, replaced: true)
    assert_equal [ :replaced, nil, [], nil, 1 ], [ fresh.state, fresh.closed_by, fresh.actions, fresh.next_try_number, fresh.w ]
    assert_equal :replaced, serve_status([], now: T0 + 60, replaced: true, superseded: true).state, "replaced wins over superseded"
    assert_equal :replaced, serve_status([], now: T0 + 15 * 24 * 3600, replaced: true).state, "and over age"
    assert_equal :open, serve_status([ :unrecognised ], now: T0 + 60, replaced: false).state
    %i[correct unrecognised].each { |o| assert_equal :closed, Practice::ServeState.step(fresh, :answer, outcome: o, hints_total: 3).result }
    assert_equal :closed, Practice::ServeState.step(fresh, :hint, hint_n: 1, hints_total: 3).result
    assert_equal :closed, Practice::ServeState.step(fresh, :solution_request).result
    assert_equal :closed, Practice::ServeState.step(fresh, :contest).result
  end

  test "D-377: a closed serve stays closed when its topic revision was replaced" do
    st = serve_status([ :correct ], now: T0 + 60, replaced: true)
    assert_equal [ :closed, :correct, %i[next back] ], [ st.state, st.closed_by, st.actions ]
    st = serve_status([ :typical_error ], now: T0 + 60, replaced: true)
    assert_equal [ :closed, :wrong ], [ st.state, st.closed_by ]
  end

  test "a closed serve is closed, not abandoned, even when superseded" do
    st = serve_status([ :correct ], now: T0 + 60, superseded: true)
    assert_equal [ :closed, :correct ], [ st.state, st.closed_by ]
  end

  test "a closed serve stays closed whatever the clock says" do
    assert_equal :closed, serve_status([ :correct ], now: T0 + 90 * 3600).state
  end

  test "a fresh open serve" do
    st = serve_status
    assert_equal [ :open, 1, 0, %i[show_solution] ], [ st.state, st.next_try_number, st.hints_shown, st.actions ]
  end

  test "every combination of states and events is either in the table or refused" do
    # closed serves: only the solution request has a row (13, 14); answer and hint are row 15.
    closed = [ %i[correct], %i[typical_error], %i[near_miss near_miss], %i[undetermined], %i[unrecognised form] ].map { |o| play(*o) }
    closed.each do |p|
      %i[correct typical_error unrecognised form near_miss undetermined].each { |o| assert_equal :closed, Practice::ServeState.step(p.status, :answer, outcome: o, hints_total: 3).result }
      assert_equal :closed, Practice::ServeState.step(p.status, :hint, hint_n: 1, hints_total: 3).result
    end
    # a closed serve whose solution was not sent and not wrong cannot exist; the only unsent one is row 2
    assert_equal :accept, Practice::ServeState.step(play(:typical_error).status, :solution_request).result
    # unknown events and outcomes are errors, not silence
    assert_raises(ArgumentError) { Practice::ServeState.step(serve_status, :skip) }
    assert_raises(ArgumentError) { Practice::ServeState.step(serve_status, :answer, outcome: :maybe) }
  end

  test "at most three tries are stored, whatever the order of outcomes" do
    outcomes = %i[correct typical_error unrecognised form near_miss undetermined]
    longest = 0
    walk = lambda do |p, depth|
      longest = [ longest, p.outcomes.size ].max
      assert_operator p.outcomes.size, :<=, Practice::Rules::V6::MAX_TRIES
      next if p.status.state != :open

      outcomes.each do |o|
        q = PracticeEngineHelper::Play.new
        p.outcomes.each { |x| q.answer(x) }
        q.answer(o)
        walk.(q, depth + 1)
      end
    end
    walk.(PracticeEngineHelper::Play.new, 0)
    assert_equal 3, longest
  end

  test "the derived closure equals what each step announced" do
    outcomes = %i[correct typical_error unrecognised form near_miss undetermined]
    outcomes.product(outcomes, outcomes).each do |seq|
      p = PracticeEngineHelper::Play.new
      seq.each do |o|
        was_open = p.status.state == :open
        step = p.answer(o)
        next unless was_open

        assert_equal step.closes_as.to_s, p.status.closed_by.to_s, "#{seq.inspect} at #{o}"
      end
    end
  end

  test "the actions of every closed state are consistent with the follow rules" do
    # prova_questo only after a typical error; after_solution only when the solution was sent
    outcomes = %i[correct typical_error unrecognised form near_miss undetermined]
    outcomes.product(outcomes, outcomes).each do |seq|
      p = PracticeEngineHelper::Play.new
      seq.each { |o| p.answer(o) }
      st = p.status
      assert st.solution_sent if st.actions.include?(:after_solution)
      next unless st.actions.include?(:prova_questo)

      assert(p.outcomes.include?(:typical_error), seq.inspect)
    end
  end

  # ---- practice/3: contest («Per me va bene così», D-389) ----

  test "row 16: a contest on an open serve after an unrecognised or form try closes it contested and sends the solution" do
    %i[unrecognised form].each do |outcome|
      p = play(outcome)
      assert_includes p.status.actions, :contest, outcome.to_s
      step = p.contest
      assert_equal [ :accept, :contested, "after_contest" ], [ step.result, step.closes_as, step.solution_reason ], outcome.to_s
      st = p.status
      assert_equal [ :closed, :contested, true, nil, %i[next back], 0 ], [ st.state, st.closed_by, st.solution_sent, st.next_try_number, st.actions, st.w ], outcome.to_s
      assert_equal [ :contested ], p.outcomes
    end
  end

  test "row 17: a contest on a serve closed wrong after the second try; the solution is not sent twice" do
    %i[unrecognised form].each do |second|
      p = play(:unrecognised, second)
      assert_equal [ :closed, :wrong, true ], [ p.status.state, p.status.closed_by, p.status.solution_sent ]
      assert_includes p.status.actions, :contest, second.to_s
      step = p.contest
      assert_equal [ :accept, :contested, nil ], [ step.result, step.closes_as, step.solution_reason ], second.to_s
      st = p.status
      assert_equal [ :closed, :contested, true, %i[next back], 1 ], [ st.state, st.closed_by, st.solution_sent, st.actions, st.w ], second.to_s
      assert_equal %i[unrecognised contested], p.outcomes
      assert_equal 1, p.events.count { |e| e.kind == "solution_shown" }
    end
  end

  test "D-389, row 16: a contest on an open serve after a near miss closes it contested and sends the solution" do
    p = play(:near_miss)
    assert_equal [ :open, %i[retry contest] ], [ p.status.state, p.status.actions ]
    step = p.contest
    assert_equal [ :accept, :contested, "after_contest" ], [ step.result, step.closes_as, step.solution_reason ]
    st = p.status
    assert_equal [ :closed, :contested, true, %i[next back], 0, 0 ], [ st.state, st.closed_by, st.solution_sent, st.actions, st.w, st.near_misses ]
    assert_equal [ :contested ], p.outcomes
  end

  test "D-389, row 17: a contest on a serve closed after a typical error or a second near miss" do
    typical = play(:typical_error)
    assert_equal [ :closed, :wrong, false ], [ typical.status.state, typical.status.closed_by, typical.status.solution_sent ]
    step = typical.contest
    assert_equal [ :accept, :contested, "after_contest" ], [ step.result, step.closes_as, step.solution_reason ]
    assert_equal [ :closed, :contested, true, %i[next back] ], [ typical.status.state, typical.status.closed_by, typical.status.solution_sent, typical.status.actions ]

    twice = play(:near_miss, :near_miss)
    assert_equal [ :closed, :near_miss, true ], [ twice.status.state, twice.status.closed_by, twice.status.solution_sent ]
    assert_includes twice.status.actions, :contest
    step = twice.contest
    assert_equal [ :accept, :contested, nil ], [ step.result, step.closes_as, step.solution_reason ]
    assert_equal [ :closed, :contested, %i[next back] ], [ twice.status.state, twice.status.closed_by, twice.status.actions ]
    assert_equal [ :near_miss, :contested ], twice.outcomes
    assert_equal 1, twice.events.count { |e| e.kind == "solution_shown" }
  end

  test "a contest is not allowed without a try, on a correct, an undetermined or a contested try" do
    [ [ :correct ], [ :unrecognised, :correct ], [ :undetermined ], [ :near_miss, :undetermined ] ].each do |outcomes|
      p = play(*outcomes)
      assert_not_includes p.status.actions, :contest, outcomes.inspect
      assert_equal :closed, p.contest.result, outcomes.inspect
    end
    assert_equal :open, play(:near_miss).status.state
    assert_equal :closed, PracticeEngineHelper::Play.new.contest.result # no try yet
    assert_not_includes PracticeEngineHelper::Play.new.status.actions, :contest
    contested = play(:near_miss)
    contested.contest
    assert_not_includes contested.status.actions, :contest
  end

  test "a contest is for the LATEST try only: after a near miss then an unrecognised one it is allowed on the unrecognised one" do
    p = play(:near_miss, :unrecognised)
    assert_equal [ :open, %i[retry show_solution contest] ], [ p.status.state, p.status.actions ]
    assert_equal :accept, p.contest.result
    assert_equal :contested, p.status.closed_by
  end

  test "D-395, row 16: a contest is allowed on the latest try after the solution was asked for on an open serve; the solution is not sent twice" do
    %i[unrecognised form near_miss].each do |outcome|
      p = play(outcome)
      p.solution
      assert_equal [ :closed, :solution, %i[after_solution back contest] ], [ p.status.state, p.status.closed_by, p.status.actions ], outcome.to_s
      step = p.contest
      assert_equal [ :accept, :contested, nil ], [ step.result, step.closes_as, step.solution_reason ], outcome.to_s
      assert_equal [ :closed, :contested, %i[next back] ], [ p.status.state, p.status.closed_by, p.status.actions ], outcome.to_s
      assert_equal 1, p.events.count { |e| e.kind == "solution_shown" }, outcome.to_s
    end
  end

  test "a contest is not allowed on a solution asked for with no try, nor on an abandoned or a superseded serve" do
    p = PracticeEngineHelper::Play.new
    p.solution
    assert_equal [ :closed, :solution, %i[after_solution back] ], [ p.status.state, p.status.closed_by, p.status.actions ]
    assert_equal :closed, p.contest.result
    abandoned = serve_status([ :unrecognised ], now: T0 + 15 * 24 * 3600)
    assert_equal [ :abandoned, [] ], [ abandoned.state, abandoned.actions ]
    superseded = serve_status([ :unrecognised ], superseded: true)
    assert_equal [ :abandoned, [] ], [ superseded.state, superseded.actions ]
  end

  test "row 18: a second contest on a contested serve is a noop; it never changes the state again" do
    p = play(:unrecognised)
    p.contest
    before = p.status
    step = p.contest
    assert_equal [ :noop, nil, nil ], [ step.result, step.closes_as, step.solution_reason ]
    assert_equal before, p.status
    assert_not_includes before.actions, :contest
  end

  test "the solution after a contest is a noop: it was sent with the contest" do
    p = play(:unrecognised)
    p.contest
    assert_equal :noop, p.solution.result
    assert_equal 1, p.events.count { |e| e.kind == "solution_shown" }
  end

  test "a contested try closes the serve whatever its stored outcome says: the contested flag is enough" do
    tries = [ Practice::ServeTry.new(1, :unrecognised), Practice::ServeTry.new(2, :form, true) ]
    st = Practice::ServeState.call(serve: stub_serve, tries: tries, events: [ serve_event("solution_shown", reason: "after_contest") ], hints_total: 3, now: T0 + 60)
    assert_equal [ :closed, :contested, 1, %i[next back] ], [ st.state, st.closed_by, st.w, st.actions ]
    assert_equal false, Practice::ServeTry.new(1, :correct).contested
  end

  test "contested is never the outcome of an answer" do
    assert_raises(ArgumentError) { Practice::ServeState.step(serve_status, :answer, outcome: :contested) }
    assert_includes Practice::Outcome::OUTCOMES, :contested
  end

  test "a closed contested serve refuses answers and hints with closed, like any closed serve" do
    p = play(:unrecognised)
    p.contest
    %i[correct unrecognised near_miss].each { |o| assert_equal :closed, Practice::ServeState.step(p.status, :answer, outcome: o, hints_total: 3).result }
    assert_equal :closed, Practice::ServeState.step(p.status, :hint, hint_n: 1, hints_total: 3).result
  end

  test "the actions say contest exactly when a contest is allowed, over every sequence of three outcomes, with and without the solution request" do
    outcomes = %i[correct typical_error unrecognised form near_miss undetermined]
    [ false, true ].each do |ask|
      outcomes.product(outcomes, outcomes).each do |seq|
        p = PracticeEngineHelper::Play.new
        seq.each { |o| p.answer(o) }
        p.solution if ask
        st = p.status
        allowed = p.outcomes.any? && %i[typical_error unrecognised form near_miss].include?(p.outcomes.last) &&
                  (st.state == :open || (st.state == :closed && %i[wrong near_miss solution].include?(st.closed_by)))
        assert_equal allowed, st.actions.include?(:contest), [ seq, ask ].inspect
        assert_equal allowed ? :accept : :closed, Practice::ServeState.step(st, :contest).result, [ seq, ask ].inspect
      end
    end
  end
end
