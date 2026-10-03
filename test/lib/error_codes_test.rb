require "test_helper"

# One registry (X-03): a code named differently by the grader and the rules would
# switch a mask off in silence.
class ErrorCodesTest < ActiveSupport::TestCase
  REGISTRY = YAML.load_file(Rails.root.join("config/banco/error_codes.yml"))

  test "validation codes are E- or W- names with a stage, severity and description" do
    REGISTRY["validation"].each do |code, meta|
      next if %w[quote_not_in_submission grader_is_author].include?(code)

      assert_match(/\A[EW](-[A-Z0-9]+)+\z/, code)
      assert_equal(code.start_with?("E") ? "error" : "warning", meta["severity"], code)
      assert meta["stage"].present? && meta["description"].present?, code
    end
  end

  test "every code listed in A-06 is in the registry" do
    listed = %w[E-SCHEMA E-GRAPH-CYCLE E-SOURCE E-SCOPE E-NEEDED-BY E-GRAPH-EDGE-UNAPPROVED E-SKILL-UNKNOWN E-ASSET
                E-COMPOSITE E-CODE-GLOBAL E-GEN-NONDETERMINISTIC E-GEN-THROW E-GEN-TIMEOUT E-GEN-SCHEMA E-GEN-POOL
                E-COMPONENT-NUMERIC E-EXPONENT-MULTIDIGIT E-ROUNDTRIP E-ERROR-NEVER-GENERATED E-ACCEPTS-RANDOM
                E-STEP-INCONSISTENT E-VERIFY-MISSING E-VERIFY-AUTHOR E-VERIFY-REJECTS E-VERIFY-VACUOUS E-DISPLAY-KEY
                E-SOLUTION-IN-DISPLAY W-ANSWER-IN-STEM E-CHOICE-OPTIONS E-DISTRACTOR-UNCODED E-OPTION-DUPLICATE
                W-LONGEST-CORRECT E-MATCHING-SIZE E-ACCENT-POLICY E-PROVA-A-PARAMS E-READ E-PHRASE E-MESSAGE E-QUOTE-REF
                W-GULPEASE W-PASSAGE-READABILITY W-ABSOLUTE W-NEGATIVE-STEM W-DECIMAL-POINT W-SELF-CERT W-CALCULATOR
                E-POOL-REDO E-BLUEPRINT-ENTRIES E-ITEM-NOT-PASSED E-QUOTE-NOT-FOUND E-BLIND-SOLVE-MISMATCH
                E-SESSION-NOT-INDEPENDENT E-PROVIDER-NOT-ALLOWED]
    assert_empty listed - REGISTRY["validation"].keys
  end

  test "API codes carry an HTTP status" do
    REGISTRY["api"].each_value { |meta| assert_kind_of Integer, meta["http"] }
    assert_equal [ 401, 409, 409, 503, 422, 413, 404, 404, 422, 404, 422, 422, 409 ], REGISTRY["api"].values.map { |m| m["http"] }
  end

  test "every orthography code of Rules::V1 is a code the grader emits" do
    assert_empty Diagnosis::Rules::V1::ORTHOGRAPHY_ALLOWLIST - REGISTRY["grader_codes"].keys
  end

  test "grader codes are snake_case" do
    REGISTRY["grader_codes"].each_key { |code| assert_match(/\A[a-z]+(_[a-z]+)*\z/, code) }
  end

  test "codes in the contract exist in the registry" do
    known = REGISTRY["validation"].keys + REGISTRY["api"].keys
    Contract.parsed["commands"].flat_map { |c| c["error_codes"] }.uniq.each do |code|
      assert_includes known, code
    end
  end

  test "the verdicts of the registry are the keys the evidence table starts from" do
    verdicts = REGISTRY["verdicts"].keys
    assert_empty verdicts - %w[correct typical_error wrong dont_know wrong_form near_miss undetermined invalid]
    verdicts.each do |v|
      key = Diagnosis::Rules::V1.evidence_key(v)
      assert Diagnosis::Rules::V1::EVIDENCE.key?(key) || v == "wrong_form", v
    end
  end

  test "error codes in schema fixtures are snake_case catalogue codes" do
    Banco::Schemas.fixture_files("item", :good).each do |path|
      JSON.parse(File.read(path)).fetch("error_catalogue", []).each { |e| assert_match(/\A[a-z]+(_[a-z0-9]+)*\z/, e["code"]) }
    end
  end
end
