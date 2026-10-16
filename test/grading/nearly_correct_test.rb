require "test_helper"

# D-301: a matching with all pairs right but one counts as right, with the pair that was off.
class NearlyCorrectTest < ActiveSupport::TestCase
  DISPLAY = {
    "left" => (1..6).map { |i| { "id" => "l#{i}", "text" => "Sinistra #{i}" } },
    "right" => (1..6).map { |i| { "id" => "r#{i}", "text" => "Destra #{i}" } }
  }.freeze

  def key(size) = (1..size).to_h { |i| [ "l#{i}", "r#{i}" ] }

  # +wrong+: how many of the last left rows get r1 instead of their own.
  def grade(size, wrong, errors: [])
    answer = key(size)
    given = answer.dup
    (size - wrong + 1..size).each { |i| given["l#{i}"] = "r1" } if wrong.positive?
    spec = Grading::Spec.new(component: "matching", subject: "history", answer: answer, errors: errors, display: DISPLAY)
    Grading::Closed.grade(spec, given)
  end

  test "3 of 4, 5 of 6 and 2 of 3 are nearly correct" do
    [ [ 4, 1 ], [ 6, 1 ], [ 3, 1 ] ].each do |size, wrong|
      assert_equal "nearly_correct", grade(size, wrong).verdict, "#{size - wrong} of #{size}"
    end
  end

  test "2 of 4 and 4 of 6 are wrong" do
    assert_equal "wrong", grade(4, 2).verdict
    assert_equal "wrong", grade(6, 2).verdict
  end

  test "a key of two pairs is all or nothing" do
    assert_equal "wrong", grade(2, 1).verdict
  end

  test "all right stays correct" do
    assert_equal "correct", grade(4, 0).verdict
  end

  test "a declared error permutation stays typical_error" do
    swap = key(4).merge("l4" => "r1") # 3 of 4 right, and the catalogue declares exactly this answer
    result = grade(4, 1, errors: [ { "code" => "confuses_four", "value" => swap } ])
    assert_equal "typical_error", result.verdict
    assert_equal [ "confuses_four" ], result.error_codes
  end

  test "normalized names the pair that was off" do
    result = grade(6, 1)
    assert_equal({ "left" => "l6", "given" => "r1", "key" => "r6" }, JSON.parse(result.normalized)["off_pair"])
    assert_equal 5, JSON.parse(result.normalized)["correct_pairs"]
  end

  test "the line says which pair, with the texts" do
    result = grade(4, 1)
    assert_equal "Giusto, tranne una coppia: «Sinistra 4» va con «Destra 4», non con «Destra 1».", Grading::PairNote.line(DISPLAY, result.normalized)
    assert_nil Grading::PairNote.line(DISPLAY, grade(4, 0).normalized)
  end

  test "it is a credit for the engine and near_miss stays pending" do
    assert_equal :C, Diagnosis::Rules::V1.evidence("nearly_correct")
    assert_equal :pending, Diagnosis::Rules::V1.evidence("near_miss")
  end

  test "the evidence of the verdict is a credit with an observation on the item's skill" do
    spec = Grading::Spec.new(component: "matching", subject: "history", skill: "history.x", answer: key(4))
    assert_equal :C, Grading::Evidence.call(verdict: "nearly_correct", spec: spec)
    assert_equal [ { kind: :one_pair_off, skill: "history.x" } ], Grading::Evidence.observations(verdict: "nearly_correct", spec: spec)
  end

  test "the verdict is registered" do
    assert_includes Grading::VERDICTS, "nearly_correct"
    assert YAML.load_file(Rails.root.join("config/banco/error_codes.yml"))["verdicts"].key?("nearly_correct")
  end

  test "in a testlet a nearly correct sub item still makes a right unit" do
    assert_equal "correct", Grading::Testlet.unit_verdict(%w[correct nearly_correct correct])
    assert_equal "undetermined", Grading::Testlet.unit_verdict(%w[wrong nearly_correct])
  end

  test "practice reads it as a correct try with the note" do
    assert_equal :correct, Practice::Outcome.call(evidence_key: "nearly_correct", aided: false)
    assert_equal :correct_aided, Practice::Outcome.call(evidence_key: "nearly_correct", aided: true)
    assert_equal :C, Practice::Outcome.evidence(:correct)
    line = "Giusto, tranne una coppia: «Sinistra 4» va con «Destra 4», non con «Destra 1»."
    assert_equal line, Practice::Messages.note("nearly_correct", pair_note: line)
  end

  test "a stored practice grading is a correct try that carries the note" do
    result = grade(4, 1)
    grading = Struct.new(:verdict, :error_codes_json, :form_violations_json, :normalized, :method) do
      def [](name) = public_send(name)
    end.new("nearly_correct", "[]", "[]", result.normalized, nil)
    attempt = Struct.new(:latest_grading, :aided).new(grading, false)
    spec = Grading::Spec.new(component: "matching", subject: "history", answer: key(4), display: DISPLAY)
    got = Practice::Instances.grade(attempt, spec)
    assert_equal [ :correct, "nearly_correct" ], [ got.outcome, got.key ]
    assert_equal "Giusto, tranne una coppia: «Sinistra 4» va con «Destra 4», non con «Destra 1».", got.pair_note
    assert_equal "Corretto.", Practice::Messages.feedback(got.outcome)
  end

  test "lesson checks: right, with the note" do
    check = { "component" => "matching", "answer" => key(4), "left" => DISPLAY["left"].first(4), "right" => DISPLAY["right"].first(4) }
    ok = Lessons::Checks.closed(check, { "l1" => "r1", "l2" => "r2", "l3" => "r3", "l4" => "r1" }, {}, "history")
    assert ok.right?
    assert_equal "Giusto, tranne una coppia: «Sinistra 4» va con «Destra 4», non con «Destra 1».", ok.message_it
    assert Lessons::Checks.closed(check, key(4), {}, "history").right?
    assert_nil Lessons::Checks.closed(check, key(4), {}, "history").message_it
    assert Lessons::Checks.closed(check, { "l1" => "r1", "l2" => "r2", "l3" => "r1", "l4" => "r1" }, {}, "history").wrong?
  end
end
