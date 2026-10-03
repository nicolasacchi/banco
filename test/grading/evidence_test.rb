require "test_helper"

# The verdict-to-evidence mapping (X-03, operator G and Q10) as a pure function.
class GradingEvidenceTest < ActiveSupport::TestCase
  V1 = Diagnosis::Rules::V1

  def spec(**item) = Grading::Spec.from_hash({ "component" => "normalized_text", "skill" => "spanish.estar" }.merge(item.stringify_keys))
  def evidence(verdict, spec: self.spec, **rest) = Grading::Evidence.call(verdict: verdict, spec: spec, **rest)

  test "certain verdicts" do
    assert_equal :C, evidence("correct")
    assert_equal :W, evidence("typical_error", error_codes: [ "wrong_person_ending" ])
    assert_equal :W, evidence("wrong")
    assert_equal :D, evidence("dont_know")
  end

  test "uncertain verdicts count neither way" do
    assert_equal :pending, evidence("undetermined")
    assert_equal :pending, evidence("short_answer")
    assert_equal :pending, evidence("near_miss"), "operator Q10 (a): a one-letter typo goes to the teacher"
  end

  test "a float result is uncertain whatever it says" do
    %w[correct wrong typical_error wrong_form undetermined].each do |verdict|
      assert_equal :pending, evidence(verdict, method: "float"), verdict
    end
    assert_equal :C, evidence("correct", method: "exact")
  end

  test "accent slip: credit only on an item that does not measure accents" do
    flag = spec(accent_policy: "flag")
    strict = spec(accent_policy: "strict")
    assert_equal V1::ORTHOGRAPHY_SLIP == :credit ? :C : :pending, evidence("typical_error", spec: flag, error_codes: [ "es_accents" ])
    assert_equal :C, evidence("typical_error", spec: flag, error_codes: [ "it_apostrophe_accent" ])
    assert_equal :W, evidence("typical_error", spec: strict, error_codes: [ "es_accents" ])
    assert_equal :W, evidence("typical_error", spec: flag, error_codes: [ "wrong_person_ending" ])
    assert_equal :W, evidence("typical_error", spec: flag, error_codes: [ "es_accents", "wrong_person_ending" ])
  end

  test "wrong form: the item's own skill, a declared other skill, or undeclared" do
    own = spec(form: [ "lowest_terms" ], skill: "math.fraction-reduction")
    declared = spec(form: [ "lowest_terms" ], skill: "math.fractions-operations", form_skill: "math.fraction-reduction")
    assert_equal :W, evidence("wrong_form", spec: own)
    assert_equal :C, evidence("wrong_form", spec: declared)
    assert_equal :C, evidence("wrong_form", spec: declared, prerequisites: [ "math.fraction-reduction" ])
    assert_equal :pending, evidence("wrong_form", spec: declared, prerequisites: [ "math.integers" ]),
                 "a form skill outside the prerequisite closure is undeclared"
  end

  test "defaults of the operator can be flipped in one place" do
    declared = spec(form: [ "lowest_terms" ], skill: "math.a", form_skill: "math.b")
    assert_equal V1::EVIDENCE.fetch("wrong_form_declared"), evidence("wrong_form", spec: declared)
    assert_equal V1::EVIDENCE.fetch("near_miss"), evidence("near_miss")
  end

  test "observations accompany a credit" do
    declared = spec(skill: "math.a", form_skill: "math.b")
    assert_equal [ { kind: :tail_suspect_on_form_skill, skill: "math.b" } ], Grading::Evidence.observations(verdict: "wrong_form", spec: declared)
    flag = spec(accent_policy: "flag")
    assert_equal [ { kind: :observation_on_orthography_skill, skill: nil } ],
                 Grading::Evidence.observations(verdict: "typical_error", spec: flag, error_codes: [ "es_accents" ])
    assert_empty Grading::Evidence.observations(verdict: "correct", spec: flag)
    assert_empty Grading::Evidence.observations(verdict: "wrong", spec: flag)
  end

  test "a stored grading without rows is ungraded, an invalid answer is not an attempt" do
    assert_equal :ungraded, Grading::Evidence.for_grading(nil, spec)
    assert_equal :none, V1::EVIDENCE.fetch("invalid")
  end

  test "every verdict the graders emit has an evidence" do
    Grading::VERDICTS.each do |verdict|
      key = Grading::Evidence.key(verdict: verdict, spec: spec(form_skill: "x.y"))
      assert V1::EVIDENCE.key?(key), "#{verdict} -> #{key}"
    end
  end

  test "grader codes in the orthography allowlist are registered" do
    registry = YAML.load_file(Rails.root.join("config/banco/error_codes.yml"))["grader_codes"]
    assert_empty V1::ORTHOGRAPHY_ALLOWLIST - registry.keys
  end
end
