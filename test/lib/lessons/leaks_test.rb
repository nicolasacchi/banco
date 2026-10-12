require "test_helper"
require_relative "../../support/lesson2_fixtures"

# Leak rules L4 and L5 on a card (Lessons::Leaks, WAVE2 1.4), with the register of T9 as the figure that prints and the figure that can be made
# to show values. The bad fixture of L4 is test/fixtures/lesson2/bad/check-answer-printed-by-register.md.
class LeaksTest < ActiveSupport::TestCase
  def register(over = {})
    { "type" => "register", "alt_it" => "Un registro di otto bit con i pesi sopra ogni cifra e il valore che si legge sotto.", "view" => "row", "width" => 8, "base" => 2,
      "value" => "11111011", "read" => "twos", "weights" => true, "groups" => 4 }.merge(over)
  end

  def number(answer, over = {}) = { "type" => "check", "n" => 2, "component" => "number", "prompt_it" => "Quanto vale?", "answer" => answer }.merge(over)

  def card(*blocks) = { "n" => 1, "blocks" => blocks.each_with_index.map { |b, i| b.merge("n" => i + 1) } }

  def codes(card) = Lessons::Leaks.card(card, "/cards/0").map(&:code)

  test "L4: an answer a figure prints in any state is a warning, however the minus sign or the groups are written" do
    fig = { "type" => "diagram", "diagram" => register("states" => [ { "value" => "00000101" }, { "value" => "11111011" } ]) }
    assert_equal [ "W-CHECK-ANSWER-IN-DIAGRAM" ], codes(card(fig, number("-5")))
    assert_equal [ "W-CHECK-ANSWER-IN-DIAGRAM" ], codes(card(fig, number("5"))), "the first state prints 5"
    assert_equal [ "W-CHECK-ANSWER-IN-DIAGRAM" ], codes(card(fig, { "component" => "normalized_text", "answer" => "1111 1011" }))
    assert_equal [ "W-CHECK-ANSWER-IN-DIAGRAM" ], codes(card(fig, { "component" => "normalized_text", "answer" => "−128" })), "a weight"
    assert_empty codes(card(fig, number("7")))
  end

  test "no check, no figure, or an answer that is not text: nothing to say" do
    assert_empty codes(card({ "type" => "diagram", "diagram" => register }))
    assert_empty codes(card(number("-5")))
    assert_empty codes(card({ "type" => "diagram", "diagram" => register }, { "component" => "choice", "answer" => "b", "options" => [] }))
  end

  test "a type that is not built answers nothing" do
    stub = { "type" => "network", "alt_it" => "Una rete di tre nodi che si guardano a vicenda e si parlano." }
    assert_empty codes(card({ "type" => "diagram", "diagram" => stub }, number("5")))
  end

  test "L5: a toggling register shows every value of its width, so a check that asks one of them is an error unless it says why not" do
    fig = { "type" => "diagram", "diagram" => register("toggle" => true, "value" => "00000000", "read" => "unsigned", "weights" => false) }
    assert_equal [ "E-CHECK-ANSWER-BY-SIMULATION" ], codes(card(fig, number("200"))), "200 is 11001000, one touch away from nothing at all"
    assert_equal [ "E-CHECK-ANSWER-BY-SIMULATION" ], codes(card(fig, { "component" => "normalized_text", "answer" => "11001000" })), "and so is its digit string"
    assert_empty codes(card(fig, number("200", "reachable_ok_it" => "Il registro mostra i bit, non il perché del prodotto: la domanda è sulla procedura."))), "reachable_ok_it is the way past"
    assert_empty codes(card(fig, number("300"))), "a value the width cannot hold is not reachable"
    twos = { "type" => "diagram", "diagram" => register("toggle" => true, "value" => "00000000", "read" => "twos", "weights" => false) }
    assert_equal [ "E-CHECK-ANSWER-BY-SIMULATION" ], codes(card(twos, number("-56")))
    assert_empty codes(card(twos, number("200")))
  end

  test "L5: a figure that can show more than 500 values on a card with a check is E-DIAGRAM-REACHABLE-CAP" do
    wide = { "type" => "diagram", "diagram" => register("toggle" => true, "width" => 16, "value" => "0" * 16, "read" => "unsigned", "weights" => false) }
    assert_equal [ "E-DIAGRAM-REACHABLE-CAP" ], codes(card(wide, number("5"))).uniq
    assert_empty codes(card(wide)), "without a check there is nothing to give away"
  end

  test "L5: the ring's stepper reaches every code" do
    ring = { "type" => "register", "alt_it" => "La ruota dei sedici codici di quattro bit con il valore senza segno e il puntatore.", "view" => "ring", "width" => 4, "read" => "unsigned", "pointer" => "0010", "step" => true }
    assert_includes codes(card({ "type" => "diagram", "diagram" => ring }, number("13"))), "E-CHECK-ANSWER-BY-SIMULATION"
  end

  test "Run adds the findings to a lesson, at the line of the block, so the bad fixture of L4 is found" do
    f = Lesson2Fixtures
    out = f.check(f.read("bad/check-answer-printed-by-register.md"), "math")
    hit = out.findings.find { |x| x.code == "W-CHECK-ANSWER-IN-DIAGRAM" }
    assert hit
    assert_equal 56, hit.detail[:line]
  end
end
