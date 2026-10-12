require "test_helper"
require "minitest/mock"
require_relative "../support/lesson2_fixtures"
require_relative "../support/lesson_checks_wave2_world"

# The semantic checks of the wave 2 check components and the truth rules (WAVE2 1.1, 1.4, 2.11): tiles, ordering, select,
# verify (E-LESSON-VERIFY), the select figure's alt text and styles (L3), what a card's figures print (L4) and show (L5).
class LessonChecksWave2Test < ActiveSupport::TestCase
  include LessonChecksWave2World
  F = Lesson2Fixtures

  def run_check(check, subject: "english", path: "/cards/1/blocks/0")
    findings = Validation::Findings.new
    ctx = Lessons::Blocks::Context.new(subject: subject, findings: findings)
    ctx.at(path, 7) { Lessons::Blocks::Check.check(check, ctx) }
    findings.map { |f| [ f.code, f.field ] }
  end

  def codes(list) = list.map(&:first)

  test "a good tiles check passes; the answer must use tile ids, once each, and leave a distractor" do
    assert_empty run_check(TILES)
    assert_includes run_check(TILES.merge("answer" => %w[a b zz])), [ "E-LESSON-CHECK", "/cards/1/blocks/0/answer" ]
    assert_includes run_check(TILES.merge("answer" => %w[a a b])), [ "E-LESSON-CHECK", "/cards/1/blocks/0/answer" ]
    all = TILES.merge("answer" => TILES["tiles"].map { |t| t["id"] })
    assert_includes run_check(all), [ "E-LESSON-CHECK", "/cards/1/blocks/0/tiles" ], "no distractor"
    assert_includes run_check(TILES.merge("accept" => [ TILES["answer"] ])), [ "E-LESSON-CHECK", "/cards/1/blocks/0/accept/0" ]
    assert_includes run_check(TILES.merge("errors" => [ { "answer" => TILES["answer"], "message_it" => "x" } ])), [ "E-LESSON-CHECK", "/cards/1/blocks/0/errors/0/answer" ]
  end

  test "a tile has exactly one language, and a check's tiles are in one language" do
    two = TILES.merge("tiles" => TILES["tiles"].dup.tap { |t| t[0] = { "id" => "a", "text_en" => "If", "text_it" => "Se" } })
    assert_includes run_check(two), [ "E-LESSON-CHECK", "/cards/1/blocks/0/tiles/0" ]
    mixed = TILES.merge("tiles" => TILES["tiles"].dup.tap { |t| t[0] = { "id" => "a", "text_es" => "Si" } })
    assert_includes codes(run_check(mixed)), "E-LESSON-LANG"
  end

  test "a sentence to build that stands in its own prompt is W-CHECK-ANSWER-IN-PROMPT" do
    leaky = TILES.merge("prompt_it" => "Costruisci: If it rains I will stay.")
    assert_includes codes(run_check(leaky)), "W-CHECK-ANSWER-IN-PROMPT"
  end

  test "an ordering check puts every item once; an error is a permutation that is not the answer" do
    assert_empty run_check(ORDERING, subject: "law_economics")
    assert_includes run_check(ORDERING.merge("answer" => %w[p q r]), subject: "law_economics"), [ "E-LESSON-CHECK", "/cards/1/blocks/0/answer" ]
    same = ORDERING.merge("errors" => [ { "answer" => %w[p q r s], "message_it" => "x" } ])
    assert_includes run_check(same, subject: "law_economics"), [ "E-LESSON-CHECK", "/cards/1/blocks/0/errors/0/answer" ]
  end

  # ---- select ----------------------------------------------------------------------------------------

  Fake = FakeFigure

  def with_fake(&) = Lessons::Diagrams.stub(:module_for, ->(type) { type == "network" ? Fake : nil }, &)

  test "a select check names a set the figure's type declares and targets it offers" do
    with_fake do
      assert_empty run_check(select_check)
      assert_includes run_check(select_check.merge("targets" => "levels")), [ "E-LESSON-CHECK", "/cards/1/blocks/0/targets" ]
      assert_includes run_check(select_check(answer: %w[n2 n9])), [ "E-LESSON-CHECK", "/cards/1/blocks/0/answer" ]
      assert_includes run_check(select_check(answer: %w[n1 n2 n3 n4 n5])), [ "E-LESSON-CHECK", "/cards/1/blocks/0/answer" ]
      bad = select_check.merge("errors" => [ { "answer" => %w[n2 n4], "message_it" => "x" } ])
      assert_includes run_check(bad), [ "E-LESSON-CHECK", "/cards/1/blocks/0/errors/0/answer" ]
    end
  end

  test "a select figure of a type with no targets yet is refused with a reason" do
    without_targets { assert_includes run_check(select_check), [ "E-LESSON-CHECK", "/cards/1/blocks/0/targets" ] }
  end

  test "the alt text or caption of a select figure that names an answer is E-CHECK-ANSWER-IN-ALT" do
    with_fake do
      assert_includes codes(run_check(select_check(alt: "Il nucleoide è il cerchio al centro della cellula."))), "E-CHECK-ANSWER-IN-ALT"
      assert_includes codes(run_check(select_check(alt: "Una cellula con ribosomi sparsi."))), "E-CHECK-ANSWER-IN-ALT"
      assert_not_includes codes(run_check(select_check(alt: "Una cellula con cinque parti."))), "E-CHECK-ANSWER-IN-ALT"
    end
  end

  module Marked
    extend Lessons::Diagrams::Contract

    module_function

    def targets(data, set) = Fake.targets(data, set)

    def target_names(*) = {}

    def select_signatures(_data, _set) = { "n1" => "plain", "n2" => "plain", "n3" => "labelled", "n4" => "plain", "n5" => "plain" }
  end

  test "candidates drawn in different styles are E-SELECT-MARKED" do
    Lessons::Diagrams.stub(:module_for, ->(_t) { Marked }) do
      assert_includes codes(run_check(select_check)), "E-SELECT-MARKED"
    end
    with_fake { assert_not_includes codes(run_check(select_check)), "E-SELECT-MARKED" }
  end

  # ---- verify ----------------------------------------------------------------------------------------

  def verified(answer, errors: [], fn: "test.sum", args: { "a" => "2", "b" => "3" })
    { "component" => "number", "prompt_it" => "Quanto?", "answer" => answer, "errors" => errors, "verify" => { "fn" => fn, "args" => args } }
  end

  setup do
    Lessons::Verify.reset!
    Lessons::Verify.register("test.sum", mutants: ->(a) { { "off_by_one" => (a["a"].to_i + a["b"].to_i + 1).to_s } }) { |a| a["a"].to_i + a["b"].to_i }
  end

  teardown { Lessons::Verify.reset! }

  test "verify holds when the function gives the answer; it names the difference when it does not" do
    assert_empty run_check(verified("5"), subject: "math")
    assert_includes codes(run_check(verified("6"), subject: "math")), "E-LESSON-VERIFY"
    assert_includes codes(run_check(verified("5", fn: "test.nothing"), subject: "math")), "E-LESSON-VERIFY"
  end

  test "a coded wrong answer that the function knows as a mutant must carry the mutant's value" do
    good = verified("5", errors: [ { "answer" => "6", "code" => "off_by_one", "message_it" => "Uno in più." } ])
    assert_empty run_check(good, subject: "math")
    bad = verified("5", errors: [ { "answer" => "7", "code" => "off_by_one", "message_it" => "Uno in più." } ])
    assert_includes run_check(bad, subject: "math"), [ "E-LESSON-VERIFY", "/cards/1/blocks/0/errors/0/answer" ]
    other = verified("5", errors: [ { "answer" => "9", "code" => "something_else", "message_it" => "Altro." } ])
    assert_empty run_check(other, subject: "math"), "a code the function does not know is not checked against it"
  end

  test "a library that is not built yet (a contract stub) is reported, not silently passed" do
    check = verified("107", fn: "chrono.duration", args: { "from" => "-133", "to" => "-27" })
    Lessons::Verify.reset!
    list = run_check(check, subject: "math")
    assert_includes codes(list), "E-LESSON-VERIFY"
  end

  test "program functions are the render check's business" do
    check = verified("5", fn: "program.output", args: {})
    assert_empty run_check(check, subject: "math")
  end

  test "the library adapter reads the frozen signature: positional arguments by name, mutants by the same arguments" do
    Lessons::Verify.reset!
    Lessons::Chrono.stub(:duration, ->(from, to) { to.to_i - from.to_i - 1 }) do
      Lessons::Chrono.stub(:mutants, ->(from, to) { { "year_zero_counted" => (to.to_i - from.to_i).to_s } }) do
        args = { "from" => "-133", "to" => "-27" }
        assert_equal 105, Lessons::Verify.resolve("chrono.duration").call.call(args)
        good = verified("105", fn: "chrono.duration", args: args, errors: [ { "answer" => "106", "code" => "year_zero_counted", "message_it" => "x" } ])
        assert_empty run_check(good, subject: "math")
        bad = verified("105", fn: "chrono.duration", args: args, errors: [ { "answer" => "99", "code" => "year_zero_counted", "message_it" => "x" } ])
        assert_includes run_check(bad, subject: "math"), [ "E-LESSON-VERIFY", "/cards/1/blocks/0/errors/0/answer" ]
      end
    end
  end

  # ---- a card's figures against its checks (L4, L5) --------------------------------------------------

  module Printing
    extend Lessons::Diagrams::Contract

    module_function

    def static(*) = nil
    def state(*) = nil
    def across(*) = nil
    def printed(_data, _state) = [ "3", "Anna" ]
    def reachable(_data) = $reachable
  end

  def card_findings(reach: [])
    $reachable = reach
    network = JSON.parse(Rails.root.join("test/fixtures/diagrams/types/network.json").read).fetch("vectors").first.fetch("data")
    Lessons::Diagrams.stub(:module_for, ->(type) { type == "network" ? Printing : nil }) do
      list = F.check(F.read("base.md")).parsed
      list.body = Marshal.load(Marshal.dump(list.body))
      card = list.body["cards"].find { |c| c["blocks"].any? { |b| b["type"] == "check" && b["component"] == "number" } }
      card["blocks"].unshift({ "n" => 9, "type" => "diagram", "line" => 1, "diagram" => network })
      card["blocks"].each_with_index { |b, i| b["n"] = i + 1 }
      findings = Validation::Findings.new
      Validation::Lesson2Checks::Run.new(list, "math", F.context("math"), findings).call
      findings.map { |f| [ f.code, f.field ] }
    end
  ensure
    $reachable = nil
  end

  test "a number check whose answer a figure of the card prints is W-CHECK-ANSWER-IN-DIAGRAM" do
    assert_includes card_findings.map(&:first), "W-CHECK-ANSWER-IN-DIAGRAM"
  end

  test "an answer a figure's controls can show is E-CHECK-ANSWER-BY-SIMULATION unless reachable_ok_it says why" do
    assert_includes card_findings(reach: %w[2 3 4]).map(&:first), "E-CHECK-ANSWER-BY-SIMULATION"
    assert_not_includes card_findings(reach: %w[8 9]).map(&:first), "E-CHECK-ANSWER-BY-SIMULATION"
  end

  test "a figure that can show more than 500 values on a card with a check is E-DIAGRAM-REACHABLE-CAP" do
    assert_includes card_findings(reach: :over_cap).map(&:first), "E-DIAGRAM-REACHABLE-CAP"
  end
end
