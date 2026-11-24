require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/lesson2_fixtures"

# D-402, the tooling after the pilots: form material is not translated (`translate_material: false`), E-LANG-TRANSLATION-COPY and -LANG, the target-language
# sentence split, W-LANG-LEVEL and W-ABSOLUTE of the target text, a lone `_it`, the leak scans of the Italian layer, [[it:..]] quoted in target text.
class BilingualMaterialTest < ActiveSupport::TestCase
  F = ValidationFixtures
  L = Lesson2Fixtures
  GOLDEN = Rails.root.join("test/fixtures/lang")
  VB = Validation::Bilingual

  SKILLS = {
    "english.make-do" => { "key" => "english.make-do", "errors" => [ { "code" => "en_make_do_swap", "implicates" => [] }, { "code" => "en_make_for_both", "implicates" => [] } ] },
    "english.present-simple" => { "key" => "english.present-simple", "errors" => [ { "code" => "en_missing_third_s", "implicates" => [] } ] },
    "spanish.tilde" => { "key" => "spanish.tilde", "errors" => [ { "code" => "es_tilde", "implicates" => [] } ] }
  }.freeze

  def golden(name) = JSON.parse(GOLDEN.join(name).read)

  def context(subject = "english")
    Validation::Context.new(subject: subject, skill: ->(key) { SKILLS[key] }, graph_present: true,
                            source_line: ->(source, number) { { text: "i verbi al presente semplice e i verbi regolari", origin: "pdf" } if source == "seconda-example" && number == 200 },
                            reference_body: ->(_) { nil })
  end

  def run_item(item)
    Validation::Rules.with(practice: { min_static_instances: 2, min_instances_per_code: 1 }) do
      Validation::ItemRunner.new(files: F.files_for(item), context: context(item["subject"]), grandfathered: false).call
    end
  end

  def codes(result) = result.findings.map(&:code).uniq
  def at(result, code) = result.findings.select { |f| f.code == code }.map(&:field)
  def material = golden("item_choice.json")
  def translated = golden("item_choice_translated.json")
  def blank = golden("item_blank.json")

  # ---- items: the marker ----------------------------------------------------------------------------------------------------------

  test "an item that says translate_material: false needs no Italian for the sentence, the options and the final, and is clean" do
    result = run_item(material)
    assert_equal "passed", result.status, result.findings.select { |f| f.severity == "error" }.map(&:to_h).inspect
    assert_empty result.findings.select { |f| f.code.match?(/\AE-LANG|BILINGUAL/) }.map(&:to_h)
    first = result.instances.first
    assert_equal "On Saturdays I ___ my bed and then I ___ the shopping with Dad.", first[:display]["stem_en"]
    assert_nil first[:display]["stem_it"]
    assert_nil first[:display]["options"].first["text_it"]
  end

  test "the same item without the marker needs the Italian of the sentence, the options and the final" do
    item = material.except("translate_material")
    result = run_item(item)
    assert_equal [ "/instances/0/display/stem_en", "/instances/1/display/stem_en" ], at(result, "E-LANG-PAIR-MISSING").first(2)
    assert_includes at(result, "E-LANG-PAIR-MISSING"), "/instances/0/display/options/0/text"
    assert_includes at(result, "E-LANG-PAIR-MISSING"), "/instances/0/solution/final"
  end

  test "an Italian text beside form material is E-LANG-PAIR-ORPHAN, naming the field" do
    item = material
    item["instances"][0]["display"]["stem_it"] = "Il sabato io ___ il letto."
    item["instances"][0]["display"]["options"][0]["text_it"] = "fare / fare"
    item["instances"][1]["solution"]["final_it"] = "makes / do: la mamma fa una torta."
    found = at(run_item(item), "E-LANG-PAIR-ORPHAN")
    assert_equal [ "/instances/0/display/options/0/text_it", "/instances/0/display/stem_it", "/instances/1/solution/final_it" ], found.sort
    assert_match(/form material/, run_item(item).findings.find { |f| f.code == "E-LANG-PAIR-ORPHAN" }.message)
  end

  test "display.task_en + task_it is the paired task line of a material instance; one side alone is E-LANG-PAIR-MISSING" do
    item = material
    item["instances"][0]["display"]["task_en"] = "Choose the two forms."
    item["instances"][0]["display"]["task_it"] = "Scegli le due forme."
    assert_empty at(run_item(item), "E-SCHEMA") + at(run_item(item), "E-LANG-PAIR-MISSING") + at(run_item(item), "E-LANG-PAIR-ORPHAN")
    item["instances"][0]["display"].delete("task_it")
    assert_equal [ "/instances/0/display/task_en" ], at(run_item(item), "E-LANG-PAIR-MISSING")
  end

  test "the instruction, the hints, the messages and the solution steps of a material item stay paired" do
    item = material
    item["hints_it"].pop
    item.delete("answer_format_it")
    result = run_item(item)
    assert_equal [ "/answer_format_en", "/hints_en/2" ], at(result, "E-LANG-PAIR-MISSING").sort
  end

  test "translate_material in an item without bilingual: true is E-LANG-BILINGUAL-FLAG" do
    item = material.except("bilingual")
    assert_includes at(run_item(item), "E-LANG-BILINGUAL-FLAG"), "/translate_material"
  end

  test "a material sentence is not a word of the level; the same word in a hint is" do
    item = material
    item["instances"][0]["display"]["stem_en"] = "On Saturdays I ___ my brujúla and then I ___ the shopping."
    item["instances"][0]["hints_en"] = [ "The brujúla is a compass.", "Think of the nouns.", "Say it aloud." ]
    item["instances"][0]["hints_it"] = [ "La brujúla è una bussola.", "Pensa ai nomi.", "Dillo ad alta voce." ]
    levels = run_item(item).findings.select { |f| f.code == "W-LANG-LEVEL" && f.detail[:words].to_a.include?("brujúla") }
    assert_equal [ "/instances/0/hints_en/0" ], levels.map(&:field)
  end

  test "the Italian of a material sentence is not a negative instruction (W-NEGATIVE-STEM); the instruction is" do
    item = translated
    item["instances"][0]["display"]["stem_en"] = "Amy ___ watch TV on Sunday."
    item["instances"][0]["display"]["stem_it"] = "Amy non ___ la TV la domenica."
    assert_empty at(run_item(item), "W-NEGATIVE-STEM")
    item["prompt"]["stem_en"] = "Do not choose the same verb twice."
    item["prompt"]["stem_it"] = "Non scegliere due volte lo stesso verbo."
    assert_equal [ "/prompt/stem_it" ], at(run_item(item), "W-NEGATIVE-STEM")
  end

  # ---- the copy and the language of a translation ---------------------------------------------------------------------------------

  test "E-LANG-TRANSLATION-COPY and -LANG name the field that is wrong: the Italian one, `final` and `final_it`" do
    item = translated
    item["instances"][0]["solution"]["final_it"] = item["instances"][0]["solution"]["final"] + " and the key"
    item["instances"][1]["solution"]["final_it"] = "makes / do"
    item["instances"][1]["solution"]["final"] = "makes / do and then he does the shopping"
    item["instances"][1]["solution"]["final_it"] = "makes / do and then he does the shopping"
    result = run_item(item)
    copy = result.findings.find { |f| f.code == "E-LANG-TRANSLATION-COPY" }
    assert_equal "/instances/1/solution/final_it", copy.field
    assert_match(/final_it is the same text as final:/, copy.message)
    item = translated
    item["prompt"]["stem_it"] = "Choose the two words that fill the gaps, in the order they are needed."
    lang = run_item(item).findings.find { |f| f.code == "E-LANG-TRANSLATION-LANG" }
    assert_equal "/prompt/stem_it", lang.field
    assert_match(/\Astem_it is not Italian/, lang.message)
  end

  test "a target text that is only spans or quoted forms is no copy; nor is a glossary term the same in both languages" do
    assert_not VB.copy?("[[es:jamón]]", "[[es:jamón]]")
    assert_not VB.copy?("«jámon» «jamón» «jamon»", "«jámon» «jamón» «jamon»")
    assert VB.copy?("Escribe «jamón» con tilde", "Escribe «jamón» con tilde")
    findings = Validation::Findings.new
    VB.check(findings, { "glossary" => [ { "term_es" => "tilde", "term_it" => "tilde", "def_es" => "La marca de acento.", "def_it" => "Il segno dell'accento." } ] }, lang: "es")
    assert_empty findings.map(&:to_h)
  end

  test "E-LANG-TRANSLATION-LANG does not fire on Italian that quotes «-es» or two words of the language inside «...»" do
    assert_not VB.translation_lang?("Con «-es» il plurale cambia, e la parola del singolare resta.", "es")
    assert_not VB.translation_lang?("Con -es il plurale della parola «lápiz» si forma al posto del singolare.", "es")
    assert_not VB.translation_lang?("Si dice «the book» e «my pen and the desk» in inglese.", "en")
    assert VB.translation_lang?("Tengo que ir porque tiene hay muy", "es")
  end

  # ---- the target-language lint -----------------------------------------------------------------------------------------------------

  test "the sentences of a target text: a lone letter and a stop, .» ?» !», and a semicolon end one" do
    assert_equal [ "Acaba en n.", "Lleva tilde." ], VB.target_sentences("Acaba en n. Lleva tilde.")
    assert_equal [ "«I am thirteen.»", "Or «I am twelve.»" ], VB.target_sentences("«I am thirteen.» Or «I am twelve.»")
    assert_equal [ "«Where do you live?»", "She asks." ], VB.target_sentences("«Where do you live?» She asks.")
    assert_equal [ "Jack plays", "Sue sings", "Tom dances." ], VB.target_sentences("Jack plays; Sue sings; Tom dances.")
    assert_equal [ "Mr. Smith lives here." ], VB.target_sentences("Mr. Smith lives here.")
    long = "Se escribe con tilde si acaba en n. Lleva tilde si acaba en s. Y no lleva si acaba en otra letra."
    assert_equal 8, VB.target_report("es", long)[:long]
  end

  test "W-LANG-LEVEL skips quoted forms, spans, Italian words and pieces of words; the words it keeps are the text's" do
    known = []
    assert_empty VB.target_report("es", "Escribe «brujúla» y «volúmen» con tilde.", known: known)[:unknown]
    assert_empty VB.target_report("es", "Mira [[es:jámon]] y [[it:il prosciutto]].", known: known)[:unknown]
    assert_empty VB.target_report("es", "Mira ja-mon en sílabas: ja-mon, bru-ju-la, -es.", known: known)[:unknown]
    assert_equal %w[brujúla], VB.target_report("es", "Escribe brujúla con tilde.", known: known)[:unknown]
    assert_empty VB.target_report("en", "Is it a verb or a noun? Is it singular or plural?", known: known)[:unknown], "the grammar words are allowed"
    assert_empty VB.target_report("en", "My grandad and my aunt have thirteen pens and eighty books.", known: known)[:unknown], "the gaps the pilots named"
    assert_empty VB.target_report("es", "El plural es femenino y la sílaba lleva tilde.", known: known)[:unknown]
    assert_empty VB.target_report("en", "Brujúla is quoted", known: known, level: false)[:unknown]
  end

  test "W-ABSOLUTE on target text: always, never, nobody; siempre, nunca, nadie; not «only» or «solo» (the standard instruction), not in quotes" do
    assert_equal "always", VB.target_report("en", "We always add -s.")[:absolute]
    assert_equal "nobody", VB.target_report("en", "Nobody takes -s here.")[:absolute]
    assert_nil VB.target_report("en", "Write only the missing words.")[:absolute]
    assert_nil VB.target_report("en", "Only he takes -s. We do not only add -s: we also change the word.")[:absolute]
    assert_nil VB.target_report("en", "Write «always» and «never» in the gaps.")[:absolute]
    assert_equal "siempre", VB.target_report("es", "Siempre lleva tilde.")[:absolute]
    assert_equal "nadie", VB.target_report("es", "Nadie lleva tilde aquí.")[:absolute]
    assert_nil VB.target_report("es", "Escribe solo las palabras que faltan. Solo lleva tilde la última; no solo la última.")[:absolute]
    assert_nil VB.target_report("es", "Escribe sólo o solamente las palabras que faltan.")[:absolute]
  end

  test "a bilingual item's hint with an absolute word is W-ABSOLUTE; a material sentence with one is not" do
    item = material
    item["instances"][0]["hints_en"] = [ "Verbs always change.", "Think of the nouns.", "Say it aloud." ]
    item["instances"][0]["hints_it"] = [ "I verbi cambiano.", "Pensa ai nomi.", "Dillo ad alta voce." ]
    item["instances"][1]["display"]["stem_en"] = "Mum never ___ a cake and I ___ my homework."
    assert_equal [ "/instances/0/hints_en/0" ], at(run_item(item), "W-ABSOLUTE").grep(/_en/)
  end

  test "an item's target text is read with [[it:..]] quoted: no E-LESSON-LANG, no word of the level" do
    item = material
    item["instances"][0]["hints_en"] = [ "Say [[it:c'è]] and [[it:il gatto che è nero]] in English.", "Think of the nouns.", "Say it aloud." ]
    item["instances"][0]["hints_it"] = [ "Di' c'è e il gatto che è nero in inglese.", "Pensa ai nomi.", "Dillo ad alta voce." ]
    result = run_item(item)
    assert_empty at(result, "E-LESSON-LANG")
    assert_empty result.findings.select { |f| f.code == "W-LANG-LEVEL" && (f.detail[:words].to_a & %w[c'è gatto nero]).any? }.map(&:to_h)
  end

  # ---- the leak scans of the Italian layer ----------------------------------------------------------------------------------------------

  test "the Italian layer is scanned with distinctive needles only: «perché», «che», «quale» are not leaks" do
    item = golden("item_choice_translated.json")
    item["instances"][0]["display"]["options"][0]["text_it"] = "perché"
    item["instances"][0]["hints_it"] = [ "Pensa a quale verbo e perché serve.", "Guarda i nomi che ci sono.", "Dillo ad alta voce." ]
    item["instances"][0]["hints_en"] = [ "Think about which verb and why.", "Look at the nouns.", "Say it aloud." ]
    item["instances"][0]["display"]["stem_it"] = "Il sabato io ___ il letto, perché è sabato, e poi io ___ la spesa."
    result = run_item(item)
    assert_empty at(result, "E-SOLUTION-IN-DISPLAY")
    assert_empty at(result, "W-HINT-OPTION")
    item["instances"][0]["display"]["options"][0]["text_it"] = "rifare il letto"
    item["instances"][0]["display"]["stem_it"] = "Il sabato io ___ il letto, devo rifare il letto, e poi io ___ la spesa."
    assert_includes codes(run_item(item)), "E-SOLUTION-IN-DISPLAY"
  end

  test "W-SOLUTION-STORED-ORDER does not read the Italian «c'è» as option c" do
    checker = Validation::InstanceChecks.allocate
    assert_nil checker.send(:stored_order_phrase, "Nella risposta c'è il verbo giusto.", [])
    assert_nil checker.send(:stored_order_phrase, "Scegli la risposta c'è una forma.", [])
    assert checker.send(:stored_order_phrase, "Scegli l'opzione b.", [])
    assert checker.send(:stored_order_phrase, "Scegli la risposta c: è giusta.", [])
  end

  # ---- lessons ----------------------------------------------------------------------------------------------------------------------

  def source = GOLDEN.join("lesson_en.md").read

  def lesson(md = source, subject = "english") = Validation::LessonChecks.call(md, subject: subject, context: L.context(subject))

  def lesson_codes(outcome) = outcome.findings.map(&:code)

  def edit(from, to)
    assert_includes source, from
    source.sub(from, to)
  end

  test "the golden lesson follows the rule and is clean of the bilingual family" do
    found = lesson.findings.select { |f| f.code.start_with?("E-LANG-", "E-LESSON-LANG") || f.code == "E-SCHEMA" }
    assert_empty found.map { |f| [ f.code, f.field, f.message ] }
  end

  test "a check or an exercise with no marker needs the Italian of its options" do
    found = lesson(edit("translate_material: false\n", "")).findings.select { |f| f.code == "E-LANG-PAIR-MISSING" }
    assert_equal [ "/cards/0/blocks/1/options/0/text_en", "/cards/0/blocks/1/options/1/text_en" ], found.map(&:field).first(2)
    found = lesson(edit("  - translate_material: false\n    text_en:", "  - text_en:")).findings.select { |f| f.code == "E-LANG-PAIR-MISSING" }
    assert_includes found.map(&:field), "/cards/1/blocks/0/exercises/0/text_en"
  end

  test "an Italian text beside a material option of a lesson check is E-LANG-PAIR-ORPHAN" do
    outcome = lesson(edit('{id: a, text_en: "plays"}', '{id: a, text_en: "plays", text_it: "suona"}'))
    assert_includes outcome.findings.select { |f| f.code == "E-LANG-PAIR-ORPHAN" }.map(&:field), "/cards/0/blocks/1/options/0/text_it"
  end

  test "the marker in a lesson without bilingual: true is E-LANG-BILINGUAL-FLAG" do
    outcome = lesson(edit("bilingual: true\n", ""))
    assert_includes lesson_codes(outcome), "E-LANG-BILINGUAL-FLAG"
  end

  test "a mistake block's wrong and right are target-only; its why is a pair" do
    mistake = <<~MD

      ::: mistake
      group_en: "The -s"
      group_it: "La -s"
      wrong_en: "He play football."
      right_en: "He plays football."
      why_en: "After he, the verb takes -s."
      why_it: "Dopo he il verbo prende -s."
      :::
    MD
    md = source.sub("\n## Try it", "#{mistake}\n## Try it")
    found = lesson(md).findings.select { |f| f.code.start_with?("E-LANG-", "E-LESSON-LANG", "E-SCHEMA") }
    assert_empty found.map { |f| [ f.code, f.field, f.message ] }
    served = Lessons::StudentBody.project(Lessons::Parser2.call(md, Validation::Findings.new).body, revision_id: 1, seed: "preview")
    block = served["cards"][0]["blocks"].last
    assert_equal [ "He play football.", "He plays football." ], block.values_at("wrong_it", "right_it")
    assert_equal({ "The -s" => "La -s", "After he, the verb takes -s." => "Dopo he il verbo prende -s." }, block["tr"])
    broken = md.sub('why_it: "Dopo he il verbo prende -s."', "")
    assert_includes lesson(broken).findings.select { |f| f.code == "E-LANG-PAIR-MISSING" }.map(&:field).join(" "), "why_en"
  end

  test "a lone _it of a bilingual lesson is E-LANG-PAIR-ORPHAN and nothing else about the target text" do
    goals = "goals_en:\n  - \"**Use** can and should with the base verb\"\n"
    outcome = lesson(edit(goals, ""))
    about = outcome.findings.select { |f| f.field.to_s.include?("goals_en") || f.message.to_s.include?("goals_it") }
    assert_equal [ "E-LANG-PAIR-MISSING" ], about.map(&:code).uniq, about.map { |f| [ f.code, f.message ] }.inspect # a list entry without its text
    prompt = "prompt_en: \"Which form goes after can?\"\n"
    outcome = lesson(edit(prompt, "").sub("Quale forma va dopo can?", "Trovare dove batte la voce di can?"))
    about = outcome.findings.select { |f| f.field.to_s.include?("prompt_en") }
    assert_equal [ "E-LANG-PAIR-ORPHAN" ], about.map(&:code).uniq, about.map { |f| [ f.code, f.message ] }.inspect
    # the Italian words of the orphan (trovare, dove, batte, voce) are not read as target text anywhere in the target layer
    assert_empty outcome.findings.select { |f| f.code != "E-LANG-PAIR-ORPHAN" && f.message.to_s.match?(/trovare|batte|voce/) }.map { |f| [ f.code, f.field, f.message ] }
  end

  test "[[it:..]] in lesson target text is no E-LESSON-LANG and no word of the level" do
    md = edit("After a modal verb the next verb does not change: no -s, no to.", "Say [[it:c'è]] and [[it:il gatto che è nero]] after a modal verb: no -s.")
    md = md.sub("Dopo un verbo modale il verbo che segue non cambia: niente -s, niente to.", "Dopo un verbo modale il verbo non cambia: niente -s.")
    outcome = lesson(md)
    assert_empty outcome.findings.select { |f| %w[E-LESSON-LANG W-LANG-LEVEL].include?(f.code) }.map { |f| [ f.code, f.field, f.message ] }
  end

  test "lesson teaches_en|teaches_es hold 150 words, not 60" do
    words = ->(n) { (1..n).map { |i| "wordy#{i}" }.join(", ") }
    assert_empty lesson(edit("skills: [english.modals-can]\n", "skills: [english.modals-can]\nteaches_en: [#{words.(150)}]\n")).findings.select { |f| f.code == "E-SCHEMA" }.map(&:message)
    assert_includes lesson(edit("skills: [english.modals-can]\n", "skills: [english.modals-can]\nteaches_en: [#{words.(151)}]\n")).findings.map(&:code), "E-SCHEMA"
  end
end
