require "test_helper"
require_relative "../../support/diagnosis_helper"

# D-304: the time the student's comment box is open is not counted, like a pause or a hidden tab, and a comment
# never changes the engine's choices or a grade. PROP_RUNS sets the number of random cases.
class DiagnosisCommentClockTest < ActiveSupport::TestCase
  include DiagnosisHelper

  RUNS = Integer(ENV.fetch("PROP_RUNS", 50))
  T0 = Diagnosis::FakeClock::START

  def flat_plan(count: 3, **opts)
    skills = (1..count).to_h { |i| [ "math.s#{i}", {} ] }
    build_plan(skills: skills, entries: skills.keys, **opts)
  end

  def counted(driver) = driver.result[:counted_seconds]

  test "an open comment box is not counted" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    d.clock.advance(40)
    d.push("comment_opened")
    d.clock.advance(300)
    d.push("comment_closed")
    d.answer(s, "correct", seconds: 20)
    assert_equal 60, counted(d)
  end

  test "a box left open runs to the answer and ends at the next serve" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    d.clock.advance(30)
    d.push("comment_opened")
    d.answer(s, "correct", seconds: 400) # the page was left; no comment_closed
    d.play("correct", seconds: 50)       # the next serve closes the open interval
    assert_equal 30 + 50, counted(d)
  end

  test "a comment overlapping a hidden tab or a pause is subtracted once" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    s = d.serve!
    d.clock.advance(10)
    d.push("hidden")
    d.clock.advance(20)
    d.push("comment_opened")
    d.clock.advance(30)
    d.push("visible")
    d.clock.advance(40)
    d.push("comment_closed")
    d.push("paused")
    d.clock.advance(100)
    d.push("resumed")
    d.answer(s, "correct", seconds: 5)
    # 10 s plain, then 20 + 30 + 40 (union of hidden 10..60 and comment 30..100) and the pause 100..200 are all out
    assert_equal 10 + 5, counted(d)
  end

  test "the comment box does not run the abandon clock" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    d.serve!
    d.clock.advance(10)
    d.push("comment_opened")
    d.clock.advance(Diagnosis::Rules::V1::ABANDON_GAP_SECONDS * 3)
    assert_equal :wait, d.action.type, "an open comment box does not count toward the abandon gap"
    d.push("comment_closed")
    assert_equal :wait, d.action.type
  end

  test "comment events before the first serve or after the last are harmless" do
    d = DiagnosisHelper::Driver.new(flat_plan)
    d.start
    d.push("comment_opened")
    d.clock.advance(500)
    d.push("comment_closed")
    d.play("correct", seconds: 40)
    d.push("comment_opened")
    d.clock.advance(500)
    d.push("comment_closed")
    assert_equal 40, counted(d)
  end

  # The property: with comment boxes opened anywhere in an item, however long, the run is exactly the run of a student who
  # never wrote a comment and whose clock did not run during the box (same serves, same grades, same counted time).
  test "property: comments change neither the engine's choices nor any result, only the wall clock" do
    RUNS.times do |i|
      seed = 9100 + i
      rng = Random.new(seed)
      plan = flat_plan(count: 4 + rng.rand(8), minutes: 20 + rng.rand(40), sittings: 1 + rng.rand(2))
      script = Array.new(40) do
        { verdict: %w[correct wrong correct dont_know].sample(random: rng), a: 1 + rng.rand(200), b: 1 + rng.rand(200),
          box: rng.rand < 0.5 ? rng.rand(4000) : nil, hidden: rng.rand < 0.2 }
      end
      plain = DiagnosisHelper::Driver.new(plan)
      noisy = DiagnosisHelper::Driver.new(plan)
      [ plain, noisy ].each(&:start)
      script.each do |step|
        next unless plain.action.type == :serve

        assert_equal plain.action.instance.id, noisy.action.instance.id, "seed=#{seed} the engine chose another item"
        ps = plain.serve!
        ns = noisy.serve!
        plain.clock.advance(step[:a] + step[:b])
        noisy.clock.advance(step[:a])
        if step[:box]
          noisy.push("hidden") if step[:hidden]
          noisy.push("comment_opened")
          noisy.clock.advance(step[:box])
          noisy.push("visible") if step[:hidden]
          noisy.push("comment_closed")
        end
        noisy.clock.advance(step[:b])
        plain.push("answered", serve: ps[:seq], verdict: step[:verdict])
        noisy.push("answered", serve: ns[:seq], verdict: step[:verdict])
      end
      assert_equal plain.result, noisy.result, "seed=#{seed}"
      assert_equal counted(plain), counted(noisy), "seed=#{seed}"
    end
  end
end
