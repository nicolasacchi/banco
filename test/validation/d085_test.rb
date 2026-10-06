require "test_helper"
require_relative "../support/validation_fixtures"

# D-085: per-instance tests; the graph readability warning.
class D085Test < ActiveSupport::TestCase
  F = ValidationFixtures

  def run_item(item) = Validation::ItemRunner.new(files: F.files_for(item), context: F.context).call
  def codes(result) = result.findings.map(&:code).uniq

  def inst(key, stem, accept: nil, tests: nil)
    i = { "display" => { "stem_it" => stem }, "answer" => key,
          "errors" => [ { "code" => "sign_error", "value" => "indeterminata" } ],
          "solution" => { "steps" => [ { "text_it" => "Isola l'incognita." } ], "final" => "fatto" } }
    i["accept"] = accept if accept
    i["tests"] = tests if tests
    i
  end

  def item(instances)
    F.static_item({ "component" => "normalized_text", "instances" => instances,
                    "tests" => { "must_accept" => [], "must_reject" => [ "mai" ], "blank" => "invalid" } })
  end

  test "instance tests run on a later instance" do
    ok = item([ inst("zero", "Prima."), inst("impossibile", "Seconda.", accept: [ "e impossibile" ], tests: { "must_accept" => [ "e impossibile" ], "must_reject" => [ "zero" ] }) ])
    result = run_item(ok)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect

    bad = item([ inst("zero", "Prima."), inst("impossibile", "Seconda.", tests: { "must_accept" => [ "e impossibile" ], "must_reject" => [ "impossibile" ] }) ])
    result = run_item(bad)
    assert_includes codes(result), "E-ROUNDTRIP"
    fields = result.findings.select { |f| f.code == "E-ROUNDTRIP" }.map(&:field)
    assert fields.any? { |f| f.include?("/1/tests/must_accept") }, fields.inspect
    assert fields.any? { |f| f.include?("/1/tests/must_reject") }, fields.inspect
  end

  test "a graph error description with a long sentence is W-GRAPH-READABILITY" do
    long = "Scrive a, o, anno al posto di ha, ho, hanno, o mette la h dove non serve: confonde il verbo avere con preposizione, congiunzione o nome."
    skills = [ { "errors" => [ { "description_it" => long } ] } ]
    findings = Validation::Findings.new
    Validation::GraphChecks.readability(skills, findings)
    assert_equal [ "W-GRAPH-READABILITY" ], findings.map(&:code)
    assert findings.none?(&:error?)
  end
end
