require "test_helper"
require_relative "../support/validation_fixtures"

# D-216: the blueprint's formula_sheet_it is linted as Italian text and limited in size.
class D216FormulaSheetTest < ActiveSupport::TestCase
  F = ValidationFixtures

  SKILLS = %w[math.integer-operations math.fractions-operations math.linear-equation-integer math.percentages].freeze

  def blueprint_findings(sheet)
    items = ->(id) { Validation::BlueprintChecks::ItemInfo.new(id: id, skills: [ SKILLS.fetch(id[1..].to_i) ], passed: true, instances: (1..4).map { |i| { fingerprint: "#{id}-#{i}", low_guess: true } }) }
    doc = { "schema" => "banco.blueprint/1", "schema_version" => 1, "subject" => "math", "graph_revision_id" => "1",
            "entries" => SKILLS.each_with_index.map { |s, i| { "skill" => s, "items" => [ "a#{i}", "b#{i}" ] } },
            "descent" => [ { "skill" => "math.factoring", "not_assessed_reason_it" => "Non misurabile." }, { "skill" => "math.decimal-operations", "not_assessed_reason_it" => "Non misurabile." } ],
            "budget" => { "sitting_minutes" => 30, "sittings" => 2 }, "depends_on_subjects" => [], "calculator" => "no",
            "intro_note_it" => "Il test dura mezz'ora.", "not_measured_it" => "Non misura la geometria." }
    doc["formula_sheet_it"] = sheet if sheet
    Validation::BlueprintChecks.call(doc, graph: F::GRAPH, subject: "math", context: F.context, items: items)
  end

  test "a blueprint formula sheet is linted as Italian text and limited in size" do
    ok = blueprint_findings("Area del rettangolo: $A = b \\cdot h$.\n\nPerimetro del quadrato: $P = 4l$.")
    assert_empty ok.select { |f| f.code == "E-READ" || f.code == "E-SCHEMA" }.map(&:to_h)
    shouting = blueprint_findings("Ricorda la FORMULA dell'area.")
    assert_equal "/formula_sheet_it", shouting.find { |f| f.code == "E-READ" }.field
    assert_includes blueprint_findings("Una formula. " * 200).map(&:code), "E-SCHEMA"
  end
end
