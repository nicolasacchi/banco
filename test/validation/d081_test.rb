require "test_helper"
require_relative "../support/validation_fixtures"

# D-081: an accept list per instance, the item prompt in the leak scan, W-FORM-SKILL-CLOSURE
# and E-MATCHING-RIGHT-MARKUP. No Chrome is needed.
class D081Test < ActiveSupport::TestCase
  F = ValidationFixtures

  def run_item(item, context: F.context)
    Validation::ItemRunner.new(files: F.files_for(item), context: context).call
  end

  def codes(result) = result.findings.map(&:code).uniq

  def text_instance(key, wrong, stem, accept: nil)
    inst = { "display" => { "stem_it" => stem }, "answer" => key,
             "errors" => [ { "code" => "sign_error", "value" => wrong } ],
             "solution" => { "steps" => [ { "text_it" => "Isola l'incognita." } ], "final" => "fatto" } }
    inst["accept"] = accept if accept
    inst
  end

  def text_item(instances, overrides = {})
    F.static_item({ "component" => "normalized_text", "instances" => instances,
                    "tests" => { "must_accept" => [ "x uguale zero" ], "must_reject" => [ "mai" ], "blank" => "invalid" } }.merge(overrides))
  end

  test "an instance accept list is graded on that instance alone and is stored" do
    item = text_item([ text_instance("zero", "indeterminata", "Risolvi la prima.", accept: [ "x uguale zero" ]),
                       text_instance("impossibile", "indeterminata", "Risolvi la seconda.") ])
    result = run_item(item)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_equal [ [ "x uguale zero" ], nil ], result.instances.map { |i| i[:accept] }

    unit = Validation::Units.of(item).first
    first, second = item["instances"]
    assert_equal "correct", Grading.grade_spec(Validation::Units.spec_for(unit, "math", first), "x uguale zero").verdict
    assert_not_equal "correct", Grading.grade_spec(Validation::Units.spec_for(unit, "math", second), "x uguale zero").verdict
  end

  test "an instance accept list on a component other than normalized_text is refused" do
    inst = F.number_instance(2, 9).merge("accept" => [ "sette" ])
    result = run_item(F.static_item("instances" => [ inst, F.number_instance(4, 13) ]))
    assert_includes codes(result), "E-GEN-SCHEMA"
  end

  test "Spec.from_instance adds the instance accept list to the item's" do
    revision = Struct.new(:body_json).new(JSON.generate("kind" => "diagnosis_item", "component" => "normalized_text", "skill" => F::SKILL, "accept" => [ "a" ]))
    row = Struct.new(:item_revision, :answer_json, :errors_json, :display_json, :accept_json).new(revision, '"zero"', nil, "{}", '["x zero"]')
    assert_equal [ "a", "x zero" ], Grading::Spec.from_instance(row).accept
  end

  test "the item prompt is read with every instance: a choice key in it is E-SOLUTION-IN-DISPLAY" do
    item = F.choice_item("prompt" => { "stem_it" => "Quale valore e la soluzione? Forse sette." })
    assert_includes codes(run_item(item)), "E-SOLUTION-IN-DISPLAY"
  end

  test "the answer in the item prompt stem is W-ANSWER-IN-STEM; in its table, E-SOLUTION-IN-DISPLAY" do
    item = text_item([ text_instance("impossibile", "indeterminata", "Risolvi la prima."), text_instance("indeterminata", "impossibile", "Risolvi la seconda.") ],
                     "prompt" => { "stem_it" => "Scrivi impossibile o indeterminata, come risposta." },
                     "tests" => { "must_accept" => [], "must_reject" => [ "mai" ], "blank" => "invalid" })
    result = run_item(item)
    assert_includes codes(result), "W-ANSWER-IN-STEM"
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect

    table = F.static_item("prompt" => { "table" => { "header" => [ "Valore" ], "rows" => [ [ "7" ], [ "13 e 125" ] ] } },
                          "instances" => [ F.number_instance(25, 150), F.number_instance(4, 13) ])
    assert_includes codes(run_item(table)), "E-SOLUTION-IN-DISPLAY"
  end

  test "W-FORM-SKILL-CLOSURE: a form_skill outside the prerequisite closure" do
    outside = run_item(F.static_item("form_skill" => "math.fractions-operations", "form" => [ "reduced" ]))
    assert_includes codes(outside), "W-FORM-SKILL-CLOSURE"
    inside = run_item(F.static_item("form_skill" => F::PREREQ, "form" => [ "reduced" ]))
    assert_not_includes codes(inside), "W-FORM-SKILL-CLOSURE"
  end

  test "E-MATCHING-RIGHT-MARKUP: LaTeX in the right column" do
    left = (1..4).map { |i| { "id" => "l#{i}", "text" => "sinistra #{i}" } }
    right = ->(text) { (1..5).map { |i| { "id" => "r#{i}", "text" => i == 1 ? text : "destra #{i}" } } }
    build = lambda do |text|
      answer = { "l1" => "r1", "l2" => "r2", "l3" => "r3", "l4" => "r4" }
      inst = { "display" => { "stem_it" => "Abbina.", "left" => left, "right" => right.call(text) }, "answer" => answer,
               "errors" => [ { "code" => "swap", "value" => answer.to_a.reverse.to_h } ],
               "solution" => { "steps" => [ { "text_it" => "Abbina." } ], "final" => "fatto" } }
      F.static_item("component" => "matching", "instances" => [ inst, inst.merge("display" => inst["display"].merge("stem_it" => "Abbina ancora.")) ],
                    "error_catalogue" => [ { "code" => "swap", "description_it" => "Scambio.", "message_it" => "Controlla.", "implicates" => [] } ],
                    "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" })
    end
    assert_includes codes(run_item(build.call("$x \\leq 2$"))), "E-MATCHING-RIGHT-MARKUP"
    assert_not_includes codes(run_item(build.call("x ≤ −2"))), "E-MATCHING-RIGHT-MARKUP"
  end
end
