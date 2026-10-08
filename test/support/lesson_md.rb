require "yaml"

# lesson.md text for tests: an invented look-alike (nothing of a real programme or lesson).
# LessonMd.build(front: {"kind" => "ponte"}, sections: {"why_it" => "..."}, drop: ["idea_it"]) gives a valid
# lesson unless told otherwise. Skills: math.demo-equation, math.demo-signed-numbers (see LessonMd.context).
module LessonMd
  FRONT = {
    "schema" => "banco.lesson/1", "key" => "ripasso.math.demo-equations", "kind" => "ripasso", "subject" => "math",
    "title_it" => "Equazioni di primo grado: risolvere e verificare",
    "skills" => [ "math.demo-equation" ], "uses" => [ "math.demo-signed-numbers" ],
    "refs" => [
      { "source" => "seconda-2025-26", "line" => 2, "fragment" => "equazioni di primo grado numeriche", "role" => "needed_by" },
      { "source" => "prima-2025-26", "line" => 1, "fragment" => "equazioni di primo grado", "role" => "taught_in" }
    ],
    "scope" => "studied", "minutes" => 30, "calculator" => false, "finals_it" => [ "x = 3", "x = 2", nil, "x = 3" ]
  }.freeze

  SECTIONS = {
    "why_it" => "Le equazioni servono in quasi ogni problema. Se le sai risolvere, i sistemi diventano facili.",
    "idea_it" => "Una equazione è come una bilancia in equilibrio. Quello che fai a un lato, lo fai anche all'altro.",
    "example_it" => "Risolviamo $3x - 7 = 2$.\n\n1. Porta $-7$ a destra: diventa $+7$.\n2. Dividi per $3$.",
    "mistakes_it" => "- Spostare un termine senza cambiargli il segno.\n- Dividere solo un lato.\n- Dimenticare la verifica.",
    "try" => "1. Risolvi e verifica: $2x + 1 = 7$.\n2. Risolvi: $5x = 10$.\n3. Spiega a parole che cosa è una soluzione.\n4. Risolvi: $x - 4 = -1$.",
    "solutions" => "1. $2x = 6$, quindi $x = 3$.\n2. Dividi per $5$: $x = 2$.\n3. È il valore che rende vera l'uguaglianza.\n4. Porta $-4$ a destra: $x = 3$.",
    "book_it" => "Pagine del libro: le indica il docente.",
    "summary_it" => "- Un termine che cambia lato cambia segno.\n- Si divide tutto per il coefficiente.\n- Si controlla sempre il risultato."
  }.freeze

  HEADINGS = { "why_it" => "Perché ti serve", "idea_it" => "L'idea in breve", "example_it" => "Esempio svolto", "mistakes_it" => "Errori da evitare",
               "try" => "Prova tu", "solutions" => "Soluzioni", "book_it" => "Sul libro", "summary_it" => "In sintesi" }.freeze

  module_function

  def build(front: {}, sections: {}, drop: [], order: nil, extra: "")
    fm = FRONT.merge(front)
    fm = fm.except(*front.select { |_, v| v == :drop }.keys)
    yaml = fm.to_yaml.sub(/\A---\n/, "")
    keys = order || HEADINGS.keys
    body = keys.reject { |k| drop.include?(k) }.map { |k| "## #{HEADINGS[k]}\n#{SECTIONS.merge(sections)[k]}\n" }.join("\n")
    "---\n#{yaml}---\n\n#{body}#{extra}"
  end

  # Skills and sources of the invented course of these tests.
  def context(subject: "math", skills: %w[math.demo-equation math.demo-signed-numbers])
    lines = { [ "seconda-2025-26", 1 ] => "sistemi lineari: metodo di sostituzione", [ "seconda-2025-26", 2 ] => "equazioni di primo grado numeriche intere",
              [ "prima-2025-26", 1 ] => "equazioni di primo grado", [ "prima-2025-26", 2 ] => "PAGINA 2" }
    Validation::Context.new(subject: subject, skill: ->(k) { skills.include?(k) ? { "key" => k, "errors" => [] } : nil },
                            source_line: ->(s, n) { (t = lines[[ s, n ]]) && { text: t, origin: n == 2 && s == "prima-2025-26" ? "transcript" : "pdf" } })
  end
end
