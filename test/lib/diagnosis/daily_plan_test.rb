require "test_helper"

# B-12 and the operator's days decision: dependency gating and the daily caps.
class DiagnosisDailyPlanTest < ActiveSupport::TestCase
  Plan = Diagnosis::DailyPlan
  TODAY = Date.new(2026, 11, 2)

  def subject(key, depends_on: [], status: "not_started", closed: 0, dates: [], seconds: {})
    Plan::Subject.new(key: key, depends_on: depends_on, status: status, sittings_closed: closed,
                      sitting_dates: dates, counted_seconds_by_date: seconds)
  end

  def states(subjects) = Plan.availability(subjects, TODAY).transform_values { |v| v[:state] }

  test "a subject waits for the first sitting of each dependency to be closed" do
    subjects = [ subject("math"), subject("chemistry", depends_on: %w[math]), subject("biology", depends_on: %w[chemistry]) ]
    s = Plan.availability(subjects, TODAY)
    assert_equal :to_do, s["math"][:state]
    assert_equal :after_dependency, s["chemistry"][:state]
    assert_equal %w[math], s["chemistry"][:waiting_for]
    assert_equal :after_dependency, s["biology"][:state]
  end

  test "once the first sitting of math is closed, its dependants are open" do
    subjects = [ subject("math", status: "continue_next_day", closed: 1, dates: [ TODAY - 1 ]),
                 subject("chemistry", depends_on: %w[math]) ]
    assert_equal :to_do, states(subjects)["chemistry"]
  end

  test "at most two subjects a day: a third waits for tomorrow" do
    subjects = [ subject("math", status: "in_progress", dates: [ TODAY ], seconds: { TODAY => 1500 }),
                 subject("english", status: "in_progress", dates: [ TODAY ], seconds: { TODAY => 1000 }),
                 subject("italian") ]
    s = states(subjects)
    assert_equal :tomorrow, s["italian"]
    assert_equal :to_do, s["math"] # the sitting in progress goes on
  end

  test "a subject whose sitting ended today continues tomorrow" do
    subjects = [ subject("math", status: "continue_next_day", closed: 1, dates: [ TODAY ], seconds: { TODAY => 1800 }) ]
    assert_equal :continue_next_day, states(subjects)["math"]
  end

  test "75 counted minutes a day is a ceiling that closes the day for new subjects" do
    subjects = [ subject("math", status: "completed", closed: 2, dates: [ TODAY ], seconds: { TODAY => 76 * 60 }),
                 subject("english") ]
    assert_equal :tomorrow, states(subjects)["english"]
  end

  test "two first sittings fit under the ceiling: 30 + 25 counted minutes leave the day open for the next one only by the two-subject cap" do
    subjects = [ subject("math", status: "continue_next_day", closed: 1, dates: [ TODAY ], seconds: { TODAY => 1800 }),
                 subject("english", status: "continue_next_day", closed: 1, dates: [ TODAY ], seconds: { TODAY => 1500 }),
                 subject("italian") ]
    assert_equal :tomorrow, states(subjects)["italian"]
  end

  test "completed subjects are done" do
    assert_equal :done, states([ subject("math", status: "completed", closed: 1) ])["math"]
  end

  test "subjects come in dependency order, mathematics first" do
    subjects = [ subject("biology", depends_on: %w[chemistry]), subject("chemistry", depends_on: %w[math]),
                 subject("geography", depends_on: %w[math]), subject("math"), subject("english"), subject("italian") ]
    order = Plan.ordered(subjects).map(&:key)
    assert_equal "math", order.first
    assert_operator order.index("chemistry"), :<, order.index("biology")
    assert_operator order.index("english"), :<, order.index("italian")
  end
end
