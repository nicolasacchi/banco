require "test_helper"

# E-ACCEPTS-RANDOM must not fire for a random answer that is the key written another way (D-080).
class RoundtripRandomTest < ActiveSupport::TestCase
  def unit(forms = [])
    body = { "component" => "expression", "skill" => "s", "form" => forms }
    Validation::Units::Unit.new(path: "", skill: "s", component: "expression", body: body, generator: false, instances: [])
  end

  def inst = { "display" => { "stem_it" => "Semplifica." }, "answer" => { "latex" => "x+4", "unknown" => nil }, "errors" => [] }

  def run_with(candidate)
    findings = Validation::Findings.new
    rt = Validation::Roundtrip.new(unit, subject: "math", findings: findings)
    rt.stub(:random_candidate, ->(_rng) { candidate }) { rt.call([ inst ], label: "x") }
    findings.map(&:code)
  end

  test "1(x+4) and 1x+4 equal the key in value and are not flagged" do
    assert_not_includes run_with({ raw: "1(x+4)", value: "1(x+4)" }), "E-ACCEPTS-RANDOM"
    assert_not_includes run_with({ raw: "1x+4", value: "1x+4" }), "E-ACCEPTS-RANDOM"
  end

  test "equal_in_value? is false for a different value" do
    rt = Validation::Roundtrip.new(unit, subject: "math", findings: Validation::Findings.new)
    assert rt.send(:equal_in_value?, inst, "1(x+4)")
    assert_not rt.send(:equal_in_value?, inst, "2x+4")
  end
end
