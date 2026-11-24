require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/lesson2_fixtures"

# D-402, round 4 of the tooling (slice A): what the first eight topics of the rewritten courses met. Each rule that was narrowed has its false positive and, next to it,
# the true positive it keeps. The lessons are the golden ones of test/fixtures/lang with one edit each; the words are checked in Validation::Bilingual directly.
class BilingualToolingFourTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  VB = Validation::Bilingual
  CHECK_CODES = %w[W-LANG-LEVEL W-ABSOLUTE W-CHECK-ANSWER-IN-PROMPT E-READ E-LANG-PAIR-ORPHAN E-LANG-PAIR-MISSING E-LANG-TRANSLATION-COPY E-SCHEMA E-LESSON-BLOCK].freeze

  def es = DIR.join("lesson_es_figures.md").read
  def en = DIR.join("lesson_en_figures.md").read
  def check(md, subject) = Validation::LessonChecks.call(md, subject: subject, context: F.context(subject))
  def found(outcome, *codes) = outcome.findings.select { |f| codes.include?(f.code) }
  def level_words(outcome) = found(outcome, "W-LANG-LEVEL").flat_map { |f| f.detail[:words].to_a }

  DIALOGUE = <<~Y.freeze
    ::: dialogue
    title_it: "Ascolta Ana y Luis"
    speakers:
      - {id: a, name: "Ana", voice: 1}
      - {id: l, name: "Luis", voice: 2}
    transcript: shown
    lines:
      - {speaker: a, text_es: "¿Me das el libro?", gloss_it: "Mi dai quel quaderno grandissimo, per favore, adesso?"}
      - {speaker: l, text_es: "Sí, ahora.", gloss_it: "Sì, subito."}
    :::

    ::: check select
  Y

  # ---- reserved types ----------------------------------------------------------------------------------------------------------------

  TILES = <<~Y.freeze
    ::: check tiles
    prompt_en: "Build the question."
    prompt_it: "Costruisci la domanda."
    tiles:
      - {id: a, text_en: "Has"}
      - {id: b, text_en: "she"}
      - {id: c, text_en: "got"}
      - {id: d, text_en: "a dog?"}
      - {id: e, text_en: "have"}
    answer: [a, b, c, d]
    explain_en: "Has comes first."
    explain_it: "Has viene per primo."
    :::

    ::: check choice
  Y

  # config/banco/lesson_types.yml is the source of truth for the dry run: tiles and select are `available` there since the checks of T1 landed, so the dry run takes
  # them without --allow-reserved; the subject briefs listed them as reserved (a stale table).
  test "tiles is an available check: a bilingual lesson with one passes the dry run with no hold-back finding" do
    assert Lessons::Types.available?(:check, "tiles")
    assert Lessons::Types.available?(:check, "select")
    outcome = check(en.sub("::: check choice\n", TILES), "english")
    assert_empty outcome.findings.select { |f| f.code == "W-TYPE-RESERVED" || f.message.match?(/not (?:yet )?available|non ancora/) }.map { |f| [ f.code, f.message ] }
    assert_empty found(outcome, "E-LESSON-BLOCK", "E-SCHEMA", "E-LESSON-CHECK").map { |f| [ f.code, f.field, f.message ] }
  end

  # ---- the level -------------------------------------------------------------------------------------------------------------------

  test "the Italian gloss of a dialogue line is not read for the level as if it were Spanish; the Spanish line still is" do
    clean = check(es.sub("::: check select\n", DIALOGUE), "spanish")
    assert_empty found(clean, "W-LANG-LEVEL").select { |f| f.field.match?(/gloss_/) }.map { |f| [ f.field, f.detail[:words] ] }
    assert_not_includes level_words(clean), "grandissimo"
    odd = check(es.sub("::: check select\n", DIALOGUE.sub("¿Me das el libro?", "¿Me das el brujulón?")), "spanish")
    assert_includes level_words(odd), "brujulón", "the Spanish text of the line keeps its level check"
  end

  test "a [[es:..]] span in the Italian text is a form quoted on purpose: no level word, while the target text keeps its check" do
    italian = es.sub("Come in italiano, la voce batte più forte su una [[g:sillaba]].", "Come in italiano, la voce batte più forte su una [[g:sillaba]], non su [[es:fantasmagoría]].")
    assert_not_includes level_words(check(italian, "spanish")), "fantasmagoría"
    target = es.sub("Como en italiano, la voz suena más fuerte en una [[g:sílaba]].", "Como en italiano, la voz suena más fuerte en una [[g:sílaba]], no en fantasmagoría.")
    assert_includes level_words(check(target, "spanish")), "fantasmagoría"
  end

  test "a topic of english or spanish may list teaches_en|es, and the words of its intro are then no level word" do
    subject = Struct.new(:key).new("spanish")
    topic = { "key" => "topic.spanish.x", "bilingual" => true, "intro_es" => "Hoy vemos la fantasmagoría.", "intro_it" => "Oggi vediamo la fantasmagoria." }
    run = lambda do |doc|
      Validation::Findings.new.tap { |findings| Validation::TopicChecks.language(doc, subject, findings) }.select { |f| f.code == "W-LANG-LEVEL" }.flat_map { |f| f.detail[:words].to_a }
    end
    assert_includes run.call(topic), "fantasmagoría"
    assert_empty run.call(topic.merge("teaches_es" => [ "fantasmagoría" ]))
    derived = Banco::Schemas::Bilingual.derive(Banco::Schemas.read("topic"), "topic")
    %w[teaches_en teaches_es].each { |key| assert_equal "array", derived.dig("properties", key, "type") }
    assert_not Banco::Schemas.read("topic").fetch("properties").key?("teaches_es"), "the file is not changed"
  end

  # ---- word_parts, decode view -----------------------------------------------------------------------------------------------------

  DECODE = <<~Y.freeze
    ::: diagram word_parts
    alt_es: "La palabra descubrir en dos piezas: des quita y cubrir tapa."
    alt_it: "La parola descubrir in due pezzi: des toglie e cubrir copre."
    view: decode
    words:
      - form_es: 'des|cubrir'
    %<gloss>s
    :::

    ::: check select
  Y

  def decode(gloss) = es.sub("::: check select\n", format(DECODE, gloss: gloss.lines.map { |l| "    #{l}" }.join.chomp))

  test "the Italian parts and meaning of a decode word stand alone: a gloss for the student, like label_it" do
    outcome = check(decode(%(parts_it: ["togliere", "coprire"]\nmeaning_it: "scoprire")), "spanish")
    assert_empty found(outcome, "E-LANG-PAIR-ORPHAN", "E-LANG-PAIR-MISSING", "E-SCHEMA", "E-LESSON-BLOCK").map { |f| [ f.code, f.field, f.message ] }
  end

  test "a target pair of parts and meaning must be complete on both sides; an Italian list of another length is a missing entry" do
    both = check(decode(%(parts_es: ["quitar", "tapar"]\nparts_it: ["togliere", "coprire"]\nmeaning_es: "abrir"\nmeaning_it: "scoprire")), "spanish")
    assert_empty found(both, "E-LANG-PAIR-ORPHAN", "E-LANG-PAIR-MISSING", "E-SCHEMA", "E-LESSON-BLOCK").map { |f| [ f.code, f.field ] }
    only_target = check(decode(%(parts_es: ["quitar", "tapar"]\nparts_it: ["togliere"]\nmeaning_es: "abrir"\nmeaning_it: "scoprire")), "spanish")
    assert_equal [ "E-LANG-PAIR-MISSING" ], found(only_target, "E-LANG-PAIR-ORPHAN", "E-LANG-PAIR-MISSING").map(&:code).uniq
    no_italian = check(decode(%(parts_es: ["quitar", "tapar"]\nparts_it: ["togliere", "coprire"]\nmeaning_es: "abrir")), "spanish")
    assert_includes found(no_italian, "E-LANG-PAIR-MISSING").map(&:field).join, "meaning_es"
  end

  test "an Italian parts_it with no word to gloss (no form_es beside it) is still an orphan" do
    pairs = Lessons::Bilingual.pairs({ "parts_it" => [ "x" ] }, "es").map { |pointer, base, target, _| [ pointer, base, target ] }
    assert_equal [ [ "/parts_es/0", "parts", nil ] ], pairs
  end

  # ---- the sentence caps ----------------------------------------------------------------------------------------------------------

  def long(text, lang = "es") = VB.target_report(lang, text)[:long]

  test "the 12-word cap does not count a quotation, a single letter or a piece of a word" do
    assert_equal 2, long("Escribe «Ella canta muy bien en la casa de su madre y de su padre hoy» ahora.")
    assert_equal 9, long("Con «e» pasa a «ie» y «o» pasa a «ue» en la raíz")
    assert_equal 10, long("Con -es el plural cambia y la palabra «lápiz» pierde la tilde")
    assert_equal 14, long("Ella canta muy bien en la casa de su madre y de su padre"), "fourteen plain words are fourteen"
    assert_equal 13, long("Escribe «hola» y luego la palabra que falta en la frase de hoy ahora")
  end

  test "a colon ends a sentence for the cap when a quote, a capital letter or a span follows, or when a closing quote comes before it" do
    assert_equal 11, long("Escribe aquí la forma del verbo que falta en la frase: Ella canta muy bien en la casa de mi madre hoy")
    assert_equal 8, long("Escribe la forma que falta en la frase: «ella canta muy bien en la casa de mi madre hoy»")
    assert_equal 12, long("Mira la forma del verbo: [[es:cantamos]] muy bien en casa de mi madre hoy por la tarde")
    assert_equal 12, long("Mira la forma del verbo:  m  muy bien en casa de mi madre hoy por la tarde"), "a span as a lesson's text layer hands it over"
    assert_equal 9, long("«Ella canta muy bien en casa.»: lleva tilde en la última sílaba de la frase")
    assert_equal 9, long("«Ella canta muy bien en casa.» : lleva tilde en la última sílaba de la frase")
    assert_equal 19, long("Escribe la forma que falta en la frase: ella canta muy bien en la casa de mi madre hoy"), "a colon before a plain word does not split"
  end

  test "an Italian note to the teacher may quote a sentence of the language: «...» is not counted" do
    note = "La frase «Ella canta muy bien en la casa de su madre y de su padre cada tarde» porta la tilde, come mostra la regola del libro."
    quoted = Validation::Findings.new
    Validation::Readability.lint_document({ "note_it" => note }, "", quoted, codes: true)
    assert_empty quoted.select { |f| f.code == "E-READ" }.map(&:to_h)
    plain = Validation::Findings.new
    Validation::Readability.lint_document({ "note_it" => note }, "", plain)
    assert_equal [ "sentence_length" ], plain.select { |f| f.code == "E-READ" }.map { |f| f.detail[:rule] }
    unquoted = Validation::Findings.new
    Validation::Readability.lint_document({ "note_it" => note.delete("«»") }, "", unquoted, codes: true)
    assert_equal [ "sentence_length" ], unquoted.select { |f| f.code == "E-READ" }.map { |f| f.detail[:rule] }, "the same words with no quote are counted"
  end

  # ---- the copy check -------------------------------------------------------------------------------------------------------------

  test "E-LANG-TRANSLATION-COPY ignores the forms quoted in the Italian text, a step that is all a form and a shared connector" do
    assert_not VB.copy?("hacer: hago", "[[es:hacer]]: [[es:hago]]")
    assert_not VB.copy?("Does Jack study German?", "[[en:Does Jack study German?]]")
    assert_not VB.copy?("la mano", "[[es:la mano]]")
    assert_not VB.copy?("Con «e»", "Con «e»")
    assert_not VB.copy?("Con [[es:pensar]]", "con [[es:pensar]]")
    assert_not VB.copy?("do / do", "do / do")
  end

  test "E-LANG-TRANSLATION-COPY still catches a sentence that was not translated, with or without a span in it" do
    assert VB.copy?("Ella canta en la casa", "Ella canta en la casa")
    assert VB.copy?("Ella canta en la casa", "Ella canta en [[es:la casa]]")
    assert VB.copy?("Does Jack study German?", "Does Jack study [[en:German]]?")
    assert VB.copy?("make / do", "make / do")
  end

  test "the copy check reads a lesson step that is only an English sentence in a span as material, and a copied step as a copy" do
    material = en.sub(%(    do_it: "Trova il soggetto: Jack."), %(    do_it: "[[en:Find the subject: Jack.]]"))
    assert_empty found(check(material.sub(%(do_en: "Find the subject: Jack."), %(do_en: "Find the subject: Jack.")), "english"), "E-LANG-TRANSLATION-COPY").map(&:field)
    copied = en.sub(%(    do_it: "Trova il soggetto: Jack."), %(    do_it: "Find the subject: Jack."))
    assert_equal [ "steps/0/do_it" ], found(check(copied, "english"), "E-LANG-TRANSLATION-COPY").map { |f| f.field[%r{steps/0/do_it\z}] }
  end

  # ---- W-ABSOLUTE ----------------------------------------------------------------------------------------------------------------

  test "W-ABSOLUTE does not read the text around the box of a typed gap, which is material; the prompt keeps it" do
    material = en.sub(%(input_before: "The baby"), %(input_before: "The baby always"))
    assert_empty found(check(material, "english"), "W-ABSOLUTE").map { |f| [ f.field, f.detail[:word] ] }
    after = en.sub(%(input_after: "(cry) at night."), %(input_after: "(cry) at night, never."))
    assert_empty found(check(after, "english"), "W-ABSOLUTE").map(&:field)
    prompt = en.sub(%(prompt_en: "Write the verb: Does the baby cry at night?"), %(prompt_en: "Write the verb: the baby always cries."))
    assert_equal [ "always" ], found(check(prompt, "english"), "W-ABSOLUTE").map { |f| f.detail[:word] }
  end

  # ---- W-CHECK-ANSWER-IN-PROMPT ----------------------------------------------------------------------------------------------------

  ARTICLE = <<~Y.freeze
    ::: check normalized_text
    prompt_es: "%<es>s"
    prompt_it: "%<it>s"
    input_after: "libro es de Ana."
    answer: "el"
    explain_es: "Libro es masculino: el libro."
    explain_it: "Libro è maschile: el libro."
    :::

    ::: check select
  Y

  def article(es_prompt, it_prompt = "Scrivi l'articolo che manca.") = es.sub("::: check select\n", format(ARTICLE, es: es_prompt, it: it_prompt))

  test "an answer of two letters that is only a function word of the instruction is no W-CHECK-ANSWER-IN-PROMPT; one in the prompt's sentence still is" do
    assert_empty found(check(article("Escribe el artículo que falta."), "spanish"), "W-CHECK-ANSWER-IN-PROMPT").map(&:field)
    assert_empty found(check(article("Escribe el artículo de la palabra «libro»."), "spanish"), "W-CHECK-ANSWER-IN-PROMPT").map(&:field)
    assert_equal 1, found(check(article("Escribe el artículo de «el libro»."), "spanish"), "W-CHECK-ANSWER-IN-PROMPT").size
    assert_equal 1, found(check(article("Escribe el artículo: el libro."), "spanish"), "W-CHECK-ANSWER-IN-PROMPT").size
    assert_equal 1, found(check(article("Escribe el artículo de [[es:el]] libro."), "spanish"), "W-CHECK-ANSWER-IN-PROMPT").size
  end

  # ---- the leak scans ------------------------------------------------------------------------------------------------------------

  test "an accepted word that opens the instruction, the hint, the format line or the message is not a leak; the same word later in it is" do
    a = Validation::Answers
    assert a.contains?("Write the word.", "write")
    assert_not a.contains_after_lead?("Write the word.", "write")
    assert_not a.contains_after_lead?("  «Write» the word.", "write")
    assert_not a.contains_after_lead?("Check the verb.\nWrite it at the end.", "write")
    assert a.contains_after_lead?("Now write the word.", "write")
    assert a.contains_after_lead?("Write the word. Then write it again.", "write")
    assert a.contains_after_lead?("Write", "write"), "a line that is only the word is the leak"
    assert a.contains_after_lead?("Write the verb: she writes, I write", "write")
    assert a.contains_after_lead?("Write the verb: cry", "cry")
    assert_not a.contains_after_lead?("Rewrite the word.", "write"), "inside another word it never counted"
    assert a.contains_after_lead?("Use the form 'goes' here", "goes"), "a key of several words, or a word that does not open the text, is as before"
  end

  def blank = JSON.parse(DIR.join("item_blank.json").read)

  def run_item(item)
    Validation::Rules.with(practice: { min_static_instances: 2, min_instances_per_code: 1 }) do
      Validation::ItemRunner.new(files: ValidationFixtures.files_for(item), context: item_context(item["subject"]), grandfathered: false).call
    end
  end

  def item_context(subject)
    skills = { "english.present-simple" => { "key" => "english.present-simple", "errors" => [ { "code" => "en_missing_third_s", "implicates" => [] } ] } }
    Validation::Context.new(subject: subject, skill: ->(key) { skills[key] }, graph_present: true,
                            source_line: ->(source, number) { { text: "i verbi al presente semplice e i verbi regolari", origin: "pdf" } if source == "seconda-example" && number == 200 },
                            reference_body: ->(_) { nil })
  end

  test "an item whose instance accepts «write» may open its instruction with Write; the instruction that says it later is W-ANSWER-IN-STEM" do
    item = blank
    item["instances"][0]["accept"] = [ "write" ]
    assert_empty run_item(item).findings.select { |f| f.code == "W-ANSWER-IN-STEM" }.map(&:to_h)
    item["prompt"]["stem_en"] = "Now write the word that fits the gap."
    item["prompt"]["stem_it"] = "Ora scrivi la parola che completa lo spazio."
    assert_equal [ "/instances/0/prompt/stem_en" ], run_item(item).findings.select { |f| f.code == "W-ANSWER-IN-STEM" }.map(&:field).uniq
  end

  test "an error message that opens with the verb of an accepted answer is no W-MESSAGE-GIVES-KEY; one that states it later is" do
    item = blank
    item["instances"][0]["accept"] = [ "complete" ]
    item["error_catalogue"][0]["message_en"] = "Complete the verb with an ending."
    item["error_catalogue"][0]["message_it"] = "Aggiungi una desinenza al verbo."
    assert_empty run_item(item).findings.select { |f| f.code == "W-MESSAGE-GIVES-KEY" }.map(&:to_h)
    item["error_catalogue"][0]["message_en"] = "With she, complete the verb."
    assert_equal [ "/error_catalogue/0/message_en" ], run_item(item).findings.select { |f| f.code == "W-MESSAGE-GIVES-KEY" }.map(&:field)
  end

  def cue_item
    item = blank
    item["translate_material"] = false
    item["hints_en"] = [ "Write study in the box.", "He, she and it take a different verb form from I.", "The verb needs a few more letters at the end." ]
    item["hints_it"] = [ "Scrivi study nella casella.", "Con he, she e it il verbo al presente non è uguale a quello con I.", "Al verbo servono ancora alcune lettere alla fine." ]
    item["instances"].each do |inst|
      inst["display"] = { "stem_en" => "She ___ (study) hard at night." }
      inst["answer"] = "study"
      inst["errors"] = [ { "code" => "en_missing_third_s", "value" => "studys" } ]
      inst["solution"] = { "steps" => inst["solution"]["steps"], "final" => "study" }
    end
    item["instances"][1]["display"] = { "stem_en" => "He ___ (study) hard on Sundays." }
    item
  end

  test "E-HINT-KEY: the Italian hint may name a word that is on screen in brackets, as the English one may" do
    result = run_item(cue_item)
    assert_empty result.findings.select { |f| f.code == "E-HINT-KEY" }.map { |f| [ f.field, f.message ] }
  end

  test "E-HINT-KEY: a key that is not on screen is still refused in both hints" do
    item = cue_item
    item["instances"].each { |inst| inst["display"]["stem_en"] = inst["display"]["stem_en"].sub("(study)", "(learn)") }
    item["hints_en"][1] = "The verb is study."
    item["hints_it"][1] = "Il verbo è study."
    fields = run_item(item).findings.select { |f| f.code == "E-HINT-KEY" }.map(&:field).uniq
    %w[hints_en hints_it].each { |key| assert_includes fields, "/instances/0/#{key}/1", key }
  end

  # ---- E-LANG-PAIR-CONFLICT ------------------------------------------------------------------------------------------------------

  test "the same label with two Italian versions is a warning up to three words and an error beyond" do
    pair = lambda do |english, one, two|
      doc = { "text_en" => english, "text_it" => one, "again" => { "text_en" => english, "text_it" => two } }
      Validation::Findings.new.tap { |f| VB.check(f, doc, lang: "en") }.select { |f| f.code.end_with?("LANG-PAIR-CONFLICT") }.map { |f| [ f.code, f.severity ] }
    end
    assert_equal [ [ "W-LANG-PAIR-CONFLICT", "warning" ] ], pair.call("a state", "uno stato", "una condizione")
    assert_equal [ [ "W-LANG-PAIR-CONFLICT", "warning" ] ], pair.call("He is here", "Lui è qui", "Eccolo")
    assert_equal [ [ "E-LANG-PAIR-CONFLICT", "error" ] ], pair.call("He is not at home", "Lui non è a casa", "Non è in casa")
    assert_empty pair.call("a state", "uno stato", "Uno stato"), "the same Italian in two cases is no conflict"
  end
end
