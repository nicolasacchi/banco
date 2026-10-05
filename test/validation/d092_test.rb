require "test_helper"
require_relative "../support/validation_fixtures"

# D-092: a matching may be a classification (display.reuse_right): several rows share one
# right entry. No Chrome is needed.
class D092Test < ActiveSupport::TestCase
  F = ValidationFixtures

  def run_item(item) = Validation::ItemRunner.new(files: F.files_for(item), context: F.context).call
  def codes(result) = result.findings.map(&:code).uniq

  def classification(left: 5, categories: 3, answer: nil, reuse: true, stem: "Classifica.")
    l = (1..left).map { |i| { "id" => "l#{i}", "text" => "caso #{i}" } }
    r = (1..categories).map { |i| { "id" => "r#{i}", "text" => "categoria #{i}" } }
    key = answer || l.each_with_index.to_h { |e, i| [ e["id"], "r#{(i % categories) + 1}" ] }
    wrong = key.merge("l1" => key["l1"] == "r1" ? "r2" : "r1")
    display = { "stem_it" => stem, "left" => l, "right" => r }
    display["reuse_right"] = true if reuse
    inst = { "display" => display, "answer" => key, "errors" => [ { "code" => "swap", "value" => wrong } ],
             "solution" => { "steps" => [ { "text_it" => "Classifica." } ], "final" => "fatto" } }
    other = inst.merge("display" => display.merge("stem_it" => "Classifica ancora."))
    F.static_item("component" => "matching", "instances" => [ inst, other ],
                  "error_catalogue" => [ { "code" => "swap", "description_it" => "Scambio.", "message_it" => "Controlla.", "implicates" => [] } ],
                  "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" })
  end

  test "a classification with repeated right ids and 3 categories passes" do
    result = run_item(classification)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
  end

  test "without reuse_right a repeated right id still fails" do
    result = run_item(classification(reuse: false, categories: 4))
    assert_not_empty codes(result) & %w[E-SCHEMA E-GEN-SCHEMA]
  end

  test "a classification needs 4 rows, 3 categories and fewer categories than rows" do
    assert_includes codes(run_item(classification(left: 3))), "E-MATCHING-SIZE"
    assert_includes codes(run_item(classification(left: 5, categories: 2))), "E-MATCHING-SIZE"
    assert_includes codes(run_item(classification(left: 4, categories: 4))), "E-MATCHING-SIZE"
  end

  test "a classification whose key uses one category only fails" do
    key = (1..5).to_h { |i| [ "l#{i}", "r1" ] }
    assert_not_empty codes(run_item(classification(answer: key))) & %w[E-SCHEMA E-GEN-SCHEMA]
  end

  test "a key that names a missing right id fails" do
    key = (1..5).to_h { |i| [ "l#{i}", i == 1 ? "r9" : "r#{(i % 3) + 1}" ] }
    assert_not_empty codes(run_item(classification(answer: key))) & %w[E-SCHEMA E-GEN-SCHEMA]
  end

  test "the grader gives credit only to the exact map" do
    item = classification
    unit = Validation::Units.of(item).first
    inst = item["instances"].first
    grade = ->(raw) { Grading.grade_spec(Validation::Units.spec_for(unit, "math", inst), raw).verdict }
    assert_equal "correct", grade.call(inst["answer"].to_json)
    assert_not_equal "correct", grade.call(inst["answer"].merge("l1" => "r3", "l2" => "r3").to_json)
  end

  test "Rekey shuffles a classification and replays it" do
    item = classification
    inst = item["instances"].first
    r = Diagnosis::Rekey.call(display: inst["display"], answer: inst["answer"], errors: inst["errors"], component: "matching", seed: 7)
    assert_equal true, r.display["reuse_right"]
  end
end
