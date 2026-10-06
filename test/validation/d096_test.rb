require "test_helper"

# D-096: the optional notes_it of banco.skill_graph/1 and per-skill testlet flags in the blueprint checks.
class D096Test < ActiveSupport::TestCase
  def graph(extra = {})
    { "schema" => "banco.skill_graph/1", "schema_version" => 1, "subject" => "math", "excluded" => [],
      "skills" => [ { "key" => "math.a", "label_it" => "A", "layer" => "core", "scope" => "studied", "prerequisites" => [], "refs" => [ { "role" => "taught_in", "line" => 1 } ], "errors" => [] } ] }.merge(extra)
  end

  def schema_errors(doc)
    JSONSchemer.schema(JSON.parse(Rails.root.join("config/banco/schemas/skill_graph.json").read)).validate(doc).map { |e| e["data_pointer"] }
  end

  test "notes_it is optional, bounded and only strings" do
    assert_not_includes schema_errors(graph("notes_it" => [ "La seconda conta come programma." ])), "/notes_it"
    assert_includes schema_errors(graph("notes_it" => [ 1 ])).join, "/notes_it"
    assert_includes schema_errors(graph("notes_it" => Array.new(11, "x"))), "/notes_it"
  end

  test "a testlet instance is low-guess per skill in the blueprint checks" do
    infos = [ Validation::BlueprintChecks::ItemInfo.new(id: "1", skills: %w[math.a math.b], passed: true,
                                                        instances: (1..6).map { |i| { fingerprint: "f#{i}", low_guess: true, low_guess_by_skill: { "math.a" => false, "math.b" => true } } }) ]
    f = Validation::Findings.new
    Validation::BlueprintChecks.descent_low_guess({ "skill" => "math.a" }, infos, "/descent/0", f)
    assert_equal [ "descent_low_guess" ], f.map { |x| x.detail[:rule] }
    ok = Validation::Findings.new
    Validation::BlueprintChecks.descent_low_guess({ "skill" => "math.b" }, infos, "/descent/0", ok)
    assert_empty ok.to_a
  end
end
