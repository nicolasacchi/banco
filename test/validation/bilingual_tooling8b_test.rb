require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/lesson2_fixtures"

# D-402, round 8 of the tooling (slice B, validators): what the fourth wave of authors met. Each rule that was narrowed has its false positive and, next to it, the
# true positive it keeps. The lessons are the golden ones of test/fixtures/lang with one edit each; the items are the golden items with one edit each.
class BilingualTooling8bTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  V = ValidationFixtures
  VB = Validation::Bilingual
  KW = Validation::KeyWords
  LX = Lessons::Lexicon

  SKILLS = {
    "english.present-simple" => { "key" => "english.present-simple", "errors" => [ { "code" => "en_missing_third_s", "implicates" => [] } ] },
    "english.agreement" => { "key" => "english.agreement", "composite_of" => %w[english.be english.have],
                             "errors" => [ { "code" => "en_missing_third_s", "implicates" => %w[english.be english.have] } ] },
    "english.be" => { "key" => "english.be", "errors" => [] },
    "english.have" => { "key" => "english.have", "errors" => [] }
  }.freeze

  def es = DIR.join("lesson_es_figures.md").read
  def check(md, subject = "spanish") = Validation::LessonChecks.call(md, subject: subject, context: F.context(subject))
  def found(outcome, *codes) = outcome.findings.select { |f| codes.include?(f.code) }
  def level_words(outcome) = found(outcome, "W-LANG-LEVEL").flat_map { |f| f.detail[:words].to_a }
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

  # ---- 1. W-TILE-ORDER ---------------------------------------------------------------------------------------------------------------

  def tiles_check(answer: %w[a b c d e f g], tiles: nil, extra: "")
    tiles ||= %w[Mi hermana se ducha por la mañana duchan].each_with_index.map { |t, i| "  - {id: #{(97 + i).chr}, text_es: \"#{t}\"}" }.join("\n")
    lines = [ "::: check tiles", 'prompt_es: "Construye la frase."', 'prompt_it: "Costruisci la frase."', "tiles:", tiles, "answer: [#{answer.join(', ')}]", extra,
              'explain_es: "Se ducha va con mi hermana."', 'explain_it: "Se ducha va con mia sorella."', ":::" ]
    "#{lines.reject(&:empty?).join("\n")}\n\n"
  end

  def tile_orders(md) = found(check(md), "W-TILE-ORDER").flat_map { |f| f.detail[:orders].to_a }

  test "W-TILE-ORDER: «Mi hermana se ducha por la mañana» warns about «Por la mañana mi hermana se ducha» until it is accepted or declared" do
    md = es.sub("::: check select\n", tiles_check + "::: check select\n")
    orders = tile_orders(md)
    assert_includes orders, "por la mañana mi hermana se ducha"
    assert_includes orders, "mi hermana por la mañana se ducha"
    assert_not_includes orders, "mi hermana se ducha por la mañana", "the key is no warning"
    accepted = es.sub("::: check select\n", tiles_check(extra: "accept:\n  - [e, f, g, a, b, c, d]") + "::: check select\n")
    assert_not_includes tile_orders(accepted), "por la mañana mi hermana se ducha"
    assert_includes tile_orders(accepted), "mi hermana por la mañana se ducha", "the other orders still warn"
    declared = es.sub("::: check select\n", tiles_check(extra: "errors:\n  - {answer: [e, f, g, a, b, c, d], message_es: \"Mal.\", message_it: \"Male.\"}") + "::: check select\n")
    assert_not_includes tile_orders(declared), "por la mañana mi hermana se ducha"
    assert_empty found(check(md), "E-LESSON-CHECK", "E-SCHEMA", "E-LESSON-BLOCK").map { |f| [ f.code, f.field, f.message ] }
  end

  test "W-TILE-ORDER: a tiles check whose tiles are no time or place phrase gives no warning" do
    tiles = %w[Mi hermana se ducha rápido duchan].each_with_index.map { |t, i| "  - {id: #{(97 + i).chr}, text_es: \"#{t}\"}" }.join("\n")
    md = es.sub("::: check select\n", tiles_check(answer: %w[a b c d], tiles: tiles) + "::: check select\n")
    assert_empty found(check(md), "W-TILE-ORDER")
  end

  test "W-TILE-ORDER: the four sentences of the wave" do
    cases = { "En 1973 Picasso murió" => "picasso murió en 1973", "Mi hermano está hoy cansado" => "hoy mi hermano está cansado",
              "En la mesa está mi libro" => "está mi libro en la mesa", "Mi hermana por la mañana se ducha" => "por la mañana mi hermana se ducha" }
    cases.each do |sentence, order|
      words = sentence.split
      tiles = words.each_with_index.map { |t, i| "  - {id: #{(97 + i).chr}, text_es: \"#{t}\"}" }.join("\n") + "\n  - {id: z, text_es: \"fue\"}"
      md = es.sub("::: check select\n", tiles_check(answer: words.each_index.map { |i| (97 + i).chr }, tiles: tiles) + "::: check select\n")
      assert_includes tile_orders(md), order, sentence
    end
  end

  def ordering_item(words = %w[Picasso died in 1973], steps: nil)
    item = golden("item_choice.json").merge("component" => "ordering")
    item["prompt"] = { "stem_en" => "Put the words in order to build the sentence.", "stem_it" => "Metti le parole in ordine per costruire la frase." }
    item["instances"].each_with_index do |inst, i|
      ids = words.each_index.map { |k| "e#{k + 1}" }
      inst["display"] = { "stem_en" => "Build the sentence #{i + 1}.", "elements" => words.each_with_index.map { |w, k| { "id" => ids[k], "text" => w } } }
      inst["answer"] = ids
      inst["errors"] = [ { "code" => "en_make_do_swap", "value" => ids.reverse } ]
      inst["solution"] = { "steps" => [ { "text_en" => "The subject comes first.", "text_it" => "Il soggetto viene prima." } ], "final" => words.join(" ") }
    end
    item
  end

  test "W-TILE-ORDER: an ordering instance of word tiles lists the orders that move the time phrase; a declared error value or an ordering of whole sentences gives none" do
    orders = ->(item) { run_item(item).findings.select { |f| f.code == "W-TILE-ORDER" } }
    found = orders.call(ordering_item)
    assert_equal %w[/instances/0/answer /instances/1/answer], found.map(&:field)
    assert_includes found.first.detail[:orders], "in 1973 picasso died"
    assert_not_includes found.first.detail[:orders], "picasso died in 1973", "the key is no warning"
    declared = ordering_item
    declared["instances"].each { |inst| inst["errors"] << { "code" => "en_make_do_swap", "value" => %w[e3 e4 e1 e2] } }
    assert_not_includes orders.call(declared).first.detail[:orders], "in 1973 picasso died"
    sentences = ordering_item([ "Picasso died in 1973 when he was ninety-one", "He was born in Malaga in 1881 and lived in France", "He painted pictures all of his long life" ])
    assert_empty orders.call(sentences)
  end

  # ---- 2. E-SUPPORT-LEAK in answer formats ---------------------------------------------------------------------------------------------

  def goes_item
    item = golden("item_blank.json")
    item["instances"].each_with_index do |inst, i|
      inst["display"] = { "stem_en" => i.zero? ? "The cat ___ to the door." : "The dog ___ to the window.", "stem_it" => "Il gatto ___ alla porta." }
      inst["answer"] = i.zero? ? "walks" : "runs"
      inst["errors"] = [ { "code" => "en_missing_third_s", "value" => i.zero? ? "walk" : "goes" } ]
      inst["solution"] = { "steps" => [ { "text_en" => "The subject is one cat.", "text_it" => "Il soggetto è un gatto." } ], "final" => inst["answer"], "final_it" => "#{inst['answer']}: il gatto va alla porta." }
    end
    item["answer_format_en"] = "Write what goes in place of ___."
    item["answer_format_it"] = "Scrivi cosa va al posto di ___."
    item
  end

  test "E-SUPPORT-LEAK: «goes», an error value of another instance, in «Write what goes in place of ___» is no leak; a format that quotes it still is" do
    assert_empty at(run_item(goes_item), "E-SUPPORT-LEAK")
    quoted = goes_item
    quoted["answer_format_en"] = "Write a verb, like «runs»."
    assert_equal [ "/answer_format_en" ], at(run_item(quoted), "E-SUPPORT-LEAK")
    named = goes_item
    named["answer_format_en"] = "Write goes in place of ___."
    assert_equal [ "/answer_format_en" ], at(run_item(named), "E-SUPPORT-LEAK"), "an error value named as the answer is still found"
  end

  test "KeyWords: an error value of the first thousand words reads as everyday, the key keeps the narrower list" do
    assert KW.everyday?("goes", "en", frequent: KW::SUPPORT_ERROR_FREQUENT)
    assert_not KW.everyday?("goes", "en")
    assert_not KW.leak?("Write what goes here.", "goes", frame: [])
    assert KW.leak?("Write the word goes.", "goes", frame: [])
  end

  test "KeyWords: «the» as a key is no leak in «Write the word that fits»; «Write the» still is" do
    assert_not KW.leak?("Write the word that fits.", "the", frame: [])
    assert KW.leak?("Write the.", "the", frame: [])
    assert KW.leak?("Write «the» in the gap.", "the", frame: [])
  end

  # ---- 3. stress of vosotros imperative + pronoun -----------------------------------------------------------------------------------------

  def stress_of(form_es)
    Lessons::Diagrams::WordParts.analyse({ "form_es" => form_es })[:stress]
  end

  test "word_parts: «compra|d+lo» is stressed on «prad» and needs no tilde; «decíd+me+lo» is an esdrújula with it and refused without" do
    assert_equal 2, stress_of("compra|d+lo")
    assert_equal 1, stress_of("i|d+os")
    assert_equal 2, stress_of("senta+os")
    assert_equal 2, stress_of("pon|e+os")
    assert_equal 2, stress_of("decíd+me+lo")
    word = ->(form) { { "type" => "word_parts", "alt_it" => "Parole divise in pezzi e in sillabe, con la sillaba forte segnata.", "view" => "syllables", "words" => [ { "form_es" => form } ] } }
    assert_empty Lessons::Diagrams.check(word.call("compra|d+lo"), subject: "spanish").map(&:to_h)
    assert_empty Lessons::Diagrams.check(word.call("decíd+me+lo"), subject: "spanish").map(&:to_h)
    assert_equal [ "/words/0/form_es" ], Lessons::Diagrams.check(word.call("decid+me+lo"), subject: "spanish").map(&:path)
    assert_equal [ "/words/0/form_es" ], Lessons::Diagrams.check(word.call("compra|d+lo").tap { |w| w["words"][0]["form_es"] = "comprá|d+lo" }, subject: "spanish").map(&:path), "a tilde that is not needed"
  end

  # ---- 4. the course map: pointers and the quoted example forms -----------------------------------------------------------------------------------

  def topic(title_it)
    { "key" => "lezione.spanish.pasiva", "kind" => "lezione", "bilingual" => true, "title_es" => "La forma pasiva", "title_it" => title_it,
      "term" => 1, "minutes" => 30, "skills" => [ "spanish.pasiva" ], "after" => [] }
  end

  def map_findings(titles)
    findings = Validation::Findings.new
    Validation::CourseChecks.language({ "topics" => titles.map { |t| topic(t) }, "skills" => [] }, "spanish", findings)
    findings.select { |f| f.code == "E-LANG-TRANSLATION-LANG" }
  end

  test "a course map finding of a title carries its /topics/N pointer" do
    found = map_findings([ "La passiva", "Tengo que ir porque tiene hay muy" ])
    assert_equal [ "/topics/1/title_it" ], found.map(&:field)
  end

  test "a title_it that lists Spanish example forms after a colon is no E-LANG-TRANSLATION-LANG; a title that is a Spanish sentence still is" do
    assert_empty map_findings([ "La forma passiva: fue escrito por, está escrito" ])
    assert_equal [ "/topics/0/title_it" ], map_findings([ "Tengo que ir porque tiene hay muy" ]).map(&:field)
    assert_equal [ "/topics/0/title_it" ], map_findings([ "Tengo que ir: porque tiene hay muy, y el que se va" ]).map(&:field).first(1), "a colon is no cover for a Spanish sentence before it"
    assert_equal [ "/topics/0/title_it" ], map_findings([ "La forma passiva: tengo que ir porque tiene hay muy" ]).map(&:field), "after the colon a sentence is no list of forms"
  end

  # ---- 5. implicates of a composite skill ----------------------------------------------------------------------------------------------------

  def composite_item(implicates)
    item = golden("item_blank.json").merge("skill" => "english.agreement")
    item["error_catalogue"][0]["implicates"] = implicates
    item
  end

  test "the graph's own implicates on a composite skill are no E-COMPOSITE and no W-ERROR-NOT-IN-GRAPH; the warning says what to write when the list differs" do
    result = run_item(composite_item(%w[english.be english.have]))
    assert_empty at(result, "E-COMPOSITE", "W-ERROR-NOT-IN-GRAPH")
    warned = run_item(composite_item(%w[english.be])).findings.find { |f| f.code == "W-ERROR-NOT-IN-GRAPH" }
    assert_equal "/error_catalogue/0/implicates", warned.field
    assert_includes warned.message, %(write ["english.be", "english.have"])
    other = golden("item_blank.json")
    other["error_catalogue"][0]["implicates"] = %w[english.be english.have]
    result = run_item(other)
    assert_equal [ "/skill" ], at(result, "E-COMPOSITE"), "an implicate the graph does not link, on a skill that is no composite, is still refused"
    assert_includes result.findings.find { |f| f.code == "E-COMPOSITE" }.message, "write that list"
  end

  # ---- 6. the level: gender and number forms of a taught word ---------------------------------------------------------------------------------------

  test "the feminine and plural forms of a taught or listed Spanish adjective are known; a form of another word is not" do
    { "enferma" => "enfermo", "ocupada" => "ocupado", "enfermos" => "enfermo", "ocupadas" => "ocupado", "jóvenes" => "joven", "felices" => "feliz", "exámenes" => "examen" }.each do |form, base|
      assert LX.taught?("es", form, [ base ], {}), form
    end
    assert_empty LX.unknown("es", "Ella está enferma y ocupada.", known: %w[enfermo ocupado])
    assert_empty LX.unknown("es", "Ellos están enfermos y ocupadas.", known: %w[enfermo ocupado])
    assert_equal %w[enferma], LX.unknown("es", "Ella está enferma.", known: %w[ocupado])
    assert_empty LX.unknown("en", "Two perambulators and three gallivants.", known: %w[perambulator gallivant])
    assert_equal %w[perambulators], LX.unknown("en", "Two perambulators.", known: %w[city])
  end

  # ---- 8. the accept cap -----------------------------------------------------------------------------------------------------------------------

  test "an instance's accept list holds up to 20 entries; 21 is refused by the schema" do
    item = golden("item_blank.json")
    item["instances"][0]["accept"] = Array.new(20) { |i| "variant #{i}" }
    assert_empty Banco::Schemas.validate("item", item).map(&:to_h)
    item["instances"][0]["accept"] << "variant 20"
    assert_not_empty Banco::Schemas.validate("item", item)
    lesson = JSON.parse(Rails.root.join("config/banco/schemas/lesson.json").read)
    assert_equal 20, lesson.dig("$defs", "check_normalized_text", "properties", "accept", "maxItems")
  end

  # ---- 7. the source note cap ------------------------------------------------------------------------------------------------------------------

  test "the fragment of an item's source note is capped at 2000 characters, not 500" do
    item = golden("item_blank.json")
    item["sources"] = [ { "kind" => "textbook", "ref" => "Libro, p. 4", "fragment" => "x" * 2000 } ]
    assert_empty Banco::Schemas.validate("item", item).map(&:to_h)
    item["sources"][0]["fragment"] = "x" * 2001
    assert_not_empty Banco::Schemas.validate("item", item)
  end
end
