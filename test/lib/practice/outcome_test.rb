require "test_helper"

# A8.2: the evidence key of Grading::Evidence gives the practice outcome.
class PracticeOutcomeTest < ActiveSupport::TestCase
  TABLE = {
    "correct" => [ :correct, :correct_aided, :C ],
    "orthography_slip" => [ :correct, :correct_aided, :C ],
    "wrong_form_declared" => [ :correct, :correct_aided, :C ],
    "typical_error" => [ :typical_error, :typical_error, :W ],
    "wrong" => [ :unrecognised, :unrecognised, :W ],
    "wrong_form_skill" => [ :form, :form, :W ],
    "near_miss" => [ :near_miss, :near_miss, :N ],
    "undetermined" => [ :undetermined, :undetermined, :N ],
    "float_method" => [ :undetermined, :undetermined, :N ],
    "wrong_form_undeclared" => [ :undetermined, :undetermined, :N ]
  }.freeze

  test "every row of the table" do
    TABLE.each do |key, (unaided, aided, evidence)|
      assert_equal unaided, Practice::Outcome.call(evidence_key: key, aided: false), key
      assert_equal aided, Practice::Outcome.call(evidence_key: key, aided: true), key
      assert_equal evidence, Practice::Outcome.evidence(unaided), key
    end
  end

  test "the evidence class agrees with the diagnosis table for every key it covers" do
    TABLE.each do |key, (unaided, _aided, evidence)|
      diagnosis = Diagnosis::Rules::V1::EVIDENCE.fetch(key)
      assert_equal({ C: :C, W: :W, pending: :N }.fetch(diagnosis), evidence, key)
      assert_equal evidence, Practice::Outcome.evidence(unaided)
    end
  end

  test "keys that are not a try" do
    %w[invalid dont_know short_answer ungraded nonsense].each do |key|
      assert_not Practice::Outcome.try?(key), key
      assert_raises(Practice::Outcome::NotATry) { Practice::Outcome.call(evidence_key: key, aided: false) }
    end
  end

  test "every key of the diagnosis table is either a try or listed as not one" do
    not_tries = %w[dont_know short_answer ungraded invalid]
    Diagnosis::Rules::V1::EVIDENCE.each_key do |key|
      assert_equal !not_tries.include?(key), Practice::Outcome.try?(key), key
    end
  end

  test "outcomes of Evidence.key for the checker verdicts" do
    spec = Grading::Spec.from_hash("component" => "number", "skill" => "math.a", "answer" => "1")
    assert_equal :correct, Practice::Outcome.call(evidence_key: Grading::Evidence.key(verdict: "correct", spec: spec), aided: false)
    assert_equal :unrecognised, Practice::Outcome.call(evidence_key: Grading::Evidence.key(verdict: "wrong", spec: spec), aided: false)
    assert_equal :undetermined, Practice::Outcome.call(evidence_key: Grading::Evidence.key(verdict: "correct", spec: spec, method: "float"), aided: false)
    flagged = Grading::Spec.from_hash("component" => "normalized_text", "skill" => "italian.a", "answer" => "è", "accent_policy" => "flag")
    key = Grading::Evidence.key(verdict: "typical_error", spec: flagged, error_codes: [ "it_accents" ])
    assert_equal "orthography_slip", key
    assert_equal :correct, Practice::Outcome.call(evidence_key: key, aided: false)
  end
end
