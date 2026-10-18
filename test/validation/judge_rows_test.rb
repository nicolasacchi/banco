require "test_helper"
require_relative "../support/validation_fixtures"

# W-MATCHING-JUDGE-ROWS (D-314): a judge matching (two right options) needs at least 2 rows of each option in every
# instance; with a single odd row one option for every row gets all rows right but one. A warning: it does not block.
class JudgeRowsTest < ActiveSupport::TestCase
  F = ValidationFixtures

  def run_item(item) = Validation::ItemRunner.new(files: F.files_for(item), context: F.context).call
  def codes(result) = result.findings.map(&:code).uniq

  def instance(labels, right: 2, stem: "Giudica.")
    display = { "stem_it" => stem, "reuse_right" => true,
                "left" => labels.each_index.map { |i| { "id" => "l#{i + 1}", "text" => "frase numero #{i + 1} #{stem}" } },
                "right" => (1..right).map { |i| { "id" => "r#{i}", "text" => "etichetta #{i}" } } }
    answer = labels.each_with_index.to_h { |r, i| [ "l#{i + 1}", r ] }
    wrong = answer.merge("l1" => answer["l1"] == "r1" ? "r2" : "r1")
    { "display" => display, "answer" => answer, "errors" => [ { "code" => "swap", "value" => wrong } ],
      "solution" => { "steps" => [ { "text_it" => "Giudica." } ], "final" => "fatto" } }
  end

  def matching_item(*instances)
    F.static_item("component" => "matching", "instances" => instances,
                  "error_catalogue" => [ { "code" => "swap", "description_it" => "Scambio.", "message_it" => "Controlla.", "implicates" => [] } ],
                  "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" })
  end

  test "a judge instance with one odd row is warned, with the option and the row count" do
    result = run_item(matching_item(instance(%w[r1 r1 r1 r2 r2 r2]), instance(%w[r1 r1 r1 r1 r1 r2], stem: "Giudica ancora.")))
    found = result.findings.select { |f| f.code == "W-MATCHING-JUDGE-ROWS" }
    assert_equal [ "/instances/1/display/right/1" ], found.map(&:field)
    assert_equal 1, found.first.detail[:rows]
    assert_equal "warning", found.first.severity
    assert_includes found.first.message, "etichetta 2"
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
  end

  test "two rows of each option or more are quiet" do
    result = run_item(matching_item(instance(%w[r1 r1 r1 r2 r2 r2]), instance(%w[r1 r1 r1 r1 r2 r2], stem: "Giudica ancora.")))
    assert_not_includes codes(result), "W-MATCHING-JUDGE-ROWS"
  end

  test "three categories with a single row of one are not a judge" do
    result = run_item(matching_item(instance(%w[r1 r1 r2 r3 r2], right: 3), instance(%w[r1 r2 r2 r3 r3], right: 3, stem: "Giudica ancora.")))
    assert_not_includes codes(result), "W-MATCHING-JUDGE-ROWS"
  end

  test "a one-to-one matching is not a judge" do
    left = (1..4).map { |i| { "id" => "l#{i}", "text" => "sinistra #{i}" } }
    right = (1..5).map { |i| { "id" => "r#{i}", "text" => "destra #{i}" } }
    answer = (1..4).to_h { |i| [ "l#{i}", "r#{i}" ] }
    inst = { "display" => { "stem_it" => "Abbina.", "left" => left, "right" => right }, "answer" => answer,
             "errors" => [ { "code" => "swap", "value" => answer.merge("l1" => "r2", "l2" => "r1") } ],
             "solution" => { "steps" => [ { "text_it" => "Abbina." } ], "final" => "fatto" } }
    assert_not_includes codes(run_item(matching_item(inst, inst.merge("display" => inst["display"].merge("stem_it" => "Abbina ancora."))))), "W-MATCHING-JUDGE-ROWS"
  end

  test "a judge sub item of a testlet is checked too" do
    judge = matching_item(instance(%w[r1 r1 r1 r2 r2 r2]), instance(%w[r1 r1 r1 r1 r1 r2], stem: "Giudica ancora."))
    subs = (1..5).map { |i| judge.slice("skill", "component", "prompt", "error_catalogue", "instances", "tests").merge("id" => "q#{i}") }
    testlet = { "schema" => "banco.item/1", "schema_version" => 1, "kind" => "testlet", "subject" => "math", "skill" => F::SKILL,
                "passage_it" => "Leggi le frasi e giudica ognuna.", "expected_seconds" => 300, "sub_items" => subs, "sources" => judge["sources"] }
    fields = run_item(testlet).findings.select { |f| f.code == "W-MATCHING-JUDGE-ROWS" }.map(&:field)
    assert_includes fields, "/sub_items/0/instances/1/display/right/1"
  end

  test "a generated instance is checked the same way, once per seed" do
    unit = Validation::Units.of(matching_item(instance(%w[r1 r1 r1 r2 r2 r2]))).first
    checker = Validation::InstanceChecks.new(unit, context: F.context)
    found = checker.call(instance(%w[r1 r1 r1 r1 r1 r2]), label: "generated", seed: 7, generated: true).select { |f| f.code == "W-MATCHING-JUDGE-ROWS" }
    assert_equal [ [ "generated/display/right/1", [ 7 ] ] ], found.map { |f| [ f.field, f.detail[:seeds] ] }
    assert_empty checker.call(instance(%w[r2 r1 r2 r1 r2 r1]), label: "generated", seed: 8, generated: true).select { |f| f.code == "W-MATCHING-JUDGE-ROWS" }
  end
end
