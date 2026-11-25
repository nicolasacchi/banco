require "test_helper"

# The time one lesson revision's render may take (D-402, round 7): the floor, plus a few seconds for each shot already taken, under a cap. A 13-card lesson with 8
# «Prova tu» takes some 66 shots in some 85 s on a quiet server: a flat 90 s passed or failed with the load.
class LessonRenderBudgetTest < ActiveSupport::TestCase
  Runner = Validation::LessonRenderRunner

  test "the budget is the floor with no shot and grows by the rule's seconds for each shot" do
    assert_equal 90, Runner.budget_for(0)
    assert_equal 92, Runner.budget_for(1)
    assert_equal 222, Runner.budget_for(66), "the lesson that took 85 s for 66 shots has 222 s at its last shot"
    assert_operator Runner.budget_for(66), :>, 85 * 2
  end

  test "the budget never passes the cap, and the numbers are the file's" do
    assert_equal Validation::Rules.get(:lesson2, :render, :budget_seconds_max), Runner.budget_for(10_000)
    Validation::Rules.with(lesson2: { render: { budget_seconds: 100, budget_seconds_per_shot: 3, budget_seconds_max: 250 } }) do
      assert_equal 100, Runner.budget_for(0)
      assert_equal 160, Runner.budget_for(20)
      assert_equal 250, Runner.budget_for(500)
    end
    Validation::Rules.with(lesson2: { render: { budget_seconds: 0 } }) { assert_equal 0, Runner.budget_for(0), "a floor of 0 in a test means over budget at once" }
  end

  test "a render is over budget when the clock passes the budget of the shots taken so far, not the flat floor" do
    now = 0.0
    runner = Runner.new(nil, body: { "cards" => [] }, token: "t", clock: -> { now })
    runner.instance_variable_set(:@started, 0.0)
    runner.instance_variable_set(:@shots, [])
    now = 91.0
    assert runner.send(:over_budget?), "no shot: the floor of 90 s"
    runner.instance_variable_set(:@shots, Array.new(66) { {} })
    assert_not runner.send(:over_budget?), "66 shots: 222 s"
    now = 223.0
    assert runner.send(:over_budget?)
  end

  test "a timeout finding says it is the server's limit and gives the retry command; a content finding is untouched" do
    runner = Runner.new(nil, body: { "cards" => [] }, token: "t")
    runner.instance_variable_set(:@errors, [])
    runner.send(:add, "E-LESSON-RENDER", 3, "390x844-cream", "timeout: the card took more than 5 s")
    runner.send(:add, "E-LESSON-OVERFLOW", 3, "390x844-cream", "the card is wider than the screen")
    timeout, content = runner.instance_variable_get(:@errors)
    assert_match(/\Atimeout: the card took more than 5 s/, timeout["message"], "still a timeout finding: timeout_only? reads the start")
    assert_includes timeout["message"], "server's time limit, not the content of the lesson"
    assert_includes timeout["message"], "banco lesson render REV --retry"
    assert_equal "the card is wider than the screen", content["message"]
  end
end
