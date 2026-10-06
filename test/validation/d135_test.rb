require "test_helper"
require_relative "../support/validation_fixtures"

# D-135: round_to on a number error, and an item implicate into another subject's draft graph.
class D135Test < ActiveSupport::TestCase
  F = ValidationFixtures

  def run_item(item, context: F.context)
    Validation::ItemRunner.new(files: F.files_for(item), context: context).call
  end

  def codes(result) = result.findings.map(&:code).uniq

  def with_round_to(round_to, value: "11", answer: nil)
    inst = F.number_instance(2, 9)
    inst["answer"] = answer if answer
    inst["errors"] = [ { "code" => "sign_error", "value" => value, "round_to" => round_to } ]
    F.static_item("instances" => [ inst, F.number_instance(4, 13) ])
  end

  test "round_to on a number error that does not touch the key passes" do
    result = run_item(with_round_to(1, value: "11,04"))
    assert_not_includes codes(result), "E-GEN-SCHEMA", result.findings.map(&:to_h).inspect
  end

  test "round_to whose window contains the key is refused" do
    result = run_item(with_round_to(0, value: "7,4"))
    assert_includes codes(result), "E-GEN-SCHEMA"
  end

  test "round_to outside 0..6 is a schema error" do
    assert_includes codes(run_item(with_round_to(9, value: "11,5"))), "E-SCHEMA"
  end

  test "an item implicate into a draft graph of another subject is a warning, not E-SKILL-UNKNOWN" do
    item = F.static_item
    item["error_catalogue"][0]["implicates"] = [ "chemistry.draft-skill" ]
    context = F.context
    draft = Validation::Context.new(subject: "math", skill: context.method(:skill).to_proc, graph_present: true,
                                    draft_skill: ->(k) { k == "chemistry.draft-skill" ? { "key" => k } : nil },
                                    source_line: ->(s, n) { context.source_line(s, n) }, reference_body: ->(k) { context.reference_body(k) })
    result = run_item(item, context: draft)
    assert_includes codes(result), "W-IMPLICATE-PENDING", result.findings.map(&:to_h).inspect
    assert_not_includes result.findings.select { |f| f.code == "E-SKILL-UNKNOWN" }.map { |f| f.field.to_s }.join, "implicates"
    assert_includes codes(run_item(item)), "E-SKILL-UNKNOWN"
  end
end
