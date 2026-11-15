require "test_helper"
require_relative "../support/lesson2_fixtures"
require_relative "../support/validation_fixtures"

# W-MATH-SPACE-PUNCT (D-335): a formula that ends in a spacing command right before a mark shows a gap before the mark (lesson 1179:
# `$C_3H_6\;$.`). Lesson/2 texts and the display, solution and hints of an item instance; the page keeps a mark glued to its formula.
class FormulaSpaceTest < ActiveSupport::TestCase
  F = ValidationFixtures
  L = Lesson2Fixtures
  CODE = "W-MATH-SPACE-PUNCT".freeze

  def spaced(text) = Validation::FormulaSpace.spaced(text)

  test "a spacing command at the end of a formula before a mark is found, whatever the command and the mark" do
    [ "\\;", "\\,", "\\:", "\\ ", "\\quad", "\\qquad", "\\; " ].each do |space|
      assert_equal [ "C_3H_6#{space}".strip ], spaced("La molecola $C_3H_6#{space}$."), space.inspect
    end
    assert_equal [ "\\ce{C3H6}\\;" ], spaced("Brucia $\\ce{C3H6}\\;$, poi si spegne.")
    assert_equal [ "x\\," ], spaced("Dov'è ($x\\,$)? Qui.")
    assert_equal [ "a\\;", "b\\quad" ], spaced("$a\\;$. E $b\\quad$?")
  end

  test "a spacing command inside a formula, a formula without one and a space before the mark are quiet" do
    assert_empty spaced("Vale $a\\;b$.")
    assert_empty spaced("Vale $C_3H_6$.")
    assert_empty spaced("Vale $x\\;$ e basta.")
    assert_empty spaced("Vale $x\\;$ .")
    assert_empty spaced("Vale $x\\,$")
    assert_empty spaced("Nessuna formula.")
    assert_empty spaced("Costa 5 \\$ e $x\\quadratic$.")
  end

  def lesson_findings(text)
    findings = Validation::Findings.new
    parsed = L.check(L.read("base.md")).parsed
    parsed.body = Marshal.load(Marshal.dump(parsed.body))
    parsed.body["cards"][1]["blocks"] = [ { "n" => 1, "type" => "text", "line" => 41, "text_it" => text } ] + parsed.body["cards"][1]["blocks"].reject { |b| b["type"] == "text" }
    Validation::Lesson2Checks::Run.new(parsed, "chemistry", L.context("math"), findings).call
    findings.select { |f| f.code == CODE }
  end

  test "a lesson text with the gap warns once, naming the card, the block and the line; without it, quiet" do
    got = lesson_findings("Il propano è $C_3H_6\\;$.")
    assert_equal 1, got.size
    assert_equal "/cards/1/blocks/0/text_it", got.first.field
    assert_match(/\Aline 41: /, got.first.message)
    assert_equal "warning", Validation::Codes.all.fetch(CODE)["severity"]
    assert_empty lesson_findings("Il propano è $C_3H_6$.")
    assert_empty lesson_findings("Il propano è $C_3H_6\\;$ e basta.")
  end

  def unit(component = "number")
    Validation::Units::Unit.new(path: "", skill: F::SKILL, component: component, body: { "kind" => "diagnosis_item" }, generator: false, instances: [])
  end

  def item_findings(inst, component = "number")
    Validation::InstanceChecks.new(unit(component), context: F.context).call(inst, label: "/instances/3").select { |f| f.code == CODE }
  end

  def number(stem, final: "Fatto.", steps: "Ragiona.")
    { "display" => { "stem_it" => stem }, "answer" => "7", "errors" => [], "solution" => { "steps" => [ { "text_it" => steps } ], "final" => final } }
  end

  test "an item stem, step or final with the gap warns at its own path; the same texts without it are quiet" do
    got = item_findings(number("Quanto vale $x+2\\;$?", final: "Vale $7\\,$.", steps: "Calcola $x\\quad$, poi."))
    assert_equal %w[/instances/3/display/stem_it /instances/3/solution/steps/0/text_it /instances/3/solution/final], got.map(&:field).sort_by { |f| [ f.include?("final") ? 2 : f.include?("steps") ? 1 : 0 ] }
    assert(got.all? { |f| f.message.start_with?("/instances/3/") })
    assert_empty item_findings(number("Quanto vale $x+2$?", final: "Vale $7$.", steps: "Calcola $x$, poi."))
  end
end
