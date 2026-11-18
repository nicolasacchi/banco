require "test_helper"
require_relative "../../support/practice_world"

# D-362 in practice (Practice::AnswerRecorder): an answer written in full is graded on its value. «x = 37/5» is right for a key of 37/5,
# «x = 37/4» is wrong; the expression shown on the left counts; another left side is not accepted.
class PracticeWrittenAnswersTest < ActiveSupport::TestCase
  include PracticeWorld

  STEM = "Risolvi $5x=37$.".freeze

  setup { build_practice_world(items: 1, instances: 1) }

  # One practice item of the given component, pinned alone on the skill, whose single instance has the key 37/5.
  def pin_fraction_key(component, answer, stem: STEM, errors: [])
    revision = make_practice_item("math-written-#{component}", SKILL, component: component, instances: 0, errors: ->(_i) { [] })
    ItemInstance.create!(item_revision: revision, seed: 1, display_json: JSON.generate(stem_it: stem), answer_json: JSON.generate(answer),
                         errors_json: JSON.generate(errors), hints_json: JSON.generate([]),
                         solution_json: JSON.generate(steps: [ { text_it: "Passo." } ], final: "$x$"), fingerprint: Digest::SHA256.hexdigest("written-#{component}"))
    @topic = make_topic(@lesson_revision, { SKILL => [ revision ] })
  end

  def outcome_of(raw)
    body(answer!(serve!, raw)).slice(:outcome, :error_code)
  end

  def body(result) = result.body

  test "an expression key of 37/5: «x = 37/5» is right" do
    pin_fraction_key("expression", "\\frac{37}{5}")
    assert_equal "correct", outcome_of("x = 37/5")[:outcome]
  end

  test "an expression key of 37/5: «x = 7,4» is right" do
    pin_fraction_key("expression", "\\frac{37}{5}")
    assert_equal "correct", outcome_of("x = 7,4")[:outcome]
  end

  test "an expression key of 37/5: «x = 37/4» is wrong, and it is a try" do
    pin_fraction_key("expression", "\\frac{37}{5}")
    c = serve!
    assert_equal "unrecognised", body(answer!(c, "x = 37/4"))[:outcome]
    attempt = c.serve.attempts.sole
    assert_equal "wrong", attempt.gradings.sole.verdict
    assert_equal "x = 37/4", attempt.raw
  end

  test "an expression key with a typical error: the wrong value written in full keeps its code" do
    pin_fraction_key("expression", "\\frac{37}{5}", errors: [ { code: "slip", value: "\\frac{37}{4}" } ])
    assert_equal({ outcome: "typical_error", error_code: "slip" }, outcome_of("x = 37/4"))
  end

  test "the expression shown, repeated on the left, is right; another left side is held for the teacher" do
    pin_fraction_key("expression", "24a^3", stem: "Semplifica $\\sqrt{625a^6-49a^6}$.")
    assert_equal "correct", outcome_of("√(625a⁶ − 49a⁶) = 24a³")[:outcome]
  end

  test "another left side is not accepted" do
    pin_fraction_key("expression", "24a^3", stem: "Semplifica $\\sqrt{625a^6-49a^6}$.")
    c = serve!
    assert_not_equal "correct", body(answer!(c, "√(625a⁶ + 49a⁶) = 24a³"))[:outcome]
    assert_equal "undetermined", c.serve.attempts.sole.gradings.sole.verdict
  end

  # An exact step: a verdict that touched floating point is uncertain whatever it says (Grading::Evidence, `float_method`), so a
  # false step between roots is `wrong` for the checker but waits for the teacher in practice.
  test "a chain with a false step is wrong" do
    pin_fraction_key("expression", "2x+6", stem: "Semplifica $2(x+3)$.")
    assert_equal "unrecognised", outcome_of("2(x+3) = 2x+5 = 2x+6")[:outcome]
  end

  test "a fraction key of 37/5: «x = 37/5» in the numerator box is right" do
    pin_fraction_key("fraction", "37/5")
    assert_equal "correct", outcome_of({ n: "x = 37/5", d: "" }.to_json)[:outcome]
  end

  test "a fraction key of 37/5: «x = 37/4» is wrong" do
    pin_fraction_key("fraction", "37/5")
    assert_equal "unrecognised", outcome_of({ n: "x = 37/4", d: "" }.to_json)[:outcome]
  end

  test "a number key of 37/5: «x = 7,4» is right, «x = 7,5» is wrong" do
    pin_fraction_key("number", "37/5")
    assert_equal "correct", outcome_of("x = 7,4")[:outcome]
  end

  test "a number key of 37/5: «x = 7,5» is wrong" do
    pin_fraction_key("number", "37/5")
    assert_equal "unrecognised", outcome_of("x = 7,5")[:outcome]
  end
end
