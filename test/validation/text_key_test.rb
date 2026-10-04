require "test_helper"
require_relative "../support/validation_fixtures"

# A normalized_text key that is only punctuation normalizes to nothing: no student
# answer could match it, so validation refuses it (D-073).
class TextKeyTest < ActiveSupport::TestCase
  test "the key of an instance and of an error value must survive the normaliser" do
    assert_equal [ "casa", nil ], Validation::Answers.raw_for("normalized_text", "casa")
    [ ".", " ... ", "?!", "…", "¿¡", "​", ";" ].each do |bad|
      raw, problem = Validation::Answers.raw_for("normalized_text", bad)
      assert_nil raw, bad.inspect
      assert_match(/only punctuation/, problem, bad.inspect)
    end
    assert_includes Validation::Answers.shape_problems("normalized_text", "!!", {}).first, "only punctuation"
    assert_empty Validation::Answers.shape_problems("normalized_text", "-", {}) # a dash is a word here, not trailing punctuation
  end

  test "an accepted text that is only punctuation is E-SCHEMA" do
    item = { "kind" => "single", "component" => "normalized_text", "accept" => [ "ok", "..." ], "instances" => [] }
    findings = Validation::Findings.new
    Validation::ItemChecks.accent_policy(item, findings)
    assert_equal [ "E-SCHEMA" ], findings.map(&:code)
    assert_equal "/accept/1", findings.first.field
  end
end
