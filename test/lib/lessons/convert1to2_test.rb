require "test_helper"
require_relative "../../support/lesson_md"
require_relative "../../support/lesson2_fixtures"

# Lessons::Convert1to2 (A15.1): the old lesson, kept in cards; nothing invented, so the draft fails on exactly what the author adds.
class LessonsConvert1to2Test < ActiveSupport::TestCase
  L = LessonMd

  SECTIONS = {
    "why_it" => "Le equazioni servono in quasi ogni problema. Se le sai risolvere, i sistemi diventano facili.",
    "idea_it" => "**La bilancia**: una equazione è come una bilancia in equilibrio. Quello che fai a un lato, lo fai anche all'altro.\n\n" \
                 "**Il metodo** in quattro passi:\n\n1. Sviluppa le parentesi.\n2. Porta le $x$ a sinistra.\n3. Somma i termini simili.\n4. Dividi per il coefficiente.\n\n" \
                 "Ricorda che il segno cambia quando un termine cambia lato.",
    "example_it" => "Risolviamo $3x - 7 = 2$.\n\n1. Porta $-7$ a destra: diventa $+7$. Perché: un termine che cambia lato cambia segno.\n2. Dividi per $3$: $x = 3$. Perché: $3x$ è 3 volte $x$.",
    "mistakes_it" => "- ✗ $2x - 3 = 7 \\to 2x = 7 - 3$ ✓ $2x = 7 + 3$. Spostando, $-3$ diventa $+3$.\n- ✗ $3x = 9 \\to x = 9 - 3$ ✓ $x = 9 : 3$ Il 3 moltiplica la $x$.\n- Dimenticare la verifica.",
    "try" => "Fai i conti sul quaderno.\n\n1. Risolvi e verifica: $3x - 7 = 2$.\n2. Risolvi: $5x = 10$.\n3. Spiega a parole che cosa è una soluzione.\n4. Risolvi: $x - 4 = -1$.",
    "solutions" => "1. $3x = 9$, quindi $x = 3$.\n2. Dividi per $5$: $x = 2$.\n3. È il valore che rende vera l'uguaglianza.\n4. Porta $-4$ a destra: $x = 3$.",
    "book_it" => "Pagine del libro: le indica il docente. Cerca equazioni di primo grado.",
    "summary_it" => "- Un termine che cambia lato cambia segno.\n- Si divide tutto per il coefficiente.\n- Si controlla sempre il risultato."
  }.freeze

  def v1 = L.build(sections: SECTIONS)

  def v2 = Lessons::Convert1to2.call(v1)

  # The draft with the goals the author adds, so that its body can be read.
  def with_goals = v2.sub("# goals_it:", "goals_it: ['**Risolvere** una equazione']\n# goals_it:")

  def body = Lessons::Parser2.call(with_goals, Validation::Findings.new).body

  def check(md) = Validation::LessonChecks.call(md, subject: "math", context: L.context)

  test "the draft is a banco.lesson/2 file that parses into cards" do
    parsed = Lessons::Parser2.call(with_goals, Validation::Findings.new)
    assert_not_nil parsed.body, "the draft parses (the schema of its blocks holds)"
    roles = parsed.body["cards"].map { |c| c["role"] }
    assert_equal %w[idea idea idea example mistakes try summary], roles
    assert_equal "banco.lesson/2", parsed.body["schema"]
  end

  test "the why, the book words and the front matter are kept; the finals move into the try block" do
    text = v2
    front = YAML.safe_load(text[/\A---\n(.*?)\n---\n/m, 1])
    assert_equal SECTIONS["why_it"], front["why_it"]
    assert_equal "Cerca equazioni di primo grado.", front["book_it"]
    assert_equal "ripasso.math.demo-equations", front["key"]
    assert_not front.key?("finals_it")
    assert_not front.key?("goals_it"), "the old lesson has no goals: the author writes them"
    try = body["cards"].find { |c| c["role"] == "try" }["blocks"].first
    assert_equal 4, try["exercises"].size
    assert_equal "x = 3", try["exercises"][0]["final_it"]
    assert_nil try["exercises"][2]["final_it"]
    assert_equal "Fai i conti sul quaderno.", try["intro_it"]
    assert_equal "$3x = 9$, quindi $x = 3$.", try["exercises"][0]["solution_it"]
  end

  test "idea cards are cut at bold heads and numbered lists, titled by their own words" do
    titles = body["cards"].select { |c| c["role"] == "idea" }.map { |c| c["title_it"] }
    assert_equal [ "La bilancia", "Il metodo", "Ricorda che il segno cambia quando" ], titles
    assert_includes body["cards"][1]["blocks"].first["text_it"], "1. Sviluppa le parentesi."
  end

  test "the worked example becomes an example block whose steps have their reasons" do
    ex = body["cards"].find { |c| c["role"] == "example" }["blocks"].first
    assert_equal "example", ex["type"]
    assert_equal "Risolviamo $3x - 7 = 2$.", ex["problem_it"]
    assert_equal "Porta $-7$ a destra: diventa $+7$.", ex["steps"][0]["do_it"]
    assert_equal "un termine che cambia lato cambia segno.", ex["steps"][0]["why_it"]
  end

  test "mistakes with ✗ and ✓ become mistake blocks; one without stays as text" do
    card = body["cards"].find { |c| c["role"] == "mistakes" }
    mistakes = card["blocks"].select { |b| b["type"] == "mistake" }
    assert_equal 2, mistakes.size
    assert_equal "$2x - 3 = 7 \\to 2x = 7 - 3$", mistakes[0]["wrong_it"]
    assert_equal "$2x = 7 + 3$", mistakes[0]["right_it"]
    assert_equal "Spostando, $-3$ diventa $+3$.", mistakes[0]["why_it"]
    assert_equal "text", card["blocks"].first["type"]
    assert_includes card["blocks"].first["text_it"], "Dimenticare la verifica."
  end

  test "without goals the draft fails the front matter schema: the author writes them" do
    assert_includes check(v2).findings.errors.map(&:code), "E-SCHEMA"
  end

  test "with goals added the remaining errors are the visuals, the checks and the map, nothing else" do
    findings = check(with_goals).findings
    wanted = %w[E-CARD-NO-VISUAL E-LESSON-MAP E-LESSON-CHECKS]
    unexpected = findings.errors.map(&:code).uniq - wanted
    assert_empty unexpected, "unexpected: #{findings.errors.select { |f| unexpected.include?(f.code) }.map { |f| [ f.code, f.field, f.message ] }.inspect}"
    assert_equal wanted.sort, (findings.errors.map(&:code).uniq & wanted).sort
  end

  test "a lesson that does not parse as banco.lesson/1 is refused" do
    assert_raises(Lessons::Convert1to2::Refused) { Lessons::Convert1to2.call("niente") }
  end

  test "the converter writes no text of its own: every word of the draft is in the old lesson" do
    old_words = v1.downcase.scan(/[\p{L}\p{N}']+/).to_set
    new_text = v2.sub(/^# goals_it:.*\n/, "")
    texts = body["cards"].flat_map { |c| [ c["title_it"] ] + Lessons::Blocks.each_block(c).flat_map { |b, _| Lessons::Blocks.markup_fields(b).map { |_, t, _| t } } }
    invented = texts.flat_map { |t| t.to_s.downcase.scan(/[\p{L}']+/) }.reject { |w| old_words.include?(w) }
    assert_empty invented.uniq
    assert_not_includes new_text, "TODO"
  end
end
