require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/lesson2_fixtures"

# D-402, round 6 of the tooling (slice A, validators): what the second wave of authors met. Each rule that was narrowed has its false positive and, next to it, the
# true positive it keeps. The lessons are the golden ones of test/fixtures/lang with one edit each; the items are the golden items with one edit each.
class BilingualToolingSixATest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  V = ValidationFixtures
  VB = Validation::Bilingual
  KW = Validation::KeyWords

  SKILLS = {
    "english.make-do" => { "key" => "english.make-do", "errors" => [ { "code" => "en_make_do_swap", "implicates" => [] }, { "code" => "en_make_for_both", "implicates" => [] } ] },
    "english.present-simple" => { "key" => "english.present-simple", "errors" => [ { "code" => "en_missing_third_s", "implicates" => [] } ] },
    "spanish.tilde" => { "key" => "spanish.tilde", "errors" => [ { "code" => "es_tilde", "implicates" => [] } ] }
  }.freeze

  def es = DIR.join("lesson_es_figures.md").read
  def en = DIR.join("lesson_en_figures.md").read
  def en_plain = DIR.join("lesson_en.md").read
  def check(md, subject = "english") = Validation::LessonChecks.call(md, subject: subject, context: F.context(subject))
  def found(outcome, *codes) = outcome.findings.select { |f| codes.include?(f.code) }
  def level_fields(outcome, word) = found(outcome, "W-LANG-LEVEL").select { |f| f.detail[:words].to_a.include?(word) }.map(&:field)
  def golden(name) = JSON.parse(DIR.join(name).read)

  def item_context(subject = "english")
    Validation::Context.new(subject: subject, skill: ->(key) { SKILLS[key] }, graph_present: true,
                            source_line: ->(source, number) { { text: "i verbi al presente semplice e i verbi regolari", origin: "pdf" } if source == "seconda-example" && number == 200 },
                            reference_body: ->(_) { nil })
  end

  def run_item(item)
    Validation::Rules.with(practice: { min_static_instances: 2, min_instances_per_code: 1 }) do
      Validation::ItemRunner.new(files: V.files_for(item), context: item_context(item["subject"]), grandfathered: false).call
    end
  end

  def at(result, *codes) = result.findings.select { |f| codes.include?(f.code) }.map(&:field)

  # ---- 1. the level of form material ----------------------------------------------------------------------------------------------

  test "a rare word in a material option of an item warns, and the key form, the error forms and teaches_en do not" do
    item = golden("item_choice.json")
    item["instances"][0]["display"]["options"] << { "id" => "o5", "text" => "make / perambulate" }
    item["instances"][0]["display"]["options"][1]["text"] = "do / quixote"
    levels = ->(doc) { run_item(doc).findings.select { |f| f.code == "W-LANG-LEVEL" }.flat_map { |f| f.detail[:words].to_a.map { |w| [ f.field, w ] } } }
    assert_includes levels.call(item), [ "/instances/0/display/options/4/text", "perambulate" ]
    assert_not_includes levels.call(item).map(&:last), "make", "the key option is the form the item teaches"
    assert_not_includes levels.call(item).map(&:last), "quixote", "o2 is an error value of the instance: a taught wrong form"
    assert_empty levels.call(item.merge("teaches_en" => [ "perambulate" ])).select { |_, w| w == "perambulate" }
    key = golden("item_choice.json")
    key["instances"][0]["display"]["options"][0]["text"] = "perambulate / do"
    key["instances"][0]["solution"]["final"] = "perambulate / do"
    assert_empty levels.call(key).select { |_, w| w == "perambulate" }, "a rare word in the key option is the taught form"
  end

  test "the sentence with its blank of a material item is read for the level, and its own key and error values are not" do
    item = golden("item_blank.json").merge("translate_material" => false)
    item["instances"].each { |inst| inst["display"].delete("stem_it") }
    item["instances"][0]["display"]["stem_en"] = "She ___ to the brujúla by bus."
    item["instances"][1]["display"]["stem_en"] = "My brother ___ football on Fridays."
    item["instances"][1]["answer"] = "gallivants"
    item["instances"][1]["errors"] = [ { "code" => "en_missing_third_s", "value" => "gallivant" } ]
    item["instances"][1]["solution"]["final"] = "gallivants"
    item["instances"][1]["solution"].delete("final_it")
    item["instances"][0]["solution"].delete("final_it")
    words = run_item(item).findings.select { |f| f.code == "W-LANG-LEVEL" }.flat_map { |f| f.detail[:words].to_a }
    assert_includes words, "brujúla"
    assert_not_includes words, "gallivants"
    assert_not_includes words, "gallivant"
  end

  test "a rare word in a material option or in the sentence of a lesson check warns; the key, the error answer and teaches_en do not" do
    md = en_plain.sub(%(  - {id: b, text_en: "play"}), %(  - {id: b, text_en: "play"}\n  - {id: c, text_en: "gallivant"}))
    assert_equal [ "/cards/0/blocks/1/options/2/text_en" ], level_fields(check(md), "gallivant")
    assert_empty level_fields(check(md.sub("bilingual: true\n", "bilingual: true\nteaches_en: [gallivant]\n")), "gallivant")
    keyed = en_plain.sub(%(  - {id: b, text_en: "play"}), %(  - {id: b, text_en: "gallivant"}))
    assert_empty level_fields(check(keyed), "gallivant"), "the key option of a check is the form it teaches"
    error = en_plain.sub(%(  - {id: a, text_en: "plays"}), %(  - {id: a, text_en: "gallivants"}))
    assert_empty level_fields(check(error), "gallivants"), "an option named by an error answer is a taught wrong form"
    sentence = en_plain.sub(%(translate_material: false\noptions:), %(translate_material: false\nsentence_en: "She ___ the brujúla very well."\noptions:))
    assert_equal [ "/cards/0/blocks/1/sentence_en" ], level_fields(check(sentence), "brujúla")
  end

  test "the text around the box of a typed gap on form material is read for the level, with no W-ABSOLUTE" do
    md = en.sub(%(input_before: "The baby"), %(translate_material: false\ninput_before: "The baby always gallivants")).sub(%(input_after: "(cry) at night."), %(input_after: "(cry) at nightfall."))
    outcome = check(md)
    assert_equal [ "/cards/1/blocks/1/input_after", "/cards/1/blocks/1/input_before" ], found(outcome, "W-LANG-LEVEL").select { |f| (f.detail[:words].to_a & %w[gallivants nightfall]).any? }.map(&:field).sort
    assert_empty found(outcome, "W-ABSOLUTE")
  end

  test "the cells of a table of forms (header, rows) are read for the level, with no sentence cap and no absolute word; headers that are a pair stay as they were" do
    md = en.sub("alt_it: \"Tabella di domande: il soggetto e la forma di have got.\"\n", "\\&translate_material: false\n")
    md = md.sub(%(  - ["lui, lei", "Ha un cane?"]\n  - ["voi, loro", "Hanno una macchina?"]\n), "").sub("rows_it:\n", "")
    assert_empty level_fields(check(md), "gallivant")
    rows = md[/^rows:\n(?:  - \[.*\]\n)+/]
    assert_not_nil rows
    odd = md.sub(rows, rows.sub(/\]\n\z/, %(, "gallivant"]\n)))
    assert_equal [ "gallivant" ], found(check(odd), "W-LANG-LEVEL").flat_map { |f| f.detail[:words].to_a }.grep("gallivant").uniq
    assert_empty found(check(odd), "E-READ", "W-ABSOLUTE").select { |f| f.field.include?("/rows/") }
  end

  test "the level of form material is checked on a generated instance too: Validation::Bilingual.lint_target reads the options and the stem" do
    doc = { "translate_material" => false,
            "display" => { "stem_en" => "She ___ the brujúla.", "options" => [ { "id" => "a", "text" => "plays" }, { "id" => "b", "text" => "gallivant" } ] },
            "answer" => "a", "errors" => [] }
    findings = Validation::Findings.new
    VB.lint_target(findings, doc, "en")
    assert_equal [ [ "/display/options/1/text", [ "gallivant" ] ], [ "/display/stem_en", [ "brujúla" ] ] ], findings.select { |f| f.code == "W-LANG-LEVEL" }.map { |f| [ f.field, f.detail[:words] ] }.sort
    assert_empty findings.select { |f| f.code == "W-ABSOLUTE" }
  end

  # ---- 2. the key scan on everyday words ----------------------------------------------------------------------------------------------

  test "KeyWords: a function word as the key leaks only when it is quoted, named as the answer or stands with the frame" do
    assert KW.everyday?("at", "en")
    assert KW.everyday?("está", "es")
    assert_not KW.everyday?("goes", "en")
    assert_not KW.everyday?("at", nil)
    frame = KW.frame("The cat is ___ the door.")
    assert_equal %w[cat is the door], frame
    assert_not KW.leak?("Look at the lesson card", "at", frame: frame)
    assert KW.leak?("Write at", "at", frame: frame)
    assert KW.leak?("The word is «at».", "at", frame: frame)
    assert KW.leak?("Use [[en:at]] here", "at", frame: frame)
    assert KW.leak?("at", "at", frame: frame), "a line that is only the key"
    assert KW.leak?("The cat is at the door.", "at", frame: frame)
    es_frame = KW.frame("El gato ___ en la cocina.")
    assert_equal %w[el gato en la], es_frame
    assert_not KW.leak?("La frase dice dónde está", "está", frame: es_frame)
    assert KW.leak?("el gato está en la cocina", "está", frame: es_frame)
    assert KW.leak?("La respuesta es está", "está", frame: es_frame)
  end

  def short_key_item
    item = golden("item_blank.json")
    item["instances"].each_with_index do |inst, i|
      inst["display"] = { "stem_en" => i.zero? ? "The cat is ___ the door." : "The dog is ___ the window.", "stem_it" => "Il gatto è ___ la porta." }
      inst["answer"] = "at"
      inst["errors"] = [ { "code" => "en_missing_third_s", "value" => "in" } ]
      inst["solution"] = { "steps" => [ { "text_en" => "The door is a place.", "text_it" => "La porta è un luogo." } ], "final" => "at", "final_it" => "at: il gatto è alla porta." }
    end
    item["hints_en"] = [ "Look at the lesson card.", "A word for a place.", "It has two letters." ]
    item["hints_it"] = [ "Guarda la scheda della lezione.", "Una parola che indica un luogo.", "Ha due lettere." ]
    item
  end

  test "E-HINT-KEY: a key of two letters that is a function word («at») passes «Look at the lesson card»; «Write at», «at» in quotes and the framed sentence are refused" do
    assert_empty at(run_item(short_key_item), "E-HINT-KEY")
    [ "Write at.", "The word is «at».", "The cat is at the door." ].each do |hint|
      item = short_key_item
      item["hints_en"][1] = hint
      assert_equal [ "/instances/0/hints_en/1" ], at(run_item(item), "E-HINT-KEY").first(1), hint
    end
  end

  test "E-SUPPORT-LEAK: the steps and the answer format follow the same rule for an everyday key" do
    item = short_key_item
    item["answer_format_en"] = "One word, like the ones on the lesson card."
    item["answer_format_it"] = "Una parola, come quelle della scheda."
    item["steps_en"] = [ "Look at the sentence.", "Find the place word." ]
    item["steps_it"] = [ "Guarda la frase.", "Trova la parola di luogo." ]
    assert_empty at(run_item(item), "E-SUPPORT-LEAK")
    item["steps_en"] = [ "Look at the sentence.", "Write «at» in the gap." ]
    assert_includes at(run_item(item), "E-SUPPORT-LEAK"), "/steps_en/1"
  end

  def estamos_item
    item = golden("item_blank.json")
    item["subject"] = "spanish"
    item["skill"] = "spanish.tilde"
    json = JSON.generate(item).gsub(/_en"/, '_es"').gsub("en_missing_third_s", "es_tilde")
    item = JSON.parse(json)
    item["instances"].each_with_index do |inst, i|
      inst["display"] = { "stem_es" => i.zero? ? "Nosotros ___ en casa de Ana." : "Nosotros ___ cansados hoy.", "stem_it" => "Noi ___ a casa di Ana." }
      inst["answer"] = "estamos"
      inst["errors"] = [ { "code" => "es_tilde", "value" => "estan" } ]
      inst["solution"] = { "steps" => [ { "text_es" => "Con nosotros va esta forma.", "text_it" => "Con noi va questa forma." } ], "final" => "estamos", "final_it" => "estamos: siamo a casa di Ana." }
    end
    item["error_catalogue"][0]["message_es"] = "Mira dónde estamos."
    item
  end

  test "W-MESSAGE-GIVES-KEY: an everyday key of six letters («estamos») is stated only when the message quotes it, names it or has it with the frame; a plain key is as before" do
    assert_empty at(run_item(estamos_item), "W-MESSAGE-GIVES-KEY")
    [ "Escribe estamos.", "Nosotros estamos en casa." ].each do |message|
      item = estamos_item
      item["error_catalogue"][0]["message_es"] = message
      assert_equal [ "/error_catalogue/0/message_es" ], at(run_item(item), "W-MESSAGE-GIVES-KEY"), message
    end
    plain = estamos_item
    plain["instances"].each { |inst| inst["answer"] = "cansados" }
    plain["error_catalogue"][0]["message_es"] = "Piensa en cansados."
    assert_equal [ "/error_catalogue/0/message_es" ], at(run_item(plain), "W-MESSAGE-GIVES-KEY"), "a key that is no function word is found anywhere, as before"
  end

  # ---- 3. the level by lemma ------------------------------------------------------------------------------------------------------

  test "a word of another inflection of a listed word is no level word («aprendes», «buscas», «quedáis», «tenéis»); a rare word still is" do
    %w[aprender buscar quedar tener].each { |lemma| assert Lessons::Lexicon.words("es").include?(lemma), "#{lemma} is in the es list" }
    assert_empty Lessons::Lexicon.unknown("es", "Tú aprendes y buscas, vosotros quedáis y tenéis")
    assert_equal [ "fantasmagoría" ], Lessons::Lexicon.unknown("es", "Hay una fantasmagoría")
    assert_empty Lessons::Lexicon.unknown("en", "She learns and he walks")
    assert_equal [ "perambulates" ], Lessons::Lexicon.unknown("en", "She perambulates")
  end

  # ---- 4. caps --------------------------------------------------------------------------------------------------------------------

  def long(text, lang = "es") = VB.target_report(lang, text)[:long]

  test "a clock time is one token" do
    assert_equal 13, long("Son las 8:45 de la mañana y Ana llega tarde a casa hoy")
    assert_equal 14, long("Son las 8 45 de la mañana y Ana llega tarde a casa hoy"), "two numbers are two words"
    assert_equal 1, Validation::Readability.count_words("8:45")
  end

  test "a colon followed by ¿ or ¡ ends the sentence for the cap; a colon before a plain word does not" do
    assert_equal 8, long("Escribe aquí la pregunta del texto: ¿Dónde está el gato de Ana en casa?")
    assert_equal 8, long("Escribe aquí la pregunta del texto:¿Dónde está el gato de Ana en casa?")
    assert_equal 7, long("Mira bien el cartel de la calle: ¡Qué grande es esta casa de piedra!")
    assert_equal 17, long("Escribe aquí la pregunta del texto: dónde está el gato de Ana en casa de su abuela")
  end

  test "a span whose closing full stop sits inside it still ends the sentence; the words of the span count one" do
    text = "Mira esta frase de Ana [[it:Dove sta il gatto di Ana in questa casa?]] y luego escribe la respuesta de la pregunta"
    assert_equal 8, long(text), "the span is one word and its stop ends the sentence: 'Mira esta frase de Ana m' and 'y luego escribe la respuesta de la pregunta'"
    assert_equal 14, long(text.sub("casa?]]", "casa]]")), "with no stop inside the span the sentence goes on"
    assert_equal 9, long("[[it:Dove sta il gatto?]] Escribe la respuesta de la pregunta aquí en casa")
    assert_equal 16, long("[[it:Dove sta il gatto]] Escribe la respuesta de la pregunta aquí en casa y mira el gato de Ana")
  end

  test "a lesson text block with a quotation or an Italian span is not counted word by word in the cap, a plain long sentence is" do
    quoted = es.sub("Como en italiano, la voz suena más fuerte en una [[g:sílaba]].", "Como en italiano, la voz suena más fuerte en una [[g:sílaba]]. Mira «Ella canta muy bien en la casa de su madre y de su padre cada tarde» ahora.")
    quoted = quoted.sub("Come in italiano, la voce batte più forte su una [[g:sillaba]].", "Come in italiano, la voce batte più forte su una [[g:sillaba]]. Guarda «Ella canta muy bien en la casa de su madre y de su padre cada tarde» ora.")
    assert_empty found(check(quoted, "spanish"), "E-READ").select { |f| f.message.include?("Spanish sentence") }
    plain = quoted.delete("«»")
    assert_not_empty found(check(plain, "spanish"), "E-READ").select { |f| f.message.include?("Spanish sentence") }
    span = es.sub("Como en italiano, la voz suena más fuerte en una [[g:sílaba]].", "Como en italiano, la voz suena más fuerte en una [[g:sílaba]]. [[it:Che bella casa ha Ana!]] Mira la casa de Ana y su jardín muy bonito ahora mismo.")
    span = span.sub("Come in italiano, la voce batte più forte su una [[g:sillaba]].", "Come in italiano, la voce batte più forte su una [[g:sillaba]]. Guarda la casa di Ana.")
    assert_empty found(check(span, "spanish"), "E-READ").select { |f| f.message.include?("Spanish sentence") }, "a span with its stop inside ends the sentence: the next one is 12 words"
    open_span = span.sub("Ana!]]", "Ana]]")
    assert_not_empty found(check(open_span, "spanish"), "E-READ").select { |f| f.message.include?("Spanish sentence") }, "the same span with no stop in it joins the next sentence: 13 words"
  end

  ARTICLE = <<~Y.freeze
    ::: check normalized_text
    prompt_es: "%<es>s"
    prompt_it: "Scrivi l'articolo."
    input_after: "libro es de Ana."
    answer: "el"
    explain_es: "Libro es masculino: el libro."
    explain_it: "Libro è maschile: el libro."
    :::

    ::: check select
  Y

  test "W-CHECK-ANSWER-IN-PROMPT names the field where the match is: prompt_es in a Spanish lesson, prompt_it in an Italian one" do
    outcome = check(es.sub("::: check select\n", format(ARTICLE, es: "Escribe el artículo de «el libro».")), "spanish")
    assert_equal [ "prompt_es" ], found(outcome, "W-CHECK-ANSWER-IN-PROMPT").map { |f| f.field[%r{[^/]+\z}] }
    legacy = Lessons::Blocks::Context.new(subject: "math", findings: Validation::Findings.new)
    assert_equal "prompt_it", legacy.slot("prompt_it")
    assert_equal "prompt_es", Lessons::Blocks::Context.new(subject: "spanish", findings: Validation::Findings.new).tap { |c| c.lang = "es" }.slot("prompt_it")
  end

  # ---- 5. W-ABSOLUTE on Italian ---------------------------------------------------------------------------------------------------

  def absolute(text)
    findings = Validation::Findings.new
    Validation::Readability.lint(text, field: "/x_it", role: :text, findings: findings)
    findings.select { |f| f.code == "W-ABSOLUTE" }.map { |f| f.detail[:word] }
  end

  test "«quasi tutti», «quasi sempre», «non sempre» are qualified claims, no absolute word; «tutti» and «sempre» alone are" do
    assert_empty absolute("Quasi tutti i verbi regolari prendono la stessa desinenza.")
    assert_empty absolute("Il verbo cambia quasi sempre alla terza persona.")
    assert_empty absolute("Non tutti i verbi cambiano e non sempre la radice resta uguale.")
    assert_empty absolute("Quasi mai la radice cambia qui.")
    assert_equal [ "tutti" ], absolute("Tutti i verbi regolari prendono la stessa desinenza.")
    assert_equal [ "sempre" ], absolute("Il verbo cambia sempre alla terza persona.")
    assert_equal [ "mai" ], absolute("La radice non cambia mai in questo caso.")
    assert_equal [ "solo" ], absolute("Il verbo prende solo la desinenza."), "«solo» alone is left as it was"
  end

  # ---- 6. the copy check ----------------------------------------------------------------------------------------------------------

  test "E-LANG-TRANSLATION-COPY allows an identical label of three words or fewer that is one word of both languages" do
    assert_not VB.copy?("Una cosa", "una cosa", "es")
    assert_not VB.copy?("Una casa", "Una casa", "es")
    assert_not VB.copy?("Radio nuova", "Radio nuova", "en")
  end

  test "E-LANG-TRANSLATION-COPY keeps a label with a word Italian lacks, a longer text, and a problem_it that is the Spanish once the markup is stripped" do
    assert VB.copy?("Una cosa más", "Una cosa más", "es"), "four words"
    assert VB.copy?("El gato", "El gato", "es"), "el is not Italian"
    assert VB.copy?("Muy buena", "Muy buena", "es"), "y is not Italian"
    assert VB.copy?("The house", "The house", "en")
    assert VB.copy?("Completa la frase con el verbo correcto de Ana.", "Completa la **frase** con el verbo correcto de Ana.", "es")
    md = en.sub(%(problem_it: "Completa la domanda su Jack."), %(problem_it: "Complete the question about Jack."))
    assert_includes found(check(md), "E-LANG-TRANSLATION-COPY").map { |f| f.field[%r{[^/]+\z}] }, "problem_it"
  end

  test "a role span in an Italian text is quoted target: no E-LANG-TRANSLATION-LANG; the same Spanish words outside a span are" do
    assert_not VB.translation_lang?("Il pronome [[od:los]] sostituisce [[oi:las]] cosas che cambiano.", "es")
    assert VB.translation_lang?("Il pronome los sostituisce las cosas che cambiano.", "es")
    assert VB.translation_lang?("Il pronome [[od|it:los]] sostituisce [[oi|it:las]] cosas che cambiano.", "es"), "a role span that says |it holds Italian words: read as before"
  end

  # ---- 7. concept_map material ----------------------------------------------------------------------------------------------------

  CONCEPT_MAP = <<~Y.freeze
    ::: schema concept_map
    alt_es: "Un mapa del verbo hablar con tres formas."
    alt_it: "Una mappa del verbo hablar con tre forme."
    %<marker>s
    root: r
    nodes:
      - {id: r, text_es: "hablar"%<root_it>s}
      - {id: a, text_es: "hablo"%<a_it>s}
      - {id: b, text_es: "hablas"%<b_it>s}
    edges:
      - {from: r, to: a, label_es: "yo", label_it: "io"}
      - {from: r, to: b, label_es: "tú", label_it: "tu"}
    :::

    ::: check select
  Y

  def concept_map(marker: true, italian: false)
    marker_line = marker ? "translate_material: false" : ""
    part = ->(it) { italian ? %(, text_it: "#{it}") : "" }
    es.sub("::: check select\n", format(CONCEPT_MAP, marker: marker_line, root_it: part.call("parlare"), a_it: part.call("parlo"), b_it: part.call("parli")))
  end

  test "a concept_map with translate_material: false has verb-form nodes with no Italian, and no schema, pair or block finding" do
    outcome = check(concept_map, "spanish")
    assert_empty found(outcome, "E-SCHEMA", "E-LESSON-BLOCK", "E-LESSON-DIAGRAM", "E-LANG-PAIR-MISSING", "E-LANG-PAIR-ORPHAN").map { |f| [ f.code, f.field, f.message ] }
    block = Lessons::Parser2.call(concept_map, Validation::Findings.new).body.dig("cards", 0, "blocks").find { |b| b["schema"].is_a?(Hash) && b["schema"]["type"] == "concept_map" }
    assert_equal [ false, nil ], [ block["schema"]["translate_material"], block["schema"]["nodes"][0]["text_it"] ]
  end

  test "a concept_map without the marker still needs the Italian of every node (E-LANG-PAIR-MISSING); with the marker, an Italian text beside a node is E-LANG-PAIR-ORPHAN" do
    missing = found(check(concept_map(marker: false), "spanish"), "E-LANG-PAIR-MISSING", "E-SCHEMA")
    assert_not_empty missing
    assert_equal [ "E-LANG-PAIR-MISSING" ], missing.map(&:code).uniq
    complete = check(concept_map(marker: false, italian: true), "spanish")
    assert_empty found(complete, "E-LANG-PAIR-MISSING", "E-SCHEMA", "E-LANG-PAIR-ORPHAN")
    orphan = found(check(concept_map(italian: true), "spanish"), "E-LANG-PAIR-ORPHAN")
    assert_equal 3, orphan.size
    assert_match(/form material/, orphan.first.message)
  end

  # ---- 8. a step equal to the final -------------------------------------------------------------------------------------------------

  test "a step whose text is the final of its exercise with another Italian is a warning, not E-LANG-PAIR-CONFLICT; two steps that differ are still refused" do
    pair = lambda do |a, b|
      doc = { "exercises" => [ { "final_en" => "Does Jack study German?", "final_it" => a, "steps" => [ { "do_en" => "Does Jack study German?", "do_it" => b } ] } ] }
      Validation::Findings.new.tap { |f| VB.check(f, doc, lang: "en") }.select { |f| f.code.end_with?("LANG-PAIR-CONFLICT") }.map { |f| [ f.code, f.severity ] }
    end
    assert_equal [ [ "W-LANG-PAIR-CONFLICT", "warning" ] ], pair.call("Jack studia tedesco?", "Studia tedesco, Jack?")
    assert_empty pair.call("Jack studia tedesco?", "Jack studia tedesco?")
    steps = { "exercises" => [ { "steps" => [ { "do_en" => "Does Jack study German at school?", "do_it" => "Jack studia tedesco a scuola?" }, { "do_en" => "Does Jack study German at school?", "do_it" => "Studia tedesco a scuola, Jack?" } ] } ] }
    refused = Validation::Findings.new.tap { |f| VB.check(f, steps, lang: "en") }.select { |f| f.code.end_with?("LANG-PAIR-CONFLICT") }.map { |f| [ f.code, f.severity ] }
    assert_equal [ [ "E-LANG-PAIR-CONFLICT", "error" ] ], refused
  end
end
