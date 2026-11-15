require "test_helper"

# W-BLANK-STEP-DATUM (Lessons::Blocks::Example.blank_data): the page never shows the do_it of a blank step, so a number or a cell
# reference only that do_it gives is a datum the student cannot know. The case of lesson revision 1072 (sheet-formula-errors).
class BlankDatumTest < ActiveSupport::TestCase
  Collector = Struct.new(:found) do
    def at(*, **) = yield
    def add(code, sub, message, **) = found << [ code, sub, message ]
    def path = "/cards/0/blocks/1"
  end

  def example(steps, over = {}) = { "type" => "example", "n" => 2, "problem_it" => "In C3 compare un errore.", "steps" => steps, "result_it" => "Fatto." }.merge(over)

  def blank(over = {}) = { "component" => "number", "prompt_it" => "Che numero compare in C3?", "answer" => "5", "errors" => [], "explain_it" => "40 diviso 8 fa 5." }.merge(over)

  def card(*blocks) = { "n" => 1, "title_it" => "Esempio", "blocks" => blocks }

  def findings(card)
    out = Collector.new([])
    Lessons::Blocks::Example.blank_data(card, "/cards/0", out)
    out.found
  end

  STEPS = [
    { "do_it" => "Leggi il codice in C3.", "why_it" => "Dice che c'è una divisione per zero." },
    { "do_it" => "B3 è vuota: per Calc vale 0.", "why_it" => "Una cella vuota è come uno zero." }
  ].freeze

  test "a number only the hidden do_it of the blank step gives fires, once, on that do_it" do
    step = { "do_it" => "Scrivi 8 in B3.", "why_it" => "Ora il divisore non è zero.", "blank" => blank }
    found = findings(card(example(STEPS + [ step ])))
    assert_equal 1, found.size
    code, sub, message = found.first
    assert_equal "W-BLANK-STEP-DATUM", code
    assert_equal "steps/2/do_it", sub
    assert_match(/gives 8\b/, message)
    assert_no_match(/B3/, message, "B3 is said by an earlier step")
  end

  test "a datum a visible place already gives is quiet: an earlier step, the problem, the question, the card, the answer itself" do
    step = { "do_it" => "Scrivi 8 in B3.", "why_it" => "Ora il divisore non è zero.", "blank" => blank }
    assert_empty findings(card(example(STEPS + [ { "do_it" => "Scegli 8 come divisore.", "why_it" => "Non è zero." }, step ])))
    assert_empty findings(card(example(STEPS + [ step ], "problem_it" => "In C3 compare un errore: scrivi 8 in B3.")))
    assert_empty findings(card(example(STEPS + [ step.merge("blank" => blank("prompt_it" => "Con 8 in B3, che numero compare in C3?")) ])))
    table = { "type" => "table", "n" => 1, "rows" => [ [ "2", "24", "8" ] ] }
    assert_empty findings(card(table, example(STEPS + [ step ])))
    assert_empty findings(card(example(STEPS + [ { "do_it" => "Il risultato è 5.", "why_it" => "Il conto fa 5.", "blank" => blank } ]))), "the blank's own answer stays hidden on purpose"
  end

  test "numbers inside a formula or a span are working, not a datum: quiet" do
    found = findings(card(example(STEPS + [ { "do_it" => "$x = 8$ e [[code:#DIV/0!]] in B9.", "why_it" => "Serve.", "blank" => blank } ])))
    assert_equal 1, found.size
    assert_match(/gives B9, which/, found.first[2], "only B9, said in words, is a datum")
    assert_empty findings(card(example(STEPS + [ { "do_it" => "$3 - 2 = 1$", "why_it" => "Serve.", "blank" => blank } ])))
  end

  test "ordinary words, a step without a blank and a blank without numbers are quiet; a cell reference fires, a decimal comma is one number" do
    assert_empty findings(card(example(STEPS + [ { "do_it" => "Scrivi il numero giusto.", "why_it" => "Serve un divisore.", "blank" => blank } ])))
    assert_empty findings(card(example(STEPS + [ { "do_it" => "Scrivi 8 in B3.", "why_it" => "Ora il divisore non è zero." } ])))
    found = findings(card(example(STEPS + [ { "do_it" => "Copia la formula in D7 e scrivi 2,5.", "why_it" => "Serve.", "blank" => blank } ])))
    assert_equal 1, found.size
    assert_match(/D7, 2\.5/, found.first[2])
    assert_empty findings(card(example(STEPS + [ { "do_it" => "Scrivi 2,5 in D7.", "why_it" => "Serve.", "blank" => blank("prompt_it" => "D7 vale 2.5: che numero compare in C3?") } ])))
  end
end
