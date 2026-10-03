require "test_helper"
require_relative "../../support/diagnosis_helper"

# Plan#descent_targets: the skills the blueprint must pin items for (D-034).
class DiagnosisDescentTargetsTest < ActiveSupport::TestCase
  include DiagnosisHelper

  test "parents and error implicates, transitively, without the entries themselves" do
    plan = build_plan(skills: {
                        "math.a" => { prereqs: [ "math.b" ], errors: { "slip" => [ "math.d" ] } },
                        "math.b" => { prereqs: [ "math.c" ] },
                        "math.c" => {}, "math.d" => {}, "math.unrelated" => {}
                      })
    assert_equal %w[math.b math.c math.d], plan.descent_targets
  end

  test "an in_progress skill is not a target, but what lies below it still is" do
    plan = build_plan(skills: {
                        "math.a" => { prereqs: [ "math.b" ] },
                        "math.b" => { prereqs: [ "math.c" ], scope: "in_progress" },
                        "math.c" => {}
                      })
    assert_equal %w[math.c], plan.descent_targets
  end

  test "skills of other subjects are not targets (they are reused, never served)" do
    plan = build_plan(skills: { "math.a" => { prereqs: [ "italian.x" ] }, "italian.x" => {} })
    assert_empty plan.descent_targets
  end

  test "another entry is not a descent target" do
    plan = build_plan(skills: { "math.a" => { prereqs: [ "math.b" ] }, "math.b" => {} }, entries: %w[math.a math.b])
    assert_empty plan.descent_targets
  end

  test "a flat subject has none" do
    assert_empty build_plan(skills: { "math.a" => {} }).descent_targets
  end
end
