require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/lesson2_fixtures"

# D-402, round 7 of the tooling (slice A, validation, level, copy and briefs): what the third wave of authors met. Each rule that was narrowed has its false
# positive and, next to it, the true positive it keeps. The lessons are the golden ones of test/fixtures/lang with one edit each; the items are the golden
# items with one edit each.
class BilingualTooling7aTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  V = ValidationFixtures
  VB = Validation::Bilingual
  KW = Validation::KeyWords
  LX = Lessons::Lexicon
  LEXICON = Rails.root.join("config/banco/lexicon")

  SKILLS = {
    "english.make-do" => { "key" => "english.make-do", "errors" => [ { "code" => "en_make_do_swap", "implicates" => [] }, { "code" => "en_make_for_both", "implicates" => [] } ] },
    "english.present-simple" => { "key" => "english.present-simple", "errors" => [ { "code" => "en_missing_third_s", "implicates" => [] } ] },
    "english.composite" => { "key" => "english.composite", "composite_of" => [],
                             "errors" => [ { "code" => "en_missing_third_s", "implicates" => %w[english.be english.have] } ] },
    "english.be" => { "key" => "english.be", "errors" => [] },
    "english.have" => { "key" => "english.have", "errors" => [] }
  }.freeze

  def en = DIR.join("lesson_en.md").read
  def es = DIR.join("lesson_es.md").read
  def en_figures = DIR.join("lesson_en_figures.md").read
  def check(md, subject = "english") = Validation::LessonChecks.call(md, subject: subject, context: F.context(subject))
  def found(outcome, *codes) = outcome.findings.select { |f| codes.include?(f.code) }
  def level_fields(outcome, word) = found(outcome, "W-LANG-LEVEL").select { |f| f.detail[:words].to_a.include?(word) }.map(&:field)
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
  def item_levels(item) = run_item(item).findings.select { |f| f.code == "W-LANG-LEVEL" }.flat_map { |f| f.detail[:words].to_a.map { |w| [ f.field, w ] } }

  # ---- 1. teaches_<lang> and the forms of an item match by stem --------------------------------------------------------------------

  test "a form of a word the text teaches is no level word: its Snowball stem is the stem of the taught word" do
    assert_equal %w[perambulé perambulamos], LX.unknown("es", "Perambulé perambulamos.")
    assert_empty LX.unknown("es", "Perambulé perambulamos.", known: %w[perambular])
    assert_equal %w[perambulated], LX.unknown("en", "They perambulated every day.", known: [])
    assert_empty LX.unknown("en", "They perambulated every day.", known: %w[perambulate])
    assert_equal %w[gallivanted], LX.unknown("en", "They gallivanted every day.", known: %w[perambulate]), "another word keeps its warning"
  end

  test "an option of an item is matched by the stem of teaches_en: «perambulates» is covered by «perambulate»" do
    item = golden("item_choice.json")
    item["instances"][0]["display"]["options"] << { "id" => "o5", "text" => "make / perambulates" }
    assert_includes item_levels(item), [ "/instances/0/display/options/4/text", "perambulates" ]
    assert_not_includes item_levels(item.merge("teaches_en" => [ "perambulate" ])).map(&:last), "perambulates"
    assert_includes item_levels(item.merge("teaches_en" => [ "gallivant" ])).map(&:last), "perambulates", "a taught word of another stem is no cover"
  end

  test "the text of a lesson check is matched by the stem of teaches_en, the option as well as the running text" do
    md = en.sub(%(  - {id: b, text_en: "play"}), %(  - {id: b, text_en: "play"}\n  - {id: c, text_en: "gallivanted"}))
    assert_equal [ "/cards/0/blocks/1/options/2/text_en" ], level_fields(check(md), "gallivanted")
    assert_empty level_fields(check(md.sub("bilingual: true\n", "bilingual: true\nteaches_en: [gallivant]\n")), "gallivanted")
  end

  # ---- 2. irregular forms and the school words -------------------------------------------------------------------------------------

  test "an irregular form is read as its verb: slept, ate, swam; fuiste, duermo, traje" do
    %w[slept ate swam flew].each do |word|
      assert_not LX.words("en").include?(word), "#{word} is outside the first 3000, the table brings it in"
      assert LX.known?("en", word), word
    end
    %w[fuiste duermo traje].each do |word|
      assert_not LX.words("es").include?(word), word
      assert LX.known?("es", word), word
    end
    assert_equal %w[ser ir], LX.verbs("es", "fui"), "a form of two verbs stands under both"
    assert_equal [ "sleep" ], LX.verbs("en", "slept")
    assert_empty LX.verbs("en", "gallivanted")
    assert_not LX.known?("en", "gallivanted"), "a regular rare word is still a level word"
    assert_empty LX.unknown("en", "She slept and he swam.")
  end

  test "an irregular form of a taught verb is no level word, a regular word around it still is" do
    assert_includes LX.unknown("en", "They froze the gallivants."), "froze"
    assert_equal %w[gallivants], LX.unknown("en", "They froze the gallivants.", known: %w[freeze])
    assert_empty LX.unknown("en", "They froze the gallivants.", known: %w[freeze gallivant])
  end

  test "the irregular form in a material option of a lesson and an item is no W-LANG-LEVEL" do
    md = en.sub(%(  - {id: b, text_en: "play"}), %(  - {id: b, text_en: "play"}\n  - {id: c, text_en: "slept"}))
    assert_empty level_fields(check(md), "slept")
    item = golden("item_choice.json")
    item["instances"][0]["display"]["options"] << { "id" => "o5", "text" => "make / slept" }
    assert_not_includes item_levels(item).map(&:last), "slept"
  end

  test "the A2 school words are an allowlist of their own: exam, piano, guitar, homework, guitarra, horario" do
    %w[exam piano guitar calculator].each do |word|
      assert_not LX.words("en").include?(word), word
      assert LX.known?("en", word), word
    end
    %w[piano guitarra horario].each do |word|
      assert_not LX.words("es").include?(word), word
      assert LX.known?("es", word), word
    end
    assert_empty LX.unknown("en", "I have an exam and my piano lesson after homework.")
    assert_includes LX.unknown("en", "They gallivant with the guitar."), "gallivant"
    %w[en_school es_school en_irregular es_irregular].each { |name| assert LEXICON.join("#{name}.txt").file?, name }
    readme = LEXICON.join("README.md").read
    %w[en_school.txt es_school.txt en_irregular.txt es_irregular.txt].each { |name| assert_includes readme, name }
    assert_operator LEXICON.join("en_school.txt").readlines.count { |l| !l.start_with?("#") && l.strip != "" }, :<=, 60, "the school list is short"
  end

  # ---- 3. the wrong side of a mistake ------------------------------------------------------------------------------------------------

  MISTAKE = <<~MD.freeze

    ::: mistake
    group_en: "The -s"
    group_it: "La -s"
    wrong_en: "%<wrong>s"
    right_en: "%<right>s"
    why_en: "After he, the verb takes -s."
    why_it: "Dopo he il verbo prende -s."
    :::
  MD

  test "the wrong side of a mistake is a deliberate misspelling: no W-LANG-LEVEL there; the right side is read as before" do
    md = en.sub("\n## Try it", "#{format(MISTAKE, wrong: 'He gallivanted football.', right: 'He gallivanted football.')}\n## Try it")
    assert_equal [ "/cards/0/blocks/2/right_en" ], level_fields(check(md), "gallivanted"), "only the right form is held to the level"
    clean = en.sub("\n## Try it", "#{format(MISTAKE, wrong: 'He plaied football.', right: 'He plays football.')}\n## Try it")
    assert_empty level_words(check(clean))
  end

  # ---- 4. word_parts: the joined word -------------------------------------------------------------------------------------------------

  def decode(form, parts) = DIR.join("lesson_en_decode.md").read.sub("form_en: 'play|ed'", "form_en: '#{form}'").sub('parts_it: ["giocare", "passato"]', "parts_it: #{parts}")

  test "a word_parts word is read as the joined word: «writ|ing» is «writing», not «writ» and «ing»" do
    outcome = check(decode("writ|ing", '["scrivere", "gerundio"]'))
    assert_empty level_words(outcome).grep(/\Awrit\z|\Aing\z/)
    assert_equal %w[gallivanting], level_words(check(decode("gallivant|ing", '["girovagare", "gerundio"]'))), "the joined word is still held to the level"
    assert_equal [], level_words(check(decode("pl[a]y|ed", '["giocare", "passato"]'))), "a mark inside the notation is not a letter of the word"
  end

  # ---- 5. the copy check -------------------------------------------------------------------------------------------------------------

  test "a short text of shared words is no copy, whatever its length: «Haber cambia con la persona», «La tilde», «presente»" do
    [ "Haber cambia con la persona", "La tilde", "La persona", "presente", "indefinido" ].each do |text|
      assert_not VB.copy?(text, text, "es"), text
    end
    assert VB.copy?("Perambular cambia con la persona", "Perambular cambia con la persona", "es"), "a word outside the language's easy words is not a shared one"
    assert_not VB.copy?("Perambular cambia con la persona", "Perambular cambia con la persona", "es", known: %w[perambular]), "the glossary and teaches_es say it is the lesson's own word"
    assert VB.copy?("El gato come con la persona", "El gato come con la persona", "es"), "«el» is not Italian"
    assert VB.copy?("Haber cambia con la persona de la casa", "Haber cambia con la persona de la casa", "es"), "more than six words is a sentence to translate"
    assert VB.copy?("Haber cambia con ñu", "Haber cambia con ñu", "es"), "a letter that Italian lacks"
  end

  test "in a lesson, an Italian title equal to the Spanish one made of shared words passes; the same with a function word Italian lacks is a copy" do
    shared = es.sub(/^title_es: .*$/, 'title_es: "Haber cambia con la persona"').sub(/^title_it: .*$/, 'title_it: "Haber cambia con la persona"')
    assert_not_equal es, shared
    assert_empty found(check(shared, "spanish"), "E-LANG-TRANSLATION-COPY")
    copied = es.sub(/^title_es: .*$/, 'title_es: "El gato cambia con la persona"').sub(/^title_it: .*$/, 'title_it: "El gato cambia con la persona"')
    assert_equal [ "/title_it" ], found(check(copied, "spanish"), "E-LANG-TRANSLATION-COPY").map(&:field)
  end

  # ---- 6. the key scans ---------------------------------------------------------------------------------------------------------------

  test "KeyWords: a frequent word and a phrase of everyday words are everyday keys; a plain content word is not" do
    assert KW.everyday?("hace", "es"), "«hace» is the 68th word of Spanish"
    assert KW.everyday?("have to", "en")
    assert KW.everyday?("hay que", "es")
    assert KW.everyday?("must", "en")
    assert_not KW.everyday?("goes", "en")
    assert_not KW.everyday?("goes to", "en"), "a phrase is everyday only when each of its words is"
    assert_not KW.everyday?("have to go home now", "en"), "no more than three words"
    assert_not KW.everyday?("hace", nil)
    assert KW.leak?("Write have to here.", "have to"), "named as the answer"
    assert KW.leak?("Use «hace» here.", "hace"), "quoted"
    assert_not KW.leak?("Si hace falta, lee otra vez.", "hace")
    assert_not KW.leak?("Think about have to and the rule.", "have to")
  end

  def phrase_item
    item = golden("item_blank.json")
    item["instances"][1]["display"] = { "stem_en" => "My brother ___ study on Fridays.", "stem_it" => "Mio fratello ___ studiare il venerdì." }
    item["instances"][1]["answer"] = "has to"
    item["instances"][1]["errors"] = [ { "code" => "en_missing_third_s", "value" => "have to" } ]
    item["instances"][1]["solution"] = { "steps" => [ { "text_en" => "My brother is «he»: the verb changes.", "text_it" => "Mio fratello è «he»: il verbo cambia." } ], "final" => "has to",
                                         "final_it" => "has to: mio fratello deve studiare il venerdì." }
    item["instances"][0]["display"] = { "stem_en" => "She ___ study every day.", "stem_it" => "Lei ___ studiare ogni giorno." }
    item["instances"][0]["answer"] = "has to"
    item["instances"][0]["errors"] = [ { "code" => "en_missing_third_s", "value" => "have to" } ]
    item["instances"][0]["solution"] = { "steps" => [ { "text_en" => "She is «she»: the verb changes.", "text_it" => "Lei è «she»: il verbo cambia." } ], "final" => "has to",
                                         "final_it" => "has to: lei deve studiare ogni giorno." }
    item
  end

  test "E-SUPPORT-LEAK and W-MESSAGE-GIVES-KEY: «have to» in the support and the message of a modals item is no leak; named as the answer or with the frame it still is" do
    item = phrase_item
    item["answer_format_en"] = "Write the whole form, like the one for the rule."
    item["answer_format_it"] = "Scrivi la forma intera, come quella della regola."
    item["error_catalogue"][0]["message_en"] = "Think about have to and the subject."
    item["error_catalogue"][0]["message_it"] = "Pensa al soggetto e alla regola."
    result = run_item(item)
    assert_empty at(result, "E-SUPPORT-LEAK", "W-MESSAGE-GIVES-KEY")
    named = Marshal.load(Marshal.dump(item))
    named["answer_format_en"] = "Write has to here."
    assert_equal [ "/answer_format_en" ], at(run_item(named), "E-SUPPORT-LEAK")
    framed = Marshal.load(Marshal.dump(item))
    framed["error_catalogue"][0]["message_en"] = "She has to study every day."
    assert_equal [ "/error_catalogue/0/message_en" ], at(run_item(framed), "W-MESSAGE-GIVES-KEY")
  end

  # ---- 8. the 12-word cap leaves what a text quotes ------------------------------------------------------------------------------------------------

  QUOTES = { "«»" => %w[« »], "“”" => %w[“ ”], "\"\"" => %w[" "] }.freeze

  def quoted_item(open, close)
    item = golden("item_blank.json")
    en = "Look at #{open}she runs to school every day with her best friend#{close} again."
    it = "Guarda #{open}lei corre a scuola ogni giorno con la sua migliore amica#{close} di nuovo."
    item["hints_en"][1] = en
    item["hints_it"][1] = it
    item["prompt"]["stem_en"] = en
    item["prompt"]["stem_it"] = it
    item["error_catalogue"][0]["message_en"] = en
    item["error_catalogue"][0]["message_it"] = it
    item["instances"][0]["solution"]["steps"][0]["text_en"] = en
    item["instances"][0]["solution"]["steps"][0]["text_it"] = it
    item
  end

  test "a quotation of any of the three kinds is not counted in the cap: item prompts, hints, messages and steps, and a lesson text, read it alike" do
    QUOTES.each do |name, (open, close)|
      assert_empty at(run_item(quoted_item(open, close)), "E-READ"), "item, #{name}"
      md = en.sub("After a modal verb the next verb does not change: no -s, no to.", "After a modal verb, look at #{open}she runs to school every day with her best friend#{close} again.")
      md = md.sub("Dopo un verbo modale il verbo che segue non cambia: niente -s, niente to.", "Dopo un verbo modale guarda #{open}lei corre a scuola ogni giorno con la sua migliore amica#{close} di nuovo.")
      assert_empty found(check(md), "E-READ"), "lesson, #{name}"
    end
    bare = quoted_item("", "")
    assert_not_empty at(run_item(bare), "E-READ"), "the same words with no quotation mark are counted"
  end

  # ---- 9. E-LANG-PAIR-CONFLICT ---------------------------------------------------------------------------------------------------------

  def conflicts(doc)
    findings = Validation::Findings.new
    VB.check(findings, doc, lang: "en")
    findings.select { |f| f.code.end_with?("PAIR-CONFLICT") }.map { |f| [ f.code, f.field ] }
  end

  test "the same target text with the same Italian twice is no conflict; with a different Italian it is, and with the same words after a stop or markup it is not" do
    doc = ->(second) { { "steps" => [ { "do_en" => "Is she tired today after the long walk?", "do_it" => "Lei è stanca oggi dopo la lunga passeggiata?" } ], "lines" => [ { "text_en" => "Is she tired today after the long walk?", "text_it" => second } ] } }
    assert_empty conflicts(doc.call("Lei è stanca oggi dopo la lunga passeggiata?"))
    assert_empty conflicts(doc.call("lei è **stanca** oggi dopo la lunga passeggiata"))
    assert_equal [ [ "E-LANG-PAIR-CONFLICT", "/lines/0/text_en" ] ], conflicts(doc.call("È stanca oggi lei, dopo la lunga camminata?"))
  end

  # ---- 10. glossary terms ---------------------------------------------------------------------------------------------------------------

  test "a [[g:..]] term may start with a hyphen and hold parentheses" do
    assert_equal [ { "t" => "gloss", "term" => "-ing form" } ], Lessons::Markup.parse("[[g:-ing form]]", roles: true).first["children"]
    assert_equal [ { "t" => "gloss", "term" => "imperativo (modo del verbo)" } ], Lessons::Markup.parse("[[g:imperativo (modo del verbo)]]", roles: true).first["children"]
    assert_raises(Lessons::Markup::Refused) { Lessons::Markup.parse("[[g:-]]", roles: true) }
    assert_raises(Lessons::Markup::Refused) { Lessons::Markup.parse("[[g:due 2]]", roles: true) }
  end

  test "a lesson glossary whose terms are «-ing form» and «imperative (mood)» is read in both layers" do
    md = en.sub(/^glossary:\n.*\n/, "glossary:\n  - {term_en: \"-ing form\", term_it: \"forma in -ing\", def_en: \"A verb with ing.\", def_it: \"Un verbo con ing.\"}\n  - {term_en: \"imperative (mood)\", term_it: \"imperativo (modo)\", def_en: \"A verb that gives an order.\", def_it: \"Un verbo che dà un ordine.\"}\n")
    md = md.sub("After a modal verb the next verb does not change: no -s, no to.", "After a modal verb use the [[g:-ing form]] never; the [[g:imperative (mood)]] has no subject.")
    md = md.sub("Dopo un verbo modale il verbo che segue non cambia: niente -s, niente to.", "Dopo un verbo modale non usare la [[g:forma in -ing]]; l'[[g:imperativo (modo)]] non ha soggetto.")
    outcome = check(md)
    assert_empty found(outcome, "E-LESSON-BLOCK", "E-LESSON-MARKUP", "E-SCHEMA", "E-LANG-PAIR-SHAPE").map { |f| [ f.code, f.field, f.message ] }
  end

  # ---- 11. an empty cell of a table ---------------------------------------------------------------------------------------------------------

  test "an empty cell of a schema table is allowed (drawn blank), with the Italian cell empty too" do
    md = en_figures.sub('  - ["he, she", "Has she got a dog?"]', '  - ["he, she", ""]').sub('  - ["lui, lei", "Ha un cane?"]', '  - ["lui, lei", ""]')
    assert_not_equal en_figures, md
    outcome = check(md)
    assert_empty found(outcome, "E-SCHEMA", "E-LESSON-BLOCK", "E-LANG-PAIR-MISSING", "E-LANG-PAIR-ORPHAN", "E-LANG-PAIR-SHAPE").map { |f| [ f.code, f.field, f.message ] }
    corner = en_figures.sub('header: ["Subject", "Question"]', 'header: ["", "Question"]').sub('header_it: ["Soggetto", "Domanda"]', 'header_it: ["", "Domanda"]')
    assert_empty found(check(corner), "E-SCHEMA", "E-LESSON-BLOCK").map { |f| [ f.code, f.field, f.message ] }, "a blank corner header too"
  end

  # ---- 12. word_parts decode with parts_it alone -----------------------------------------------------------------------------------------------

  test "a decode word with parts_it and no meaning_it passes the dry run and, in the browser, the layout" do
    md = DIR.join("lesson_es_decode.md").read
    assert_includes md, "des|cubrir"
    outcome = check(md, "spanish")
    assert_empty found(outcome, "E-LESSON-DIAGRAM", "E-LANG-PAIR-MISSING", "E-LANG-PAIR-ORPHAN").map { |f| [ f.code, f.field, f.message ] }
    word = { "type" => "word_parts", "alt_it" => "Una parola.", "view" => "decode", "words" => [ { "form_es" => "des|cubrir", "parts_it" => [ "il contrario", "coprire" ] } ] }
    assert_empty Lessons::Diagrams.layout_findings(word, subject: "spanish") if Lessons::Diagrams.respond_to?(:layout_findings)
    long = word.merge("words" => [ word["words"][0].merge("meaning_it" => "una parola che vuol dire proprio tanto di quello che ha dentro di sé") ])
    c = Lessons::Diagrams::Collector.new("spanish")
    Lessons::Diagrams::WordParts.state(long, c, "")
    assert_equal [ "/words/0/meaning_it" ], c.findings.map(&:path), "a meaning, when written, is still short"
  end

  # ---- 13. E-COMPOSITE and W-ERROR-NOT-IN-GRAPH -----------------------------------------------------------------------------------------------------

  test "implicates copied from the graph clear W-ERROR-NOT-IN-GRAPH and are no E-COMPOSITE; the ones the item invents are" do
    item = golden("item_blank.json").merge("skill" => "english.composite")
    item["error_catalogue"][0]["implicates"] = %w[english.be english.have]
    result = run_item(item)
    assert_empty at(result, "W-ERROR-NOT-IN-GRAPH", "E-COMPOSITE")
    item["error_catalogue"][0]["implicates"] = []
    assert_equal [ "/error_catalogue/0/implicates" ], at(run_item(item), "W-ERROR-NOT-IN-GRAPH"), "the graph says two, the item says none: still a warning"
    assert_empty at(run_item(item), "E-COMPOSITE")
    invented = golden("item_blank.json")
    invented["error_catalogue"][0]["implicates"] = %w[english.be english.have]
    result = run_item(invented)
    assert_equal [ "/skill" ], at(result, "E-COMPOSITE"), "the graph says none and the item adds two prerequisites to a skill that is not composite"
    assert_equal [ "/error_catalogue/0/implicates" ], at(result, "W-ERROR-NOT-IN-GRAPH")
  end
end
