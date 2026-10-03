require "test_helper"

# The synthetic corpus of 3,524 labelled pairs is run in full by Node
# (app/javascript/grader/test/corpus.test.mjs). Here every seventh pair goes
# through the Ruby side as well: spec -> worker -> Result.
class GradingCorpusTest < ActiveSupport::TestCase
  PAIRS = File.foreach(Rails.root.join("test/fixtures/grading/corpus.jsonl")).map { |l| JSON.parse(l) }

  teardown { Grading::Expression.shutdown }

  def spec_for(pair)
    answer = pair["expected"]
    answer = { "latex" => answer, "unknown" => pair["unknown"], "domain" => pair["domain"] } if pair["unknown"] || pair["domain"].present?
    Grading::Spec.from_hash("component" => "expression", "answer" => answer, "form" => pair["form"],
                            "errors" => pair["errors"].map { |e| { "code" => e["code"], "value" => e["latex"] } })
  end

  test "the corpus is the 3,524 pairs" do
    assert_equal 3524, PAIRS.size
    assert_equal 3524, PAIRS.map { |p| p["id"] }.uniq.size
  end

  test "a sample of the corpus gets the labelled verdict through Grading" do
    wrong = []
    PAIRS.each_slice(7).map(&:first).each do |pair|
      result = Grading.grade_spec(spec_for(pair), pair["answer"], source: pair["source"])
      ok = result.verdict == pair["expected_verdict"]
      ok &&= result.error_codes.sort == pair["truth"]["error_codes"].sort if result.verdict == "typical_error"
      wrong << [ pair["id"], pair["answer"], pair["expected_verdict"], result.verdict ] unless ok
    end
    assert_empty wrong
  end
end
