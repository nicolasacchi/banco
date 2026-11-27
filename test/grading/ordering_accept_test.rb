require "test_helper"
require_relative "../support/validation_fixtures"

# Round 8 (D-402): an ordering instance may list alternative right orders in `accept` (a time phrase moved in a sentence built from tiles). The grader
# grades them right with the key's payload; the validator refuses an accepted order that is not a permutation of the answer or is a declared error order.
class OrderingAcceptTest < ActiveSupport::TestCase
  F = ValidationFixtures
  ELEMENTS = %w[e1 e2 e3 e4].map { |id| { "id" => id, "text" => "tile #{id}" } }.freeze

  def spec(accept: [ %w[e2 e1 e3 e4] ], errors: [ { "code" => "en_order", "value" => %w[e4 e3 e2 e1] } ])
    Grading::Spec.from_hash({ "component" => "ordering", "subject" => "english", "skill" => "english.x", "answer" => %w[e1 e2 e3 e4], "accept" => accept, "errors" => errors,
                              "display" => { "elements" => ELEMENTS } })
  end

  test "an accepted alternative order grades correct with the payload of a right order, and says it matched an accept entry" do
    right = Grading::Closed.grade(spec, %w[e2 e1 e3 e4])
    assert_equal "correct", right.verdict
    assert_equal({ "order" => %w[e2 e1 e3 e4], "inverted_pairs" => 0 }, JSON.parse(right.normalized))
    assert_equal({ kind: "accept", value: %w[e2 e1 e3 e4] }, right.matched)
    key = Grading::Closed.grade(spec, %w[e1 e2 e3 e4])
    assert_equal [ "correct", "key" ], [ key.verdict, key.matched[:kind] ]
  end

  test "an order that is neither the key nor accepted is graded as before: a declared error order, or wrong" do
    assert_equal "typical_error", Grading::Closed.grade(spec, %w[e4 e3 e2 e1]).verdict
    assert_equal "wrong", Grading::Closed.grade(spec, %w[e1 e3 e2 e4]).verdict
    assert_equal "wrong", Grading::Closed.grade(spec(accept: []), %w[e2 e1 e3 e4]).verdict
    assert_equal "invalid", Grading::Closed.grade(spec, %w[e1 e1 e3 e4]).verdict
  end

  def instance(accept)
    { "display" => { "stem_it" => "Ordina.", "elements" => ELEMENTS }, "answer" => %w[e1 e2 e3 e4], "accept" => accept, "errors" => [ { "code" => "sign_error", "value" => %w[e4 e3 e2 e1] } ],
      "solution" => { "steps" => [ { "text_it" => "Ragiona." } ], "final" => "Fatto." } }
  end

  def findings(accept)
    unit = Validation::Units::Unit.new(path: "", skill: F::SKILL, component: "ordering", body: { "kind" => "diagnosis_item", "component" => "ordering", "error_catalogue" => [ { "code" => "sign_error" } ] }, generator: false, instances: [])
    Validation::InstanceChecks.new(unit, context: F.context).call(instance(accept), label: "/instances/0")
  end

  test "the validator takes a permutation of the answer and refuses anything else, or an order that is a declared error" do
    assert_empty findings([ %w[e2 e1 e3 e4] ]).select { |f| f.code == "E-GEN-SCHEMA" || f.code == "E-ACCEPT-IS-ERROR" }
    [ [ %w[e1 e2 e3] ], [ %w[e1 e2 e3 e5] ], [ %w[e1 e1 e3 e4] ], [ "e1 e2 e3 e4" ] ].each do |accept|
      hit = findings(accept).select { |f| f.code == "E-GEN-SCHEMA" }
      assert_equal [ "/instances/0/accept/0" ], hit.map(&:field), accept.inspect
    end
    clash = findings([ %w[e4 e3 e2 e1] ]).select { |f| f.code == "E-ACCEPT-IS-ERROR" }
    assert_equal [ "/instances/0/errors/0/value" ], clash.map(&:field)
  end

  test "the item schema allows accept on an ordering instance as lists of ids, up to 20" do
    doc = F.static_item("component" => "ordering", "instances" => [ instance([ %w[e2 e1 e3 e4] ]) ])
    shape = Validation::Findings.new
    Validation::SchemaCheck.call("item", doc, shape)
    assert_empty shape.map(&:to_h).select { |f| f[:field].to_s.include?("accept") }, shape.map(&:to_h).inspect
    too_many = F.static_item("component" => "ordering", "instances" => [ instance(Array.new(21) { %w[e2 e1 e3 e4] }) ])
    shape = Validation::Findings.new
    Validation::SchemaCheck.call("item", too_many, shape)
    assert shape.map(&:to_h).any? { |f| f[:field].to_s.include?("accept") }
  end
end
