require "test_helper"
require_relative "../support/validation_fixtures"

# W-SENTENCE-COMMA-VARIANTS (D-335): Grading::Closed::Text keeps the commas and semicolons inside a text (only the trailing marks go), so
# a sentence key with one marks the same sentence written without it wrong. The warning is quiet once an accept entry carries the variant.
class SentenceCommasTest < ActiveSupport::TestCase
  F = ValidationFixtures
  CODE = "W-SENTENCE-COMMA-VARIANTS".freeze
  KEY = "No salimos, ya que llovía."

  def findings(answer, accept: nil, item_accept: nil, component: "normalized_text", body: {})
    unit = Validation::Units::Unit.new(path: "", skill: F::SKILL, component: component, body: { "kind" => "diagnosis_item" }.merge(item_accept ? { "accept" => item_accept } : {}).merge(body), generator: false, instances: [])
    inst = { "display" => { "stem_it" => "Completa la frase." }, "answer" => answer, "errors" => [], "solution" => { "steps" => [ { "text_it" => "Ragiona." } ], "final" => "Fatto." } }
    inst["accept"] = accept if accept
    Validation::InstanceChecks.new(unit, context: F.context).call(inst, label: "/instances/2").select { |f| f.code == CODE }
  end

  test "the grader compares commas and semicolons inside a text, and strips only the trailing marks" do
    assert_not Grading::Closed::Text.same_answer?(KEY, "No salimos ya que llovía.")
    assert_not Grading::Closed::Text.same_answer?("Llueve; por lo tanto, voy.", "Llueve por lo tanto voy.")
    assert Grading::Closed::Text.same_answer?(KEY, "No salimos, ya que llovía")
  end

  test "a sentence key with a comma or a semicolon and no variant in accept warns, naming the instance" do
    got = findings(KEY)
    assert_equal [ "/instances/2/answer" ], got.map(&:field)
    assert_match(%r{\A/instances/2: }, got.first.message)
    assert_equal 1, findings("Llueve; por lo tanto, nos quedamos en casa.").size
    assert_equal "warning", Validation::Codes.all.fetch(CODE)["severity"]
    assert_equal 1, findings(KEY, accept: [ "No salimos, ya que llovia." ]).size, "an accept that still has the comma is not a variant"
    assert_equal 1, findings(KEY, accept: [ "Otra frase." ]).size
  end

  test "a variant without the comma in the instance's or the item's accept silences it, however it is written" do
    assert_empty findings(KEY, accept: [ "No salimos ya que llovía." ])
    assert_empty findings(KEY, item_accept: [ "no salimos ya que llovía" ])
    assert_empty findings("Llueve; por lo tanto, nos quedamos en casa.", accept: [ "Llueve por lo tanto, nos quedamos en casa." ])
    assert_equal 1, findings("No salimos, ya que llovía.", accept: [ "NO SALIMOS YA QUE LLOVÍA." ], body: { "case_sensitive" => true }).size
  end

  test "a key without a comma, a word or a sentence end, and another component, are quiet" do
    assert_empty findings("No salimos ya que llovía.")
    assert_empty findings("sí, no")
    assert_empty findings("Nunca, jamás")
    assert_empty findings("Sí.")
    assert_empty findings("7", component: "number")
  end
end
