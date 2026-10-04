require "test_helper"
require_relative "../../support/diagnosis_helper"

# B-05: counted time, the budget between serves, abandon, sittings and the
# item cap, on a fake clock.
class DiagnosisTimeAccountTest < ActiveSupport::TestCase
  include DiagnosisHelper

  A = "math.a".freeze
  T0 = Diagnosis::FakeClock::START

  def flat_plan(count: 3, **opts)
    skills = (1..count).to_h { |i| [ "math.s#{i}", {} ] }
    build_plan(skills: skills, entries: skills.keys, **opts)
  end

  def counted(driver) = driver.result[:counted_seconds]

  test "TimeAccount.counted_seconds: the plain gap, the cap, a testlet cap" do
    assert_equal 90, Diagnosis::TimeAccount.counted_seconds(T0, T0 + 90, [])
    assert_equal 600, Diagnosis::TimeAccount.counted_seconds(T0, T0 + 5000, [])
    assert_equal 1200, Diagnosis::TimeAccount.counted_seconds(T0, T0 + 5000, [], testlet: true)
  end

  test "item_capped_at_600s" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    d.play("correct", seconds: 2000)
    assert_equal 600, counted(d)
  end

  test "paused_not_counted" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    d.clock.advance(60)
    d.push("paused")
    d.clock.advance(240)
    d.push("resumed")
    d.answer(s, "correct", seconds: 100)
    assert_equal 160, counted(d)
  end

  test "hidden_not_counted, and pause and hidden overlapping are subtracted once" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    d.clock.advance(30)
    d.push("hidden")
    d.clock.advance(60)
    d.push("paused") # overlaps the hidden interval from here
    d.clock.advance(60)
    d.push("visible")
    d.clock.advance(60)
    d.push("resumed")
    d.answer(s, "correct", seconds: 30)
    # 240 s between serve and answer; 30 s counted + hidden 120 + pause tail 60 minus overlap: union is 30..210 = 180
    assert_equal 30 + 30, counted(d)
  end

  test "a pause that is never closed runs to the answer" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    d.clock.advance(50)
    d.push("paused")
    d.answer(s, "correct", seconds: 400)
    assert_equal 50, counted(d)
  end

  test "a hidden or paused interval left open by a closed tab ends at the next serve" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    d.clock.advance(30)
    d.push("hidden")
    d.clock.advance(60)
    d.push("paused")
    d.answer(s, "wrong", seconds: 10) # the page was left like this; no visible, no resumed
    d.clock.advance(86_400)
    d.play("correct", seconds: 540)
    d.play("correct", seconds: 540)
    assert_equal 30 + 540 + 540, counted(d)
  end

  test "pause before the item does not count against it" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    d.push("paused")
    d.clock.advance(500)
    d.push("resumed")
    d.play("correct", seconds: 40)
    assert_equal 40, counted(d)
  end

  test "closes_at_item_boundary: the budget is checked between serves, the item in flight is never cut" do
    d = DiagnosisHelper::Driver.new(flat_plan(count: 10, minutes: 10))
    d.start
    # 10-minute budget: 5 items of 110 s leave 50 s, which is still time: the next item starts.
    5.times { d.play("correct", seconds: 110) }
    assert_equal 550, counted(d)
    assert_equal :serve, d.action.type
    d.play("correct", seconds: 400) # runs over the budget: allowed, it was in flight
    assert_equal 950, counted(d)
    a = d.action
    assert_equal :end_sitting, a.type
    assert_equal "time_budget", a.reason
  end

  test "nothing is served once the budget is reached" do
    d = DiagnosisHelper::Driver.new(flat_plan(count: 20, minutes: 10, sittings: 1))
    d.start
    served_after = 0
    loop do
      a = d.action
      break unless a.type == :serve

      served_after += 1 if counted(d) >= 600
      d.play("correct", seconds: 100)
    end
    assert_equal 0, served_after
    assert_equal :close_run, d.action.type
    assert_equal "time_budget", d.action.reason
  end

  test "an open item is waited for, then abandoned after 1800 s" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    assert_equal :wait, d.action.type
    d.clock.advance(Diagnosis::Rules::V1::ABANDON_GAP_SECONDS - 1)
    assert_equal :wait, d.action.type
    d.clock.advance(1)
    assert_equal :abandon_item, d.action.type
    assert_equal s[:seq], d.action.serve
  end

  test "abandon counts awake time: a hidden or paused hour is not counted toward the gap (D-073)" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    d.clock.advance(60)
    d.push("hidden")
    d.clock.advance(2 * 3600) # far beyond the gap on the wall clock
    assert_equal :wait, d.action.type, "an open hidden interval does not run the abandon clock"
    d.push("visible")
    d.clock.advance(60)
    d.push("paused")
    d.clock.advance(3600)
    d.push("resumed")
    assert_equal :wait, d.action.type
    d.clock.advance(Diagnosis::Rules::V1::ABANDON_GAP_SECONDS - 120 - 1)
    assert_equal :wait, d.action.type
    d.clock.advance(1)
    assert_equal :abandon_item, d.action.type
    assert_equal s[:seq], d.action.serve
  end

  test "abandon_after_1800s_serves_fresh_instance of the same skill, counted time capped" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    first_instance = s[:instance]
    d.clock.advance(1800)
    d.push("item_abandoned", serve: s[:seq])
    assert_equal 600, counted(d)
    a = d.action
    assert_equal :serve, a.type
    assert_equal "math.s1", a.skill
    refute_equal first_instance, a.instance.id
  end

  test "auto_second_sitting_next_day: the budget with skills left opens a second sitting from the next day" do
    skip "AUTO_SECOND_SITTING is off" unless Diagnosis::Rules::V1::AUTO_SECOND_SITTING
    d = DiagnosisHelper::Driver.new(flat_plan(count: 10, minutes: 10))
    d.start
    6.times { d.play("correct", seconds: 110) }
    a = d.action
    assert_equal :end_sitting, a.type
    d.push("sitting_closed", reason: a.reason)
    b = d.action
    assert_equal :start_sitting, b.type
    assert_equal Date.new(2026, 11, 3), b.not_before
    d.clock.advance_to(b.not_before)
    d.push("sitting_started")
    assert_equal :serve, d.action.type
    # Second sitting reaches its budget too: the run closes with time_budget.
    6.times { d.play("correct", seconds: 110) }
    assert_equal :close_run, d.action.type
    assert_equal "time_budget", d.action.reason
    d.push("run_closed", reason: "time_budget")
    rows = d.result[:sittings]
    assert_equal [ 660, 660 ], rows.map { |r| r[:counted_seconds] }
    assert_equal %w[unsupervised unsupervised], rows.map { |r| r[:condition] }
  end

  test "frontier empty at the same moment as the budget closes as frontier_empty" do
    d = DiagnosisHelper::Driver.new(flat_plan(count: 1, minutes: 10))
    d.start
    2.times { d.play("correct", seconds: 400) }
    assert_equal "frontier_empty", d.action.reason
  end

  test "extend_grants_second_sitting_next_day" do
    d = DiagnosisHelper::Driver.new(flat_plan(count: 10, minutes: 10, sittings: 1))
    d.start
    6.times { d.play("correct", seconds: 110) }
    a = d.action
    assert_equal :close_run, a.type
    assert_equal "time_budget", a.reason
    d.push("run_closed", reason: "time_budget")
    assert_equal :none, d.action.type
    d.clock.advance(3600)
    d.push("extend_diagnosis_run")
    b = d.action
    assert_equal :start_sitting, b.type
    assert_equal Date.new(2026, 11, 3), b.not_before
    d.clock.advance_to(b.not_before)
    d.push("sitting_started")
    assert_equal :serve, d.action.type
  end

  test "a run closed by the teacher stays closed even after an extension" do
    d = DiagnosisHelper::Driver.new(flat_plan(count: 3, sittings: 1))
    d.start
    d.push("close_diagnosis_run")
    d.push("extend_diagnosis_run")
    assert_equal :none, d.action.type
  end

  test "item cap: 30 items end a sitting with item_cap, the second sitting may go on, then the run closes" do
    d = DiagnosisHelper::Driver.new(flat_plan(count: 40, minutes: 60))
    d.start
    30.times { d.play("correct", seconds: 5) }
    a = d.action
    assert_equal :end_sitting, a.type
    assert_equal "item_cap", a.reason
    d.push("sitting_closed", reason: "item_cap")
    d.clock.advance_to(d.action.not_before)
    d.push("sitting_started")
    30.times { d.play("correct", seconds: 5) }
    assert_equal :close_run, d.action.type
    assert_equal "item_cap", d.action.reason
  end

  test "sitting budget is per sitting: the second sitting starts from zero" do
    d = DiagnosisHelper::Driver.new(flat_plan(count: 10, minutes: 10))
    d.start
    6.times { d.play("correct", seconds: 110) }
    d.push("sitting_closed", reason: "time_budget")
    d.clock.advance_to(d.action.not_before)
    d.push("sitting_started")
    d.play("correct", seconds: 100)
    sittings = d.result[:sittings]
    assert_equal 100, sittings.last[:counted_seconds]
  end

  test "budgets: 30 minutes for mathematics, 25 for the others" do
    assert_equal 1800, flat_plan.sitting_seconds
    other = Diagnosis::Plan.build(blueprint: { "subject" => "history", "entries" => [ { "skill" => "history.a", "items" => [ "i" ] } ] })
    assert_equal 1500, other.sitting_seconds
  end
end
