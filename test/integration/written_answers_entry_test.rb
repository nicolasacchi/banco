require "test_helper"
require_relative "../support/finished_run"
require_relative "../support/decision_world"

# D-362 in the entry test (Diagnosis::AnswerRecorder): an answer written in full is graded on its value. «x = 37/5» is right for a key
# of 37/5 and «x = 37/4» is wrong; the expression shown, repeated on the left, counts; another left side is held for the teacher.
class WrittenAnswersEntryTest < ActionDispatch::IntegrationTest
  include FinishedRun
  include DecisionWorld

  SOLUTION = { steps: [ { text_it: "Si divide per cinque." } ], final: "Vedi il passaggio." }.freeze

  # The instances of the one component under test: the key is 37/5 and the stem is the one a student sees.
  def ui_instance_spec(component, i)
    case [ component, @written ]
    when [ "expression", :expression ]
      { display: { stem_it: "Risolvi $5x=37$." }, answer: "\\frac{37}{5}", errors: [ { code: "denominator_slip", value: "\\frac{37}{4}" } ], solution: SOLUTION }
    when [ "expression", :simplify ]
      { display: { stem_it: "Semplifica $\\sqrt{625a^6-49a^6}$." }, answer: "24a^3", errors: [], solution: SOLUTION }
    when [ "fraction", :fraction ]
      { display: { stem_it: "Risolvi $5x=37$.", answer_format_it: "Scrivi la frazione nelle due caselle." }, answer: { n: 37, d: 5 }, errors: [], solution: SOLUTION }
    when [ "number", :number ]
      { display: { stem_it: "Risolvi $5x=37$." }, answer: "37/5", errors: [], solution: SOLUTION }
    else super
    end
  end

  def first_step(component, kind)
    @written = kind
    rows = build_ui_subject(components: [ component ])
    release_diagnosis!
    [ rows, Diagnosis::Conductor.new(Diagnosis::Conductor.run_for(rows[:student], rows[:subject])).step! ]
  end

  # Records one answer to the first item of the subject; returns [outcome, the stored grading].
  def written(component, kind, raw)
    rows, step = first_step(component, kind)
    outcome = Diagnosis::AnswerRecorder.new(student: rows[:student], context: "diagnosis")
                                       .call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: raw, source: "text")
    [ outcome, Attempt.sole.gradings.sole ]
  end

  test "«x = 37/5» is right for an expression key of 37/5, and what he typed is kept as it is" do
    outcome, grading = written("expression", :expression, "x = 37/5")
    assert_equal "recorded", outcome.status
    assert_equal "correct", grading.verdict
    assert_equal "x = 37/5", Attempt.sole.raw, "what he typed is kept as it is"
  end

  test "«x = 37/4» is a wrong value: graded as 37/4, the catalogue's typical error" do
    _, grading = written("expression", :expression, "x = 37/4")
    assert_equal [ "typical_error", [ "denominator_slip" ] ], [ grading.verdict, JSON.parse(grading.error_codes_json) ]
  end

  test "«x = 7,4» is right too" do
    assert_equal "correct", written("expression", :expression, "x = 7,4").last.verdict
  end

  test "«x = 37/3» is wrong" do
    assert_equal "wrong", written("expression", :expression, "x = 37/3").last.verdict
  end

  test "the expression shown on the left: «√(625a⁶ − 49a⁶) = 24a³» is right" do
    assert_equal "correct", written("expression", :simplify, "√(625a⁶ − 49a⁶) = 24a³").last.verdict
  end

  test "the expression shown on the left, with a wrong value, is wrong" do
    assert_equal "wrong", written("expression", :simplify, "√(625a⁶ − 49a⁶) = 24a²").last.verdict
  end

  test "another left side is not accepted: it waits for the teacher, undetermined" do
    outcome, grading = written("expression", :simplify, "√(625a⁶ + 49a⁶) = 24a³")
    assert_equal "recorded", outcome.status
    assert_equal "undetermined", grading.verdict
    assert_equal :pending, Grading::Evidence.for_grading(grading, Grading::Spec.from_instance(Attempt.sole.item_instance))
  end

  test "a chain is right when every member is" do
    assert_equal "correct", written("expression", :simplify, "√(625a⁶ − 49a⁶) = √(576a⁶) = 24a³").last.verdict
  end

  test "a chain with a false step is wrong" do
    assert_equal "wrong", written("expression", :simplify, "√(625a⁶ − 49a⁶) = √(500a⁶) = 24a³").last.verdict
  end

  test "a fraction item: «x = 37/5» in the numerator box is right" do
    assert_equal "correct", written("fraction", :fraction, { n: "x = 37/5", d: "" }.to_json).last.verdict
  end

  test "a fraction item: «x = 37/4» is wrong" do
    assert_equal "wrong", written("fraction", :fraction, { n: "x = 37/4", d: "" }.to_json).last.verdict
  end

  test "a number item: «x = 7,4» is right" do
    assert_equal "correct", written("number", :number, "x = 7,4").last.verdict
  end

  test "a number item: «x = 7,5» is wrong" do
    assert_equal "wrong", written("number", :number, "x = 7,5").last.verdict
  end
end
