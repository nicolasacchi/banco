require "test_helper"
require_relative "../support/validation_fixtures"

# D-402, slice 2: the validation of the items of english and spanish in the target language with their authored Italian. The golden items are
# test/fixtures/lang/item_*.json (slice 0); every code of the bilingual family has one broken copy, a legacy item is checked as it always was, and
# the answer-leak scans read the Italian layer too. No Chrome is needed (listed instances only).
class BilingualItemsTest < ActiveSupport::TestCase
  F = ValidationFixtures
  GOLDEN = Rails.root.join("test/fixtures/lang")

  def golden(name) = JSON.parse(GOLDEN.join(name).read)

  SKILLS = {
    "english.make-do" => { "key" => "english.make-do", "errors" => [ { "code" => "en_make_do_swap", "implicates" => [] }, { "code" => "en_make_for_both", "implicates" => [] } ] },
    "english.present-simple" => { "key" => "english.present-simple", "errors" => [ { "code" => "en_missing_third_s", "implicates" => [] } ] },
    "spanish.ser-estar" => { "key" => "spanish.ser-estar", "errors" => [ { "code" => "es_ser_estar", "implicates" => [] } ] }
  }.freeze

  def context(subject = "english")
    Validation::Context.new(subject: subject, skill: ->(key) { SKILLS[key] }, graph_present: true,
                            source_line: ->(source, number) { { text: "i verbi al presente semplice e i verbi regolari", origin: "pdf" } if source == "seconda-example" && number == 200 },
                            reference_body: ->(_) { nil })
  end

  # The golden items have two instances: the practice pool and the code-sparse rule are lowered to what they have.
  def run_item(item, grandfathered: false)
    Validation::Rules.with(practice: { min_static_instances: 2, min_instances_per_code: 1 }) do
      Validation::ItemRunner.new(files: F.files_for(item), context: context(item["subject"]), grandfathered: grandfathered).call
    end
  end

  def codes(result) = result.findings.map(&:code).uniq
  def at(result, code) = result.findings.select { |f| f.code == code }.map(&:field)

  # The translated golden choice (every text paired, the options too) and the one that follows the form-material rule (translate_material: false).
  def choice = golden("item_choice_translated.json")
  def material_choice = golden("item_choice.json")
  def blank = golden("item_blank.json")

  # ---- the golden items -----------------------------------------------------------------------------------------------------------

  test "the golden items validate clean: passed, no error, none of the bilingual family" do
    [ choice, blank ].each do |item|
      result = run_item(item)
      assert_equal "passed", result.status, result.findings.select { |f| f.severity == "error" }.map(&:to_h).inspect
      family = result.findings.select { |f| f.code.match?(/\AE-LANG|BILINGUAL|TOPIC-LANG/) }
      assert_empty family, family.map(&:to_h).inspect
    end
  end

  test "the golden choice item keeps both layers in the stored instances and the pair of the instance's own hints as an object" do
    result = run_item(choice)
    first, second = result.instances
    assert_equal "Il sabato io ___ il letto e poi io ___ la spesa con papà.", first[:display]["stem_it"]
    assert_equal "On Saturdays I ___ my bed and then I ___ the shopping with Dad.", first[:display]["stem_en"]
    assert_equal "fare / fare", first[:display]["options"].first["text_it"]
    assert_equal choice["hints_en"], first[:hints]["hints_en"], "an instance without hints of its own stores the item's pair"
    assert_equal choice["hints_it"], first[:hints]["hints_it"]
    assert_equal %w[hints_en hints_it], second[:hints].keys.sort
    assert_equal choice["instances"][1]["hints_en"], second[:hints]["hints_en"]
  end

  # ---- one broken copy per code ---------------------------------------------------------------------------------------------------

  test "E-LANG-PAIR-MISSING: a target text without its Italian, and a list of another length" do
    item = choice
    item.delete("answer_format_it")
    item["hints_it"].pop
    result = run_item(item)
    assert_includes codes(result), "E-LANG-PAIR-MISSING"
    assert_equal [ "/answer_format_en", "/hints_en/2" ], at(result, "E-LANG-PAIR-MISSING").sort
  end

  test "E-LANG-PAIR-MISSING: an option without its text_it, a solution final without final_it, a table without its translated rows" do
    item = choice
    item["instances"][0]["display"]["options"][1].delete("text_it")
    item["instances"][1]["solution"].delete("final_it")
    item["instances"][0]["display"]["table"] = { "header" => [ "Verb" ], "rows" => [ [ "make" ] ] }
    assert_equal [ "/instances/0/display/options/1/text", "/instances/0/display/table/header", "/instances/0/display/table/rows", "/instances/1/solution/final" ], at(run_item(item), "E-LANG-PAIR-MISSING").sort
    ok = choice
    ok["instances"][0]["display"]["table"] = { "header" => [ "Verb" ], "rows" => [ [ "make" ] ], "header_it" => [ "Verbo" ], "rows_it" => [ [ "fare" ] ] }
    assert_empty at(run_item(ok), "E-LANG-PAIR-MISSING")
  end

  test "E-LANG-PAIR-ORPHAN: an Italian text with nothing to translate" do
    item = choice
    item["prompt"].delete("stem_en")
    result = run_item(item)
    assert_equal [ "/prompt/stem_en" ], at(result, "E-LANG-PAIR-ORPHAN")
    assert_equal "failed", result.status
  end

  test "E-LANG-PAIR-SHAPE: a translation that loses a blank, a number or a bold word, and one that has another paragraph count" do
    item = blank
    item["instances"][0]["display"]["stem_it"] = "Lei va a scuola in autobus."
    item["instances"][1]["display"]["stem_en"] = "My brother ___ football on 2 Fridays."
    item["hints_it"][0] = "**Guarda** il soggetto della frase: she."
    result = run_item(item)
    assert_equal [ "/hints_en/0", "/instances/0/display/stem_en", "/instances/1/display/stem_en" ], at(result, "E-LANG-PAIR-SHAPE").sort
    shapes = Validation::Bilingual
    assert_equal [], shapes.shape_problems("Look at $x + 1$ and 3.5 cm.\n\nThen go.", "Guarda $x + 1$ e 3,5 cm.\n\nPoi vai.")
    assert_equal 1, shapes.shape_problems("A\n\nB", "A B").size
    assert_equal 1, shapes.shape_problems("Use $x$.", "Usa $y$.").size
    assert_equal 1, shapes.shape_problems("See [[g:verb]] here.", "Vedi qui.").size
    assert_equal 1, shapes.shape_problems("- one\n- two", "- uno\n- due\n- tre").size - 1 + 1
  end

  test "E-LANG-PAIR-CONFLICT: the same target text with two translations in one scope; items are not one table" do
    doc = { "text_en" => "The book is on the table", "text_it" => "Il libro è sul tavolo", "again" => { "text_en" => "The book is on the table", "text_it" => "Il quaderno è sul tavolo" } }
    found = Validation::Findings.new
    Validation::Bilingual.check(found, doc, lang: "en")
    assert_equal [ "/again/text_en" ], found.select { |f| f.code == "E-LANG-PAIR-CONFLICT" }.map(&:field)
    quiet = Validation::Findings.new
    Validation::Bilingual.check(quiet, doc, lang: "en", conflicts: false)
    assert_not quiet.include_code?("E-LANG-PAIR-CONFLICT")
    two = choice
    two["instances"][1]["display"]["options"].each { |o| o["text_it"] = "fa / faccio" }
    assert_not_includes codes(run_item(two)), "E-LANG-PAIR-CONFLICT"
  end

  test "E-LANG-TRANSLATION-LANG: an _it text that is English; quoted English and spans are not" do
    item = choice
    item["prompt"]["stem_it"] = "Choose the two words that fill the gaps, in the order they are needed."
    result = run_item(item)
    assert_equal [ "/prompt/stem_it" ], at(result, "E-LANG-TRANSLATION-LANG") # the fault is in the Italian: the field names it
    quiet = choice
    quiet["prompt"]["stem_it"] = "Scegli le parole «the book and the pen» che completano la frase, nell'ordine in cui servono."
    assert_not_includes codes(run_item(quiet)), "E-LANG-TRANSLATION-LANG"
    spanish = Validation::Bilingual
    assert spanish.translation_lang?("Tengo que ir porque tiene hay muy", "es")
    assert_not spanish.translation_lang?("Si dice [[es:el niño que tiene hambre]] in Spagna.", "es")
  end

  test "E-LANG-TRANSLATION-COPY: an _it text equal to its target, only when it has a word of four letters" do
    item = choice
    item["prompt"]["stem_it"] = item["prompt"]["stem_en"]
    assert_equal [ "/prompt/stem_it" ], at(run_item(item), "E-LANG-TRANSLATION-COPY")
    item = choice
    item["instances"][0]["display"]["options"][3]["text_it"] = "do / do"
    assert_not_includes codes(run_item(item)), "E-LANG-TRANSLATION-COPY", "do / do has no word of four letters"
    item["instances"][0]["display"]["options"][0]["text_it"] = "make / do"
    assert_includes codes(run_item(item)), "E-LANG-TRANSLATION-COPY"
  end

  test "E-LESSON-LANG: Italian words in a target-language text" do
    item = choice
    item["prompt"]["stem_en"] = "Scegli le parole che sono giuste per questo spazio."
    assert_includes at(run_item(item), "E-LESSON-LANG"), "/prompt/stem_en"
  end

  test "E-LANG-BILINGUAL-FLAG: a sibling with the flag off, a sibling of the other language, the flag in a subject that teaches none" do
    off = choice.except("bilingual")
    assert_includes codes(run_item(off)), "E-LANG-BILINGUAL-FLAG"
    assert_includes at(run_item(off), "E-LANG-BILINGUAL-FLAG"), "/prompt/stem_en"
    false_flag = choice.merge("bilingual" => false)
    assert_includes codes(run_item(false_flag)), "E-LANG-BILINGUAL-FLAG"

    other = choice
    other["prompt"]["stem_es"] = "Elige las dos palabras."
    assert_includes at(run_item(other), "E-LANG-BILINGUAL-FLAG"), "/prompt/stem_es"

    flags = Validation::Findings.new
    Validation::Bilingual.flag(flags, { "bilingual" => true }, subject: "math")
    assert_equal [ "/bilingual" ], flags.map(&:field)
    # The schema of a subject that teaches no language refuses the marker and the siblings first, as before the bilingual courses.
    math = F.static_item.merge("bilingual" => true)
    assert_includes codes(run_item(math)), "E-SCHEMA"
    assert_not_includes codes(run_item(math)), "E-LANG-BILINGUAL-FLAG"
  end

  test "E-LANG-BILINGUAL-REQUIRED: a new revision of a subject on the list, never a grandfathered one, a bilingual one or another subject" do
    legacy = choice.except("bilingual")
    legacy["prompt"] = { "stem_it" => "Scegli le due parole che completano la frase." }
    legacy.delete("answer_format_en")
    legacy.delete("answer_format_it")
    legacy.delete("steps_en")
    legacy.delete("steps_it")
    legacy.delete("hints_en")
    legacy["hints_it"] = choice["hints_it"]
    legacy["error_catalogue"].each { |e| e.delete("message_en") }
    legacy["instances"].each do |inst|
      inst["display"].delete("stem_en")
      inst["display"]["options"].each { |o| o.delete("text_it") }
      inst["solution"].delete("final_it")
      inst["solution"]["steps"].each { |s| s.delete("text_en") }
      inst.delete("hints_en")
    end
    # D-404, D-405: the live rules list english and spanish (the cut-over of D-402).
    assert_equal %w[english spanish], Validation::Rules.get(:lang, :bilingual_required)
    assert_includes codes(run_item(legacy)), "E-LANG-BILINGUAL-REQUIRED"
    assert_not_includes codes(run_item(legacy, grandfathered: true)), "E-LANG-BILINGUAL-REQUIRED"
    assert_not_includes codes(run_item(choice)), "E-LANG-BILINGUAL-REQUIRED"
    legacy_es = legacy.merge("subject" => "spanish", "skill" => "spanish.ser-estar")
    assert_includes codes(run_item(legacy_es)), "E-LANG-BILINGUAL-REQUIRED"
    assert_not_includes codes(run_item(legacy_es, grandfathered: true)), "E-LANG-BILINGUAL-REQUIRED"
    Validation::Rules.with(lang: { bilingual_required: [] }) do
      assert_not_includes codes(run_item(legacy_es)), "E-LANG-BILINGUAL-REQUIRED", "nothing is required while lang.bilingual_required is empty"
      assert_not_includes codes(run_item(legacy)), "E-LANG-BILINGUAL-REQUIRED", "nothing is required while lang.bilingual_required is empty"
    end
    Validation::Rules.with(lang: { bilingual_required: %w[spanish] }) do
      assert_not_includes codes(run_item(legacy)), "E-LANG-BILINGUAL-REQUIRED", "a subject off the list is not required"
    end
  end

  # ---- the target-language lint -----------------------------------------------------------------------------------------------------

  test "the target lint: 12-word sentences, the stem cap, W-LANG-LEVEL with the given names allowed" do
    item = blank
    item["instances"][0]["display"]["stem_en"] = "She ___ to school by bus every single morning with her little brother and her old friend."
    item["instances"][1]["display"]["stem_en"] = "Tom ___ the ubiquitous perambulator."
    item["instances"][1]["display"]["stem_it"] = "Tom ___ il passeggino onnipresente."
    result = run_item(item)
    assert_includes at(result, "E-READ"), "/instances/0/display/stem_en"
    assert_includes at(result, "W-LANG-LEVEL"), "/instances/1/display/stem_en"
    words = result.findings.find { |f| f.code == "W-LANG-LEVEL" && f.field == "/instances/1/display/stem_en" }.detail[:words]
    assert_includes words, "ubiquitous"
    assert_not_includes words, "tom"
    names = Validation::Bilingual.names("en")
    assert_includes names, "tom"
    assert_includes Validation::Bilingual.names("es"), "lucía"
    named = blank
    named["instances"][0]["display"]["stem_en"] = "Tom ___ to school by bus."
    named["instances"][0]["display"]["stem_it"] = "Tom ___ a scuola in autobus."
    assert_not_includes at(run_item(named), "W-LANG-LEVEL"), "/instances/0/display/stem_en"
    # teaches_en is read from the item when it has one: the lesson's own way of allowing a word
    allowed = Validation::Findings.new
    Validation::Bilingual.target_lint(allowed, "/x", "en", "A perambulator.", known: %w[perambulator])
    assert_empty allowed.to_a
  end

  test "the Italian lint now reaches passage_it of a bilingual testlet, and still skips it for a legacy one" do
    long = "Questo testo è lungo e va avanti ancora per molte altre parole senza fermarsi in nessun punto fino alla fine della riga, e poi continua con altre parole ancora, " \
           "senza che si veda la fine del testo, perché chi scrive non vuole fermarsi."
    bilingual = { "passage_en" => "A short text.", "passage_it" => long }
    findings = Validation::Findings.new
    Validation::Readability.lint_document(bilingual, "", findings, skip: Validation::ItemChecks.target_language_keys({ "subject" => "english", "bilingual" => true }))
    assert_includes findings.map(&:code), "E-READ"
    legacy = Validation::Findings.new
    Validation::Readability.lint_document({ "passage_it" => "A very long English text that never ends and goes on and on and on for far more than the twenty five words that an Italian sentence may have." },
                                          "", legacy, skip: Validation::ItemChecks.target_language_keys({ "subject" => "english" }))
    assert_empty legacy.to_a
  end

  # ---- the Italian layer -------------------------------------------------------------------------------------------------------------

  test "the Italian layer: a hint, a support or a stem that gives the key away in the translation is found" do
    item = choice
    item["instances"][0]["hints_it"] = [ "Pensa a make e a do.", "Prima make e poi do, fare / fare.", "Dillo ad alta voce." ]
    item["instances"][0]["hints_en"] = [ "Think about both verbs.", "Look at the nouns.", "Say it aloud." ]
    result = run_item(item)
    hit = result.findings.select { |f| f.code == "W-HINT-OPTION" }
    assert_equal [ "/instances/0/hints_it/1" ], hit.map(&:field)
    assert_match(/in the Italian translation/, hit.first.message)
  end

  test "the Italian layer: the target key in the Italian stem is a leak, the same stem without it is not" do
    item = choice
    item["instances"][1]["display"]["stem_it"] = "La domenica la mamma ___ una torta e io ___ i compiti (makes / do)."
    result = run_item(item)
    assert_includes codes(result), "E-SOLUTION-IN-DISPLAY"
    assert_match(/in the Italian translation/, result.findings.find { |f| f.code == "E-SOLUTION-IN-DISPLAY" }.message)
    assert_not_includes codes(run_item(choice)), "E-SOLUTION-IN-DISPLAY"
  end

  test "the Italian layer: E-HINT-KEY and E-SUPPORT-LEAK on a normalized_text item" do
    item = blank
    item["hints_it"][1] = "Con he, she e it il verbo diventa goes, plays e così via."
    item["hints_en"][1] = "With he, she and it the verb changes."
    item["answer_format_it"] = "Scrivi la parola intera: plays."
    item["answer_format_en"] = "Write the whole word."
    result = run_item(item)
    assert_includes codes(result), "E-HINT-KEY"
    assert_includes codes(result), "E-SUPPORT-LEAK"
    assert(result.findings.select { |f| %w[E-HINT-KEY E-SUPPORT-LEAK].include?(f.code) }.all? { |f| f.message.start_with?("in the Italian translation") })
    assert_equal "failed", result.status
  end

  test "W-MESSAGE-GIVES-KEY reads both messages of the catalogue" do
    item = choice
    item["error_catalogue"][0]["message_it"] = "Non scrivere make / do: guarda di nuovo i nomi."
    item["error_catalogue"][1]["message_en"] = "Not make / do: the gaps need two different verbs."
    fields = at(run_item(item), "W-MESSAGE-GIVES-KEY")
    assert_includes fields, "/error_catalogue/1/message_en"
  end

  # ---- legacy items -----------------------------------------------------------------------------------------------------------------

  test "a legacy item of english is validated as before: its Italian instruction, English options, passage_it in English" do
    legacy = F.static_item("subject" => "english", "skill" => "english.present-simple", "component" => "choice",
                           "prompt" => { "stem_it" => "Scegli la parola giusta." },
                           "error_catalogue" => [ { "code" => "en_missing_third_s", "description_it" => "Manca la -s.", "message_it" => "Con she il verbo prende una desinenza.", "implicates" => [] } ],
                           "instances" => [ "plays", "play", "played" ].each_with_index.map { |right, i|
                             options = [ { "id" => "o1", "text" => right }, { "id" => "o2", "text" => "playing" }, { "id" => "o3", "text" => "to play" } ]
                             { "display" => { "stem_it" => "She ___ football number #{i + 1}.", "options" => options }, "answer" => "o1",
                               "errors" => [ { "code" => "en_missing_third_s", "value" => "o2" }, { "code" => "en_missing_third_s", "value" => "o3" } ],
                               "solution" => { "steps" => [ { "text_it" => "Con she il verbo prende la -s." } ], "final" => right } } },
                           "tests" => { "must_accept" => [ "o1" ], "must_reject" => [ "o2" ], "blank" => "invalid" })
    result = run_item(legacy, grandfathered: true) # D-405: a legacy english revision keeps the pass it had
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_empty codes(result).grep(/LANG|PAIR/)
    assert_kind_of Array, result.instances.first[:hints].to_a, "no hints on a diagnosis item"
    assert_equal "She ___ football number 1.", result.instances.first[:display]["stem_it"]
    assert_equal "english", legacy["subject"]
  end

  test "a legacy practice item stores its hints as the Italian list, as before" do
    item = choice.except("bilingual")
    item = { "schema" => "banco.item/1", "schema_version" => 1, "kind" => "practice_item", "subject" => "english", "skill" => "english.make-do", "component" => "choice", "level" => 2,
             "prompt" => { "stem_it" => "Scegli le due parole." }, "hints_it" => [ "Uno qui.", "Due qui.", "Tre qui." ],
             "error_catalogue" => [ { "code" => "en_make_do_swap", "description_it" => "Scambia.", "message_it" => "Guarda i nomi.", "implicates" => [] }, { "code" => "en_make_for_both", "description_it" => "Stesso.", "message_it" => "Due verbi.", "implicates" => [] } ],
             "instances" => choice["instances"].map { |inst|
               { "display" => { "stem_it" => inst["display"]["stem_en"], "options" => inst["display"]["options"].map { |o| o.slice("id", "text") } }, "answer" => "o1", "errors" => inst["errors"],
                 "solution" => { "steps" => [ { "text_it" => "Si dice make the bed." } ], "final" => inst["solution"]["final"] } } },
             "sources" => choice["sources"], "tests" => choice["tests"] }
    result = run_item(item, grandfathered: true)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_equal [ "Uno qui.", "Due qui.", "Tre qui." ], result.instances.first[:hints]
  end

  # ---- the bilingual short answer and testlet ----------------------------------------------------------------------------------------

  test "a bilingual short answer keeps both stems and both model answers; the rubric stays Italian" do
    item = { "schema" => "banco.item/1", "schema_version" => 1, "kind" => "short_answer", "component" => "short_answer", "subject" => "english", "bilingual" => true, "skill" => "english.present-simple",
             "passage_en" => "Tom wakes up at seven. He goes to school by bus.", "passage_it" => "Tom si sveglia alle sette. Va a scuola in autobus.",
             "prompt" => { "stem_en" => "Write two short sentences about your day.", "stem_it" => "Scrivi due frasi brevi sulla tua giornata." },
             "rubric" => { "points" => [ { "id" => "present", "expected_it" => "Usa il presente.", "weight" => 1 }, { "id" => "two", "expected_it" => "Scrive due frasi.", "weight" => 1 } ],
                           "model_answer_en" => "I wake up at seven. I go to school.", "model_answer_it" => "Mi sveglio alle sette. Vado a scuola.", "threshold" => 0.5 },
             "sources" => choice["sources"] }
    assert_empty Banco::Schemas.validate("item", item).map(&:message)
    result = run_item(item)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    shown = result.instances.first
    assert_equal "Write two short sentences about your day.", shown[:display]["stem_en"]
    assert_equal "Scrivi due frasi brevi sulla tua giornata.", shown[:display]["stem_it"]
    assert_equal "I wake up at seven. I go to school.", shown[:solution]["model_answer_en"]
    broken = item.merge("passage_it" => "Tom wakes up at seven and he goes to the school with his bus.")
    assert_equal [ "/passage_it" ], at(run_item(broken), "E-LANG-TRANSLATION-LANG")
  end

  # ---- a reading text per instance (display.passage_*) --------------------------------------------------------------------------------------

  # The golden blank item with a passage in each instance's display (D-402: three to five questions on each text, not ten on one).
  EACH_PASSAGES = [ [ "She goes to school by bus. It takes ten minutes.", "Lei va a scuola in autobus. Ci vogliono dieci minuti." ],
                    [ "My brother plays football on Fridays. He likes it.", "Mio fratello gioca a calcio il venerdì. Gli piace." ] ].freeze

  def with_passages(item)
    item["instances"].each_with_index { |inst, i| inst["display"].merge!("passage_en" => EACH_PASSAGES[i][0], "passage_it" => EACH_PASSAGES[i][1]) }
    item
  end

  test "a bilingual instance's own passage validates clean, its key may be a word of the text, and it is stored with both layers" do
    result = run_item(with_passages(blank))
    assert_equal "passed", result.status, result.findings.select { |f| f.severity == "error" }.map(&:to_h).inspect
    assert_empty codes(result) & %w[E-SOLUTION-IN-DISPLAY E-LANG-PAIR-MISSING E-LANG-PAIR-ORPHAN E-SCHEMA E-GEN-SCHEMA W-LANG-FRAME-BLANK]
    assert_equal EACH_PASSAGES[0], result.instances.first[:display].values_at("passage_en", "passage_it")
    assert_empty Banco::Schemas.validate("item", with_passages(blank)).map(&:message)
  end

  test "the target lint, the pair and the translation checks reach the instance's own passage" do
    item = with_passages(blank)
    item["instances"][0]["display"].delete("passage_it")
    assert_equal [ "/instances/0/display/passage_en" ], at(run_item(item), "E-LANG-PAIR-MISSING")
    item = with_passages(blank)
    item["instances"][0]["display"]["passage_en"] = "She goes to school by bus and then she plays with all of her friends in the big park."
    assert_equal [ "/instances/0/display/passage_en" ], at(run_item(item), "E-READ")
    item = with_passages(blank)
    item["instances"][1]["display"]["passage_en"] = "Scegli le parole che sono giuste per questo brano."
    assert_includes at(run_item(item), "E-LESSON-LANG"), "/instances/1/display/passage_en"
    item = with_passages(blank)
    item["instances"][0]["display"]["passage_it"] = "She goes to the school with her bus and she is happy."
    assert_equal [ "/instances/0/display/passage_it" ], at(run_item(item), "E-LANG-TRANSLATION-LANG")
    item = with_passages(blank)
    item["instances"][0]["display"]["passage_it"] = item["instances"][0]["display"]["passage_en"]
    assert_equal [ "/instances/0/display/passage_it" ], at(run_item(item), "E-LANG-TRANSLATION-COPY")
  end

  test "the leak scan reads the instance's own passage in both layers: a long key option stated word for word is E-SOLUTION-IN-DISPLAY" do
    item = choice
    first = item["instances"][0]["display"]
    first["options"][0].merge!("text" => "make the bed every morning", "text_it" => "rifare il letto ogni mattina")
    first.merge!("passage_en" => "Tom has to make the bed every morning before school.", "passage_it" => "Tom deve rifare il letto ogni mattina prima della scuola.")
    result = run_item(item)
    assert_equal [ "/instances/0/display/passage_en", "/instances/0/display/passage_it" ], at(result, "E-SOLUTION-IN-DISPLAY").sort
    assert(result.findings.any? { |f| f.field == "/instances/0/display/passage_it" && f.message.start_with?("in the Italian translation") })
    first.merge!("passage_en" => "Tom likes to make beds.", "passage_it" => "A Tom piace rifare i letti.")
    assert_empty at(run_item(item), "E-SOLUTION-IN-DISPLAY"), "a short key is a word of any text"
  end

  test "a legacy instance's own passage_it (the language of the course under its legacy key) is not linted as Italian and breaks nothing" do
    legacy = { "schema" => "banco.item/1", "schema_version" => 1, "kind" => "practice_item", "subject" => "english", "skill" => "english.present-simple", "component" => "normalized_text", "level" => 1,
               "prompt" => { "stem_it" => "Scrivi la parola." }, "hints_it" => [ "Uno qui.", "Due qui.", "Tre qui." ],
               "error_catalogue" => [ { "code" => "en_missing_third_s", "description_it" => "Manca la s.", "message_it" => "Con she serve la s.", "implicates" => [] } ],
               "instances" => EACH_PASSAGES.map { |text, _| { "display" => { "stem_it" => "She ___ to school by bus.", "passage_it" => "#{text} She is happy to go there with her friends every day." }, "answer" => "goes",
                                                                "errors" => [ { "code" => "en_missing_third_s", "value" => "go" } ], "solution" => { "steps" => [ { "text_it" => "Con she il verbo prende la s." } ], "final" => "goes" } } },
               "sources" => blank["sources"], "tests" => blank["tests"] }
    result = run_item(legacy, grandfathered: true)
    assert_equal "passed", result.status, result.findings.select { |f| f.severity == "error" }.map(&:to_h).inspect
    assert_empty codes(result) & %w[E-READ E-SCHEMA E-GEN-SCHEMA E-SOLUTION-IN-DISPLAY]
    assert_equal EACH_PASSAGES[0][0] + " She is happy to go there with her friends every day.", result.instances.first[:display]["passage_it"]
  end

  test "a sub item of a testlet shows the testlet's passage: one of its own is E-GEN-SCHEMA" do
    testlet = JSON.parse(Rails.root.join("test/fixtures/content/item/good/testlet.json").read)
    testlet["sub_items"][0]["instances"][0]["display"]["passage_it"] = "Un altro brano."
    result = Validation::ItemRunner.new(files: F.files_for(testlet), context: context("italian")).call
    assert_includes at(result, "E-GEN-SCHEMA"), "/sub_items/0/instances/0/display/passage_it"
  end

  test "two instances with the same options and stem but another passage are not alike; on the same passage they are" do
    shown = ->(passage) { { "display" => { "stem_en" => "Which colour?", "passage_en" => passage, "options" => %w[red blue green grey].map { |t| { "id" => t, "text" => t } } } } }
    assert_empty Validation::AlikeInstances.pairs("choice", [ shown.call("Tom has a red bike."), shown.call("Amy has a blue kite.") ])
    assert_equal [ [ 0, 1 ] ], Validation::AlikeInstances.pairs("choice", [ shown.call("Tom has a red bike."), shown.call("Tom has a red bike.") ])
  end

  # ---- W-LANG-FRAME-BLANK (§4.3) ------------------------------------------------------------------------------------------------------------

  test "W-LANG-FRAME-BLANK: an instruction line with a ___ that the frame does not know switches the whole-sentence grading off; the known wordings do not" do
    stem = lambda do |en, it|
      item = blank
      item["instances"][0]["display"].merge!("stem_en" => en, "stem_it" => it)
      run_item(item)
    end
    assert_equal [ "/instances/0/display/stem_en" ], at(stem.call("Fill ___ with one word.\nShe ___ to school by bus.", "Riempi ___ con una parola.\nLei ___ a scuola in autobus."), "W-LANG-FRAME-BLANK")
    assert_empty at(stem.call("Write the word in place of ___.\nShe ___ to school by bus.", "Scrivi la parola al posto di ___.\nLei ___ a scuola in autobus."), "W-LANG-FRAME-BLANK")
    assert_empty at(stem.call("She ___ to school by bus and he ___ to work.", "Lei ___ a scuola in autobus e lui ___ al lavoro."), "W-LANG-FRAME-BLANK"), "two gaps in one sentence are not a second line"
    assert_empty at(run_item(blank), "W-LANG-FRAME-BLANK")
    assert_equal "warning", Validation::Codes.all.fetch("W-LANG-FRAME-BLANK")["severity"]
    es = Grading::Frame.blank_lines("Escribe la palabra en lugar de ___.\nAna ___ en Madrid.")
    assert_equal 1, es
  end

  # ---- the topic status --------------------------------------------------------------------------------------------------------------------

  test "W-TOPIC-LANG-MIXED: some parts bilingual and some not; nothing for a topic that is all one or the other, or for another subject" do
    subject = Struct.new(:key).new("english")
    lesson = ->(flag) { Struct.new(:body).new({ "bilingual" => flag }) }
    pins = ->(*flags) { [ { skill: "s", pins: flags.each_with_index.map { |flag, i| { key: "item-#{i}", bilingual: flag } } } ] }
    run = lambda do |lesson_revision, resolved, entry: { "title_it" => "Titolo" }, doc: { "key" => "topic.english.x" }, subj: subject|
      findings = Validation::Findings.new
      Validation::TopicChecks.mixed(doc, entry, subj, lesson_revision, resolved, findings)
      findings
    end
    mixed = run.call(lesson.call(true), pins.call(true, false), entry: { "title_it" => "Titolo", "title_en" => "Title" })
    assert_equal [ "W-TOPIC-LANG-MIXED" ], mixed.map(&:code)
    assert_equal [ "the item item-1" ], mixed.first.detail[:parts]
    assert_equal [ "the lesson", "the title" ], run.call(lesson.call(false), pins.call(true), entry: { "title_it" => "T" }).first.detail[:parts] - [ "the item item-0" ]
    assert_empty run.call(lesson.call(false), pins.call(false, false)).to_a
    assert_empty run.call(lesson.call(true), pins.call(true), entry: { "title_it" => "T", "bilingual" => true }).to_a
    assert_empty run.call(lesson.call(true), pins.call(false), subj: Struct.new(:key).new("math")).to_a
    intro = run.call(lesson.call(true), pins.call(true), entry: { "bilingual" => true }, doc: { "key" => "topic.english.x", "intro_it" => "Ciao." })
    assert_equal [ [ "the intro" ] ], intro.map { |f| f.detail[:parts] }
  end
end
