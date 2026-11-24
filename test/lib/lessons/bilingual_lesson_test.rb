require "test_helper"
require_relative "../../support/lesson2_fixtures"

# D-402, slice 3: the lessons of english and spanish in the target language, each text with its authored Italian. The parse (heading tags `it=` and `short_it=`,
# `# Part {it=}`, the `::: it` fence, `[[it:]]`, the front matter siblings), the served body (the whitelist projection with siblings, then Bilingual.fold), the replies
# of the check endpoint with their own `tr`, and the checks, against the golden fixtures of test/fixtures/lang. A legacy lesson is run by the older tests.
class BilingualLessonTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  # The fixtures' choice options were shuffled by the seed of this revision id (Diagnosis::Rekey, student "preview").
  REVISION = { "en" => 1, "es" => 0 }.freeze
  SUBJECT = { "en" => "english", "es" => "spanish" }.freeze

  def fixture(name) = JSON.parse(DIR.join(name).read)
  def source(lang) = DIR.join("lesson_#{lang}.md").read
  def suffix(lang) = lang == "en" ? "" : "_es"
  def json(value) = JSON.parse(JSON.generate(value))

  def parse(md, findings = Validation::Findings.new) = Lessons::Parser2.call(md, findings)

  def check(md, subject = "english") = Validation::LessonChecks.call(md, subject: subject, context: F.context(subject))

  def codes(outcome) = outcome.findings.map(&:code)

  # The golden lesson with one edit.
  def edit(lang, from, to)
    md = source(lang)
    assert_includes md, from
    md.sub(from, to)
  end

  # ---- the golden fixtures ----------------------------------------------------------------------------------------------

  %w[en es].each do |lang|
    test "#{lang}: the golden lesson parses with no finding, and its body keeps both texts" do
      findings = Validation::Findings.new
      body = parse(source(lang), findings).body
      assert_empty findings.map(&:to_h)
      assert_equal true, body["bilingual"]
      assert_equal "Can + the base verb", body["cards"][0]["title_en"] if lang == "en"
      assert body["cards"][0]["blocks"][0]["text_#{lang}"].present?
      assert body["cards"][0]["blocks"][0]["text_it"].present?
    end

    test "#{lang}: the projection with siblings is the golden projected lesson, and the fold is the golden served lesson" do
      body = parse(source(lang)).body
      projected = Lessons::StudentBody.project(body.merge("bilingual" => false), revision_id: REVISION[lang], seed: "preview")
      assert_equal fixture("projected_lesson#{suffix(lang)}.json"), json(projected)
      served = Lessons::StudentBody.project(body, revision_id: REVISION[lang], seed: "preview")
      assert_equal fixture("served_lesson#{suffix(lang)}.json"), json(served)
      assert_equal lang, served["lang"]
    end

    test "#{lang}: no answer-side text reaches the served body, in either language" do
      body = parse(source(lang)).body
      served = JSON.generate(Lessons::StudentBody.project(body, revision_id: REVISION[lang], seed: "preview"))
      %w[answer explain_it explain_en explain_es message_it message_en message_es solution_it solution_en solution_es final_it final_en final_es].each do |key|
        assert_not_includes served, "\"#{key}\"", key
      end
      assert_not_includes served, "After can the verb stays as it is" if lang == "en"
    end

    test "#{lang}: the golden lesson gives no finding about its pairs, its spans or its language" do
      outcome = check(source(lang), SUBJECT[lang])
      mine = outcome.findings.select { |f| f.code.start_with?("E-LANG-", "E-LESSON-LANG") || f.code == "E-LESSON-MARKUP" || f.code == "E-LESSON-ROLE" || f.code == "E-SCHEMA" }
      assert_empty mine.map { |f| [ f.code, f.field, f.message ] }
    end
  end

  test "the part titles reach the served body folded, with their Italian in the body's tr" do
    md = source("en").sub("## Can + the base verb", "# Modals {it=\"I modali\"}\n\n## Can + the base verb").sub("## Try it", "# Practice {it=\"Esercizi\"}\n\n## Try it")
    parsed = parse(md)
    assert_equal [ [ "Modals", "I modali" ], [ "Practice", "Esercizi" ] ], parsed.parts.map { |p| p.values_at("title_en", "title_it") }
    body = parse(source("en")).body.merge("parts" => parsed.parts.map { |p| p.slice("n", "title_en", "title_it") })
    served = Lessons::StudentBody.project(body, revision_id: 1, seed: "preview")
    assert_equal [ { "n" => 1, "title_it" => "Modals" }, { "n" => 2, "title_it" => "Practice" } ], served["parts"]
    assert_equal "I modali", served["tr"]["Modals"]
  end

  # ---- the parse ----------------------------------------------------------------------------------------------------------

  test "the card tag takes it= and short_it= only in a bilingual lesson, and short_it is 2 to 28 characters" do
    legacy = F.read("base.md").sub(/^(## .+) \{(\w+)/, "\\1 {\\2 it=\"Titolo\"").sub(/\Aschema/, "schema")
    findings = Validation::Findings.new
    Lessons::Parser2.call(legacy, findings)
    assert(findings.any? { |f| f.code == "E-LESSON-CARD" && f.message.include?("bilingual") }, findings.map(&:message).inspect)

    findings = Validation::Findings.new
    parse(edit("en", 'short_it="Verbo base"', 'short_it="x"'), findings)
    assert(findings.any? { |f| f.code == "E-LESSON-CARD" && f.message.include?("short_it") })
  end

  test "a ::: it fence belongs to a bilingual lesson, follows a text, a callout or a summary, and translates it once" do
    legacy = F.read("base.md").sub(/^(::: check)/, "::: it\nciao\n:::\n\n\\1")
    findings = Validation::Findings.new
    Lessons::Parser2.call(legacy, findings)
    assert(findings.any? { |f| f.code == "E-LESSON-BLOCK" && f.message.include?("bilingual") })

    stray = edit("en", "::: check choice", "::: it\nUn'altra.\n:::\n\n::: check choice")
    findings = Validation::Findings.new
    parse(stray, findings)
    assert(findings.any? { |f| f.code == "E-LESSON-BLOCK" && f.message.include?("right before it") }, findings.map(&:message).inspect)

    twice = edit("en", "::: check choice", "::: it\nAncora.\n:::\n\n::: check choice")
    findings = Validation::Findings.new
    body = parse(twice, findings).body
    assert(findings.any? { |f| f.message.include?("::: it") || f.message.include?("already") }, "a second fence is refused: #{findings.map(&:message).inspect}")
    assert_nil body
  end

  test "a callout and a summary have their Italian in a fence, a titled fence adds it=, a more block too" do
    md = source("en").sub("::: check choice", <<~MD.chomp)
      ::: callout tip "Remember" it="Ricorda"
      Use the base verb.
      :::

      ::: it
      Usa il verbo base.
      :::

      :::: more "Going further" it="Per andare oltre"
      Can also asks for help.

      ::: it
      Can serve anche a chiedere.
      :::

      ::::

      ::: summary
      - One
      - Two
      - Three
      :::

      ::: it
      - Uno
      - Due
      - Tre
      :::

      ::: check choice
    MD
    findings = Validation::Findings.new
    blocks = parse(md, findings).body["cards"][0]["blocks"]
    assert_empty findings.map(&:message)
    callout = blocks.find { |b| b["type"] == "callout" }
    assert_equal({ "title_en" => "Remember", "title_it" => "Ricorda", "text_en" => "Use the base verb.", "text_it" => "Usa il verbo base." }, callout.slice("title_en", "title_it", "text_en", "text_it"))
    more = blocks.find { |b| b["type"] == "more" }
    assert_equal [ "Going further", "Per andare oltre" ], more.values_at("title_en", "title_it")
    assert_equal "Can serve anche a chiedere.", more["blocks"][0]["text_it"]
    summary = blocks.find { |b| b["type"] == "summary" }
    assert_equal [ [ "One", "Two", "Three" ], [ "Uno", "Due", "Tre" ] ], summary.values_at("points_en", "points_it")
  end

  test "a text block without its ::: it fence is E-LANG-PAIR-MISSING at its line; a title without it= too" do
    missing = edit("en", "\n::: it\nDopo un verbo modale il verbo che segue non cambia: niente -s, niente to.\n:::\n", "")
    outcome = check(missing)
    hit = outcome.findings.find { |f| f.code == "E-LANG-PAIR-MISSING" && f.field.end_with?("text_en") }
    assert hit, outcome.findings.map { |f| [ f.code, f.field ] }.inspect
    assert_equal 28, hit.detail[:line]

    no_title = edit("en", ' it="Can + il verbo base"', "")
    assert(check(no_title).findings.any? { |f| f.code == "E-LANG-PAIR-MISSING" && f.field == "/cards/0/title_en" })
  end

  # ---- the checks -----------------------------------------------------------------------------------------------------------

  test "a pair without the flag is E-LANG-BILINGUAL-FLAG; the flag in a subject that teaches no language is too; a sibling of another language too" do
    unflagged = edit("en", "bilingual: true\n", "")
    flagged = check(unflagged).findings.select { |f| f.code == "E-LANG-BILINGUAL-FLAG" }
    assert_operator flagged.size, :>=, 1

    math = F.read("base.md").sub("schema: banco.lesson/2\n", "schema: banco.lesson/2\nbilingual: true\n")
    assert_includes codes(check(math, "math")), "E-LANG-BILINGUAL-FLAG"

    spanish = source("es").sub("title_es:", "title_en:")
    assert_includes codes(check(spanish, "spanish")), "E-LANG-BILINGUAL-FLAG"
  end

  test "the colour roles of a text and of its Italian must be the same" do
    md = edit("en", "After a modal verb the next verb does not change: no -s, no to.", "After a [[subject:modal verb]] the next verb does not change: no -s, no to.")
    assert_includes codes(check(md)), "E-LANG-PAIR-SHAPE"
    both = md.sub("Dopo un verbo modale", "Dopo un [[subject:verbo modale]]").sub("Dopo un [[subject:verbo modale]] il verbo", "Dopo un [[subject:verbo modale]] il verbo")
    assert_not_includes codes(check(both)).select { |c| c == "E-LANG-PAIR-SHAPE" }, "E-LANG-PAIR-SHAPE"
  end

  test "[[it:..]] quotes Italian inside target text only; a [[en:..]] in English text is redundant unless the lesson discusses it" do
    quoted = edit("en", "After a modal verb the next verb does not change: no -s, no to.", "Say [[it:ho fame]] in English.")
    quoted = quoted.sub("Dopo un verbo modale il verbo che segue non cambia: niente -s, niente to.", "Di' [[it:ho fame]] in inglese.")
    findings = check(quoted).findings
    assert(findings.any? { |f| f.code == "E-LESSON-LANG" && f.field.end_with?("text_it") }, "in the translation it is refused: #{findings.map { |f| [ f.code, f.field ] }.inspect}")
    assert_not(findings.any? { |f| f.code == "E-LESSON-LANG" && f.field.end_with?("text_en") })

    redundant = edit("en", "no -s, no to.", "no [[en:fish]] now.")
    assert(check(redundant).findings.any? { |f| f.code == "W-LANG-SPAN-REDUNDANT" })

    legacy = F.read("demo-italian.md").sub(/^(## .+\n\n)/, "\\1Dico [[it:ciao]] qui.\n\n")
    assert(check(legacy, "italian").findings.any? { |f| f.code == "E-LESSON-LANG" && f.message.include?("[[it:") }, "in a lesson that is not bilingual [[it:..]] has no place")
  end

  test "target-language sentences are held to the target lint, not to the Italian one" do
    findings = check(source("en")).findings
    assert(findings.any? { |f| f.code == "E-READ" && f.field == "/cards/0/blocks/0/text_en" && f.message.include?("English sentence") }, "the 14-word sentence of the golden lesson")
    assert_not(findings.any? { |f| f.code == "W-GULPEASE" && f.field == "/cards/0/blocks/0/text_en" })
  end

  test "a blank (___) is text in a lesson, in the target text and in its translation" do
    blocks = Lessons::Markup.parse("Fill: I ___ my bed.", roles: true)
    assert_equal "Fill: I ___ my bed.", blocks.first["children"].first["v"]
    assert_raises(Lessons::Markup::Refused) { Lessons::Markup.parse("Fill: x___ y.", roles: true) }
  end

  # ---- the replies of the check endpoint --------------------------------------------------------------------------------------

  Rev = Struct.new(:body, :id, keyword_init: true)

  def answer(response, card: 1, block: 2, try: 1, ex: nil)
    body = parse(source("en")).body
    locator = { card: card, block: block }
    locator[:ex] = ex if ex
    Lessons::CheckAnswer.new(Rev.new(body: body, id: REVISION["en"]), student_key: "preview", trial_try: try).call(locator, response)
  end

  test "a wrong answer carries the target message in message_it and its Italian in its own tr" do
    reply = answer("o2")
    assert_equal 200, reply.status
    assert_equal fixture("reply_check_wrong.json"), json(reply.body)
  end

  test "a right answer carries the explanation, target and Italian" do
    reply = answer("o1", try: 2)
    assert_equal fixture("reply_check_right.json"), json(reply.body)
  end

  test "the solution reply of an exercise carries the target text, the final and the tr" do
    exercise = parse(source("en")).body["cards"][1]["blocks"][0]["exercises"][0]
    assert_equal fixture("reply_solution.json"), json(Lessons::CheckAnswer.solution(exercise))
    legacy = { "n" => 2, "solution_it" => "Si dice così.", "final_it" => "x" }
    assert_equal({ n: 2, solution_it: "Si dice così." }, Lessons::CheckAnswer.solution(legacy))
  end

  # ---- figures and tables ---------------------------------------------------------------------------------------------------

  test "the table of a lesson and of a figure pairs R2 style: the cells in the target language, header_it and rows_it, all served" do
    table = { "n" => 1, "type" => "table", "caption_en" => "Forms", "caption_it" => "Forme", "header" => [ "Base", "Past" ], "header_it" => [ "Base", "Passato" ],
              "rows" => [ [ "go", "went" ] ], "rows_it" => [ [ "andare", "andò" ] ] }
    schema = Banco::Schemas.for_subject("lesson", "english").ref("#/$defs/block")
    assert_empty schema.validate(table).map { |e| e["error"] }
    assert_not_empty Banco::Schemas.schema("lesson").ref("#/$defs/block").validate(table).to_a, "a subject that teaches no language does not meet the twins"
    served = Lessons::StudentBody.block(table, "english", "seed")
    assert_equal %w[header header_it rows rows_it], served.slice("header", "header_it", "rows", "rows_it").keys.sort
    assert_equal({ "n" => 1, "type" => "table", "caption_en" => "Forms", "caption_it" => "Forme", "header" => [ "Base", "Past" ], "header_it" => [ "Base", "Passato" ],
                   "rows" => [ [ "go", "went" ] ], "rows_it" => [ [ "andare", "andò" ] ] }, served)
    folded = Lessons::StudentBody.project({ "subject" => "english", "bilingual" => true, "cards" => [ { "n" => 1, "blocks" => [ table ] } ] }, revision_id: 1, seed: "x")
    assert_equal({ "Forms" => "Forme" }, folded["cards"][0]["blocks"][0]["tr"])
    assert_equal %w[Base Passato], folded["cards"][0]["blocks"][0]["header_it"]
    pairs = Lessons::Bilingual.pairs({ "cards" => [ { "blocks" => [ table ] } ] }, "en").to_a
    assert_includes pairs, [ "/cards/0/blocks/0/header/1", "header", "Past", "Passato" ]
    assert_includes pairs, [ "/cards/0/blocks/0/rows/0/1", "rows", "went", "andò" ]
  end

  test "a figure with pairs is served in the slots the renderer reads, with its own tr; a legacy figure is served as before" do
    figure = { "type" => "table", "alt_en" => "Two forms of go.", "alt_it" => "Due forme di go.", "caption_en" => "Forms", "caption_it" => "Forme",
               "header" => [ "Base", "Past" ], "header_it" => [ "Base", "Passato" ], "rows" => [ [ "go", "went" ] ], "rows_it" => [ [ "andare", "andò" ] ] }
    served = Lessons::StudentBody.diagram(figure)
    assert_equal "Two forms of go.", served["alt_it"]
    assert_equal "Forms", served["caption_it"]
    assert_equal({ "Two forms of go." => "Due forme di go.", "Forms" => "Forme" }, served["tr"])
    assert_equal %w[Base Passato], served["header_it"]
    legacy = { "type" => "table", "alt_it" => "Due forme.", "caption_it" => "Forme", "header" => [ "a" ], "rows" => [ [ "b" ] ] }
    assert_equal legacy, Lessons::StudentBody.diagram(legacy)
  end

  test "listen and span_select text and the spans of a figure are target-only data: never an orphan" do
    doc = { "cards" => [ { "blocks" => [ { "component" => "span_select", "text_en" => "She plays.", "spans" => [ { "id" => "a", "text_en" => "She" } ] },
                                         { "component" => "choice", "listen" => { "text_en" => "Hello." } },
                                         { "type" => "diagram", "diagram" => { "type" => "sentence", "parts" => [ { "text_en" => "She", "label_en" => "subject", "label_it" => "soggetto" } ] } } ] } ] }
    orphans = Lessons::Bilingual.pairs(doc, "en").select { |_, base, target, italian| base == "text" && target && italian.nil? }
    assert_empty orphans
  end

  # ---- the palette --------------------------------------------------------------------------------------------------------------

  test "english and spanish roles carry their names and questions in the language of the lesson, own to the role (same_as keeps them)" do
    english = Lessons::Palette.roles("english")
    assert_equal "subject", english["subject"]["label_en"]
    assert_equal "soggetto", english["subject"]["label_it"], "same_as keeps the Italian name it copies"
    assert_equal "Who? What?", english["subject"]["question_en"]
    assert_equal "terminación", Lessons::Palette.roles("spanish")["ending"]["label_es"]
    assert_equal "Find the object", Lessons::Palette.step_tags("english")["object"]["label_en"]
  end

  test "the whitelist and its sibling columns: a served _it field is served with its target siblings, a dropped one is not" do
    wl = JSON.parse(Rails.root.join("test/fixtures/lesson2/whitelist.json").read)
    wide = Lessons::StudentBody::WIDE
    twin = ->(field) { (base = field[/\A(.+)_it\z/, 1]) && !Lessons::Bilingual::EXEMPT.include?(base) ? [ "#{base}_en", "#{base}_es" ] : [] }
    wl["checks"].reject { |name, _| name.start_with?("_") }.each do |name, entry|
      next unless (columns = Lessons::StudentBody::CHECK_COLUMNS[name])
      entry["serve"].each { |field| assert_empty twin.call(field) - columns, "#{name}.#{field}: siblings served" }
      (entry["drop"].map { |d| d[/\A[a-z_]+/] } - %w[text_it text_en text_es]).each { |field| assert_empty twin.call(field) & columns, "#{name}.#{field}: dropped, and so are its siblings" }
    end
    wl["blocks"].each do |name, entry|
      next unless Lessons::StudentBody::BLOCKS.key?(name)

      columns = Lessons::StudentBody::BLOCKS.fetch(name).first
      entry["serve"].each { |field| assert_empty twin.call(field) - columns, "#{name}.#{field}: siblings served" }
      entry["drop"].each { |field| assert_empty twin.call(field[/\A[a-z_]+/]) & columns, "#{name}.#{field}: dropped, and so are its siblings" }
    end
    assert_equal %w[header_it rows_it], wl["bilingual"]["r2_twins"]["table"]
    assert_equal wide.call(%w[title_it]), %w[title_it title_en title_es]
    assert_equal %w[header_it rows_it], wide.call(%w[header_it rows_it]), "an R2 twin has no sibling of its own"
  end

  test "test/fixtures/lesson2/served/bilingual.json is the stored body of the golden english lesson and is valid against the derived schema" do
    stored = JSON.parse(Rails.root.join("test/fixtures/lesson2/served/bilingual.json").read)
    assert_equal true, stored["bilingual"]
    assert_empty Banco::Schemas.validate("lesson", stored).map(&:to_h)
    golden = parse(source("en")).body
    assert_equal json(Lessons::StudentBody.project(golden, revision_id: 1, seed: "x")).except("key", "kind"), json(Lessons::StudentBody.project(stored, revision_id: 1, seed: "x")).except("key", "kind")
  end

  test "with Validation::Bilingual (slice 2): a different shape, a copied translation and a conflict are refused, in the lesson's scopes" do
    skip "Validation::Bilingual has not landed" unless defined?(Validation::Bilingual) && Validation::Bilingual.respond_to?(:check)
    shape = edit("en", "Dopo un verbo modale il verbo che segue non cambia: niente -s, niente to.", "Dopo un verbo modale.\n\nIl verbo che segue non cambia.")
    assert(check(shape).findings.any? { |f| f.code == "E-LANG-PAIR-SHAPE" && f.field == "/cards/0/blocks/0/text_en" })
    copied = edit("en", "Quale forma va dopo can?", "Which form goes after can?")
    assert(check(copied).findings.any? { |f| f.code == "E-LANG-TRANSLATION-COPY" })
    conflict = edit("en", "translate_material: false\noptions:\n  - {id: a, text_en: \"plays\"}\n  - {id: b, text_en: \"play\"}", "options:\n  - {id: a, text_en: \"play\", text_it: \"suona\"}\n  - {id: b, text_en: \"play\", text_it: \"suonare\"}")
    assert(check(conflict).findings.any? { |f| f.code == "W-LANG-PAIR-CONFLICT" }, "a label of one word: a warning (round 4)")
  end
end
