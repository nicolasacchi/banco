require "test_helper"

# D-402: the pairs of a bilingual revision. Lessons::Lang.pick/pair?, Lessons::Bilingual.pairs (the walker of the validators), .fold (the served lesson)
# and .italian_layer (what the answer-leak scans read). Against the golden fixtures of test/fixtures/lang that every slice of the work shares.
class BilingualTest < ActiveSupport::TestCase
  B = Lessons::Bilingual
  DIR = Rails.root.join("test/fixtures/lang")

  def fixture(name) = JSON.parse(DIR.join(name).read)

  # ---- Lang ---------------------------------------------------------------------------------------------------------------

  test "pick reads the target text of a pair and the Italian of a legacy or Italian-only field" do
    assert_equal "After can.", Lessons::Lang.pick({ "text_en" => "After can.", "text_it" => "Dopo can." }, "text")
    assert_equal "Después de can.", Lessons::Lang.pick({ "text_es" => "Después de can.", "text_it" => "Dopo can." }, "text")
    assert_equal "Dopo can.", Lessons::Lang.pick({ "text_it" => "Dopo can." }, "text")
    assert_equal "After can.", Lessons::Lang.pick({ "text_en" => "After can." }, "text")
    assert_nil Lessons::Lang.pick({}, "text")
    assert_equal "Dopo can.", Lessons::Lang.pick({ "text_en" => "After can.", "text_it" => "Dopo can." }, "text", lang: "es"), "no sibling in that language: the Italian"
  end

  test "pair? is the target sibling and the Italian together" do
    assert Lessons::Lang.pair?({ "stem_en" => "a", "stem_it" => "b" }, "stem")
    assert Lessons::Lang.pair?({ "stem_es" => "a", "stem_it" => "b" }, "stem")
    assert_not Lessons::Lang.pair?({ "stem_it" => "b" }, "stem")
    assert_not Lessons::Lang.pair?({ "stem_en" => "a" }, "stem")
    assert_not Lessons::Lang.pair?({ "stem_la" => "a", "stem_it" => "b" }, "stem"), "Latin is a quoted word, never a translated text"
  end

  test "TARGET_WORDS: one list per language, no word of Italian's own list, none shared" do
    assert_equal %w[en es], Lessons::Lang::TARGET_WORDS.keys
    Lessons::Lang::TARGET_WORDS.each_value { |words| assert_empty words & Lessons::Lang::ITALIAN_WORDS }
    assert_empty Lessons::Lang::TARGET_WORDS["en"] & Lessons::Lang::TARGET_WORDS["es"]
    assert_not Lessons::Lang.italian?("The cat and the dog"), "the Italian test does not fire on English"
  end

  test "TARGET_WORDS holds no word that is also Italian: del, es and son (an Italian text quoting «-es» must not be taken for Spanish)" do
    italian = Lessons::Lang::ITALIAN_FUNCTION_WORDS
    Lessons::Lang::TARGET_WORDS.each_value { |words| assert_empty words & italian }
    %w[del es son].each { |w| assert_not_includes Lessons::Lang::TARGET_WORDS["es"], w }
    assert_not Validation::Bilingual.translation_lang?("Con -es il plurale si aggiunge una sillaba, come in «bus» e «autobús»: del singolare.", "es")
    assert_not Validation::Bilingual.translation_lang?("La parola «the book» e «my brother and the dog» si legge così.", "en")
  end

  test "italian? does not count what is quoted: a [[it:..]] span, «...» or a span of a language" do
    assert_not Lessons::Lang.italian?("Say [[it:c'è]] and [[it:il gatto]] in English: there is.")
    assert_not Lessons::Lang.italian?("The Italian «il gatto che è nero» is a black cat.")
    assert Lessons::Lang.italian?("Il gatto che è nero.")
  end

  # ---- the walker ---------------------------------------------------------------------------------------------------------

  test "pairs of the practice fixtures: every text has both sides, in the pointer order of the document" do
    %w[item_choice_translated item_blank].each do |name|
      found = B.pairs(fixture("#{name}.json"), "en").to_a
      assert_operator found.size, :>=, 10, name
      assert found.all? { |_, _, target, italian| target.is_a?(String) && italian.is_a?(String) }, "#{name}: #{found.reject { |f| f[2] && f[3] }.inspect}"
    end
  end

  test "pairs names the pointer of the target field, the base and both texts; lists pair by index" do
    found = B.pairs(fixture("item_choice_translated.json"), "en").to_a
    assert_includes found, [ "/prompt/stem_en", "stem", "Choose the two words for the gaps, in the right order.",
                             "Scegli le due parole che completano la frase, nell'ordine in cui servono." ]
    assert_includes found, [ "/hints_en/1", "hints", "Think of the nouns: a bed, the shopping. Which verb is the usual partner of each one?",
                             "Pensa ai nomi: un letto, la spesa. Quale verbo è il compagno abituale di ciascuno?" ]
    assert_includes found, [ "/error_catalogue/0/message_en", "message", "Look at the nouns again. Which verb is the partner of each one?",
                             "Guarda di nuovo i nomi. Quale verbo è il compagno di ciascuno?" ]
    assert_includes found, [ "/instances/0/solution/steps/1/text_en", "text", "We say «do the shopping».", "Si dice «do the shopping»." ]
  end

  test "R2: the bare key of an option, a solution's final, a table and a quote is the target; its twin is <key>_it" do
    found = B.pairs(fixture("item_choice_translated.json"), "en").to_a
    assert_includes found, [ "/instances/0/display/options/0/text", "text", "make / do", "fare / fare" ]
    assert_includes found, [ "/instances/1/solution/final", "final", "makes / do", "makes / do: la mamma fa una torta e io faccio i compiti." ]
    doc = { "instances" => [ { "display" => { "table" => { "header" => [ "Verb", "Past" ], "header_it" => [ "Verbo", "Passato" ], "rows" => [ [ "go", "went" ] ], "rows_it" => [ [ "andare", "andò" ] ] },
                                              "quote" => { "ref" => "a:1", "text" => "To be", "text_it" => "Essere" } } } ] }
    got = B.pairs(doc, "en").to_a
    assert_includes got, [ "/instances/0/display/table/header/1", "header", "Past", "Passato" ]
    assert_includes got, [ "/instances/0/display/table/rows/0/0", "rows", "go", "andare" ]
    assert_includes got, [ "/instances/0/display/quote/text", "text", "To be", "Essere" ]
  end

  test "a bare text is not an R2 field outside the item keys that hold the subject's language" do
    assert_empty B.pairs({ "type" => "code", "text" => "print(1)", "text_it" => "stampa" }, "en").reject { |_, _, target, _| target.nil? }
  end

  test "orphans come out with a nil side, and a list that is shorter pairs by index" do
    got = B.pairs({ "stem_it" => "Una frase.", "hint_en" => "A hint.", "hints_en" => [ "One", "Two" ], "hints_it" => [ "Uno" ] }, "en").to_a
    assert_includes got, [ "/stem_en", "stem", nil, "Una frase." ]
    assert_includes got, [ "/hint_en", "hint", "A hint.", nil ]
    assert_includes got, [ "/hints_en/1", "hints", "Two", nil ]
    assert_includes got, [ "/hints_en/0", "hints", "One", "Uno" ]
  end

  test "the teacher's keys, the textbook pointer and target-only data are never pairs or orphans" do
    doc = { "description_it" => "Per il docente.", "choice_only_reason_it" => "x", "notes_it" => "y", "book_it" => "Cerca...", "teaches_en" => [ "mum" ],
            "rubric" => { "points" => [ { "expected_it" => "z" } ] }, "form_en" => "go", "pieces_it" => [ "a" ], "pieces_en" => [ "b" ] }
    assert_empty B.pairs(doc, "en").to_a
  end

  test "legacy pairs the figures draw (a dialogue line, a word_parts word) are pairs of text and gloss, form and label" do
    line = { "speaker" => "a", "text_en" => "Hi, I'm Tom.", "gloss_it" => "Ciao, sono Tom." }
    assert_equal [ [ "/text_en", "text", "Hi, I'm Tom.", "Ciao, sono Tom." ] ], B.pairs(line, "en").to_a
    word = { "form_en" => "hap|py", "label_it" => "felice" }
    assert_equal [ [ "/form_en", "form", "hap|py", "felice" ] ], B.pairs(word, "en").to_a
  end

  test "lang narrows the walk: a sibling in another language is not the subject's" do
    got = B.pairs({ "title_es" => "Hola", "title_it" => "Ciao" }, "en").to_a
    assert_equal [ [ "/title_en", "title", nil, "Ciao" ] ], got
    assert_equal [ [ "/title_es", "title", "Hola", "Ciao" ] ], B.pairs({ "title_es" => "Hola", "title_it" => "Ciao" }, "es").to_a
  end

  test "pairs of the lesson fixtures: every text has both sides" do
    %w[projected_lesson.json projected_lesson_es.json].zip(%w[en es]).each do |name, lang|
      found = B.pairs(fixture(name), lang).to_a
      assert_operator found.size, :>=, 12, name
      assert_empty found.reject { |_, _, target, italian| target && italian }, name
    end
  end

  # ---- fold ---------------------------------------------------------------------------------------------------------------

  test "fold of the projected english lesson is the served fixture" do
    assert_equal fixture("served_lesson.json"), B.fold(fixture("projected_lesson.json"), "en")
  end

  test "fold of the projected spanish lesson is the served fixture" do
    assert_equal fixture("served_lesson_es.json"), B.fold(fixture("projected_lesson_es.json"), "es")
  end

  test "fold puts the target in the renderer's _it slot and the Italian in the nearest table" do
    served = fixture("served_lesson.json")
    assert_equal "en", served["lang"]
    assert_equal "Modals: can and should", served["title_it"]
    assert_equal "I modali: can e should", served["tr"]["Modals: can and should"]
    card = served["cards"][0]
    assert_equal "Can + the base verb", card["title_it"]
    assert_equal "Can + il verbo base", card["tr"]["Can + the base verb"]
    assert_equal "Verbo base", card["tr"]["Base verb"]
    text, check = card["blocks"]
    assert_equal "Dopo un verbo modale il verbo che segue non cambia: niente -s, niente to.", text["tr"][text["text_it"]]
    assert_equal %w[play plays], check["options"].map { |o| o["text_it"] }
    assert_equal({ "Which form goes after can?" => "Quale forma va dopo can?" }, check["tr"], "the options are form material: no entry in tr")
    assert_nil check["prompt_en"], "no target sibling is left once folded"
  end

  test "fold: a list pairs by index and every table is the one of its own scope" do
    served = fixture("served_lesson.json")
    assert_equal [ "**Use** can and should with the base verb" ], served["goals_it"]
    assert_equal "**Usare** can e should con il verbo base", served["tr"]["**Use** can and should with the base verb"]
    assert_equal "verbo modale", served["tr"]["modal verb"]
    try = served["cards"][1]["blocks"][0]
    assert_equal "Prova tu", served["cards"][1]["tr"]["Try it"]
    assert_nil try["tr"]["You should ___ more water."], "the exercise's sentence is form material: no translation"
    assert_nil try["tr"]["drink"]
    assert_equal "You should ___ more water.", try["exercises"][0]["text_it"], "the target text is in the slot the renderer reads"
    assert_equal false, try["exercises"][0]["translate_material"]
    assert_nil served["cards"][1]["tr"]["drink"]
  end

  test "fold leaves what is not a pair as it was served: the textbook pointer, a legacy dialogue pair, a native mirror pair" do
    body = { "book_it" => "Cerca...", "cards" => [ { "n" => 1, "blocks" => [
      { "n" => 1, "type" => "dialogue", "lines" => [ { "speaker" => "a", "text_en" => "Hi.", "gloss_it" => "Ciao." } ] },
      { "n" => 2, "type" => "diagram", "diagram" => { "type" => "mirror", "rows" => [ { "pieces_it" => [ "ciao" ], "pieces_en" => [ "hi" ] } ] } }
    ] } ] }
    out = B.fold(body, "en")
    assert_equal "Cerca...", out["book_it"]
    assert_equal body["cards"][0]["blocks"], out["cards"][0]["blocks"]
    assert_nil out["tr"]
  end

  test "fold: a pair that is not whole (no Italian, or no target) is left alone, and two equal targets keep the first Italian" do
    body = { "title_en" => "Only English", "intro_it" => "Solo italiano", "cards" => [ { "n" => 1, "blocks" => [
      { "n" => 1, "type" => "text", "text_en" => "Go.", "text_it" => "Vai." }, { "n" => 2, "type" => "callout", "title_en" => "Go.", "title_it" => "Va'.", "text_en" => "x", "text_it" => "y" }
    ] } ] }
    out = B.fold(body, "en")
    assert_equal "Only English", out["title_en"]
    assert_equal "Solo italiano", out["intro_it"]
    assert_equal({ "Go." => "Vai." }, out["cards"][0]["blocks"][0]["tr"])
    assert_equal({ "Go." => "Va'.", "x" => "y" }, out["cards"][0]["blocks"][1]["tr"], "one table per block: no conflict across blocks")
    same = B.fold({ "cards" => [ { "n" => 1, "blocks" => [ { "n" => 1, "type" => "x", "a_en" => "Go.", "a_it" => "Vai.", "b_en" => "Go.", "b_it" => "Va'." } ] } ] }, "en")
    assert_equal({ "Go." => "Vai." }, same["cards"][0]["blocks"][0]["tr"])
  end

  test "fold does not change what it was given" do
    projected = fixture("projected_lesson.json")
    before = Marshal.load(Marshal.dump(projected))
    B.fold(projected, "en")
    assert_equal before, projected
  end

  test "the Italian of a served lesson never holds what the target layer does not show: tr has the Italian only for strings of the scope" do
    served = fixture("served_lesson.json")
    served["cards"].each do |card|
      card["blocks"].each do |block|
        shown = block.to_json
        block["tr"].each_key { |target| assert_includes shown, target.to_json[1..-2], "#{target} is in its block" }
      end
    end
  end

  # ---- the Italian layer --------------------------------------------------------------------------------------------------

  test "italian_layer of an item: the bare keys take the Italian, the R1 keys keep theirs and lose the target" do
    item = fixture("item_choice_translated.json")
    layer = B.italian_layer(item)
    display = layer["instances"][0]["display"]
    assert_equal "Il sabato io ___ il letto e poi io ___ la spesa con papà.", display["stem_it"]
    assert_nil display["stem_en"]
    assert_equal [ "fare / fare" ] * 4, display["options"].map { |o| o["text"] }
    assert_equal [ "o1", "o2", "o3", "o4" ], display["options"].map { |o| o["id"] }
    assert_nil display["options"][0]["text_it"]
    assert_equal "make / do: il sabato rifaccio il letto e faccio la spesa.", layer["instances"][0]["solution"]["final"]
    assert_nil layer["instances"][0]["solution"]["final_it"]
    assert_equal "Si dice «make the bed».", layer["instances"][0]["solution"]["steps"][0]["text_it"]
    assert_equal item["instances"][0]["answer"], layer["instances"][0]["answer"], "the key is an id and stays"
    assert_equal item["instances"][0]["errors"], layer["instances"][0]["errors"]
    assert_equal "Scegli le due parole che completano la frase, nell'ordine in cui servono.", layer["prompt"]["stem_it"]
    assert_nil layer["prompt"]["stem_en"]
    assert_equal item["hints_it"], layer["hints_it"]
    assert_nil layer["hints_en"]
  end

  test "italian_layer of the blank item: the blank stays in the Italian sentence, the key is not in it" do
    layer = B.italian_layer(fixture("item_blank.json"))
    assert_equal "Lei ___ a scuola in autobus.", layer["instances"][0]["display"]["stem_it"]
    assert_not_includes layer.to_json, "She ___"
    assert_equal "goes", layer["instances"][0]["answer"]
  end

  test "italian_layer leaves orphans, legacy pairs and a document with no pair as they are, and does not change its argument" do
    doc = { "stem_en" => "Only English", "line" => { "text_en" => "Hi.", "gloss_it" => "Ciao." }, "n" => 1 }
    assert_equal doc, B.italian_layer(doc)
    item = fixture("item_choice.json")
    before = Marshal.load(Marshal.dump(item))
    B.italian_layer(item)
    assert_equal before, item
  end

  # ---- form material (D-402) ------------------------------------------------------------------------------------------------------

  test "form material has no pair: the instance stem, the options, the final of an item that says translate_material: false" do
    item = fixture("item_choice.json")
    assert_equal false, item["translate_material"]
    found = B.pairs(item, "en").map { |pointer, base, _t, _i| [ pointer, base ] }
    assert_includes found, [ "/prompt/stem_en", "stem" ], "the instruction stays paired"
    assert_includes found, [ "/hints_en/0", "hints" ]
    assert_includes found, [ "/instances/0/solution/steps/1/text_en", "text" ], "a solution step stays paired"
    assert_empty found.select { |pointer, _| pointer.include?("/display/") || pointer.end_with?("/final") }, "no pair for the sentence, the options, the final"
    material = B.material_fields(item, "en").map { |pointer, base, tkey, ikey| [ pointer, base, tkey, ikey ] }
    assert_includes material, [ "/instances/0/display", "stem", "stem_en", nil ]
    assert_empty material.select { |_, _, _, ikey| ikey }, "no Italian beside the material"
    assert_includes B.material_pointers(item, "en"), "/instances/1/display/stem_en"
  end

  test "without the marker the same fields are pairs, and a marker only counts for what is under it" do
    translated = fixture("item_choice_translated.json")
    assert_empty B.material_fields(translated, "en").to_a
    assert_includes B.pairs(translated, "en").map { |_, base, _t, _i| base }, "final"
    below = B.pairs(fixture("item_choice.json")["instances"][0], "en", "/instances/0", false, true).map { |pointer, *| pointer } # a walk that starts below the root says it with `material`
    assert_includes below, "/instances/0/solution/steps/0/text_en"
    assert_empty below.grep(/display|final/)
  end

  test "a lesson mistake block's wrong and right are material with no marker; its why is a pair; a table says it with the marker" do
    mistake = { "type" => "mistake", "group_en" => "The -s", "group_it" => "La -s", "wrong_en" => "He play.", "right_en" => "He plays.", "why_en" => "He takes -s.", "why_it" => "He prende -s." }
    assert_equal %w[group why], B.pairs(mistake, "en").map { |_, base, _, _| base }
    assert_equal %w[right wrong], B.material_fields(mistake, "en").map { |_, base, _, _| base }.sort
    served = B.fold({ "cards" => [ { "n" => 1, "blocks" => [ mistake ] } ] }, "en")["cards"][0]["blocks"][0]
    assert_equal "He play.", served["wrong_it"]
    assert_equal "He plays.", served["right_it"]
    assert_equal({ "He takes -s." => "He prende -s.", "The -s" => "La -s" }, served["tr"])
    table = { "type" => "table", "translate_material" => false, "caption_en" => "Forms", "caption_it" => "Forme", "header" => [ "I", "he" ], "rows" => [ [ "have", "has" ] ] }
    assert_equal %w[caption], B.pairs(table, "en", "/cards/0/blocks/0").map { |_, base, _, _| base }
    assert_empty B.material_fields(table.except("translate_material"), "en", "/cards/0/blocks/0").to_a, "a table with no marker pairs its cells"
  end

  test "italian_layer of a material item has no stem and keeps the bare options and final the student reads" do
    item = fixture("item_choice.json")
    layer = B.italian_layer(item)
    display = layer["instances"][0]["display"]
    assert_nil display["stem_en"]
    assert_nil display["stem_it"]
    assert_equal item["instances"][0]["display"]["options"].map { |o| o["text"] }, display["options"].map { |o| o["text"] }
    assert_equal "make / do", layer["instances"][0]["solution"]["final"]
    assert_equal "Scegli le due parole che completano la frase, nell'ordine in cui servono.", layer["prompt"]["stem_it"]
  end

  # ---- the rules and the codes --------------------------------------------------------------------------------------------

  test "the rules have the lang block, spanish cut over (D-404, v14) and english not, and the codes of D-402 are in the registry" do
    assert_equal %w[spanish], Validation::Rules.get(:lang, :bilingual_required)
    assert_equal 14, Validation::Rules.version
    codes = YAML.load_file(Rails.root.join("config/banco/error_codes.yml")).fetch("validation")
    %w[E-LANG-BILINGUAL-REQUIRED E-LANG-BILINGUAL-FLAG E-LANG-PAIR-MISSING E-LANG-PAIR-ORPHAN E-LANG-PAIR-SHAPE E-LANG-PAIR-CONFLICT
       E-LANG-TRANSLATION-LANG E-LANG-TRANSLATION-COPY W-LANG-PAIR-CONFLICT W-LANG-SPAN-REDUNDANT W-LANG-LEVEL W-TOPIC-LANG-MIXED].each { |code| assert codes.key?(code), code }
  end
end
