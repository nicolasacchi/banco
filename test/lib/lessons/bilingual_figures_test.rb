require "test_helper"
require_relative "../../support/lesson2_fixtures"

# D-402: the figures whose own data is target-language text. A `sentence` figure's `text_<lang>`, its states' and its parts are target-only, never paired and never
# folded (the translation of the sentence is its `alt_it` and `caption_it`, which pair as usual); a `mirror` figure's `rows` are not table rows (R2's `header` and
# `rows` belong to a `table` block and a `table` figure only). A bilingual lesson with such figures, in the hero and in a card, parses, validates and is served.
class BilingualFiguresTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  SUBJECT = { "en" => "english", "es" => "spanish" }.freeze
  REVISION = { "en" => 1, "es" => 0 }.freeze

  # Per language: the sentence, its parts (role, target word, the label pair of the part) and the figures' Italian.
  SENTENCE = {
    "en" => { text: "She reads a book", parts: [ [ "s", "She", "subject", "subject", "soggetto" ], [ "v", "reads", "verb", "verb", "verbo" ], [ "o", "a book", "object", "object", "complemento oggetto" ] ],
              alt: "The sentence She reads a book, with the subject, the verb and the object in colour.", alt_it: "La frase She reads a book, con il soggetto, il verbo e il complemento oggetto colorati." },
    "es" => { text: "Mi hermana lee un libro", parts: [ [ "v", "lee", "verb", "el verbo", "il verbo" ], [ "o", "un libro", "od", "complemento directo", "complemento diretto" ] ],
              alt: "La frase Mi hermana lee un libro, con el verbo y el complemento directo en color.", alt_it: "La frase Mi hermana lee un libro, con il verbo e il complemento diretto colorati." }
  }.freeze
  MIRROR = {
    "en" => { it: [ "Lei", "legge", "un libro" ], pieces: [ "She", "reads", "a book" ], alt: "The Italian sentence lei legge un libro over the same sentence in the other language, piece by piece: the verbs match." },
    "es" => { it: [ "Lei", "legge", "un libro" ], pieces: [ "Ella", "lee", "un libro" ], alt: "La frase italiana lei legge un libro sobre la misma frase en la otra lengua, pieza por pieza: los verbos se corresponden." }
  }.freeze

  def json(value) = JSON.parse(JSON.generate(value))

  def parts_yaml(lang, indent, labelled)
    SENTENCE[lang][:parts].map do |id, text, role, label, label_it|
      pair = labelled ? ", label_#{lang}: #{label.inspect}, label_it: #{label_it.inspect}" : ""
      "#{indent}- {id: #{id}, text_#{lang}: #{text.inspect}, role: #{role}#{pair}}"
    end.join("\n")
  end

  def sentence_yaml(lang, indent: "", labelled: true)
    s = SENTENCE[lang]
    body = [ "type: sentence", "layout: line", "alt_#{lang}: #{s[:alt].inspect}", "alt_it: #{s[:alt_it].inspect}", "text_#{lang}: #{s[:text].inspect}", "parts:", *parts_yaml(lang, "  ", labelled).lines.map(&:chomp) ]
    body.map { |l| "#{indent}#{l}" }.join("\n")
  end

  def mirror_block(lang)
    m = MIRROR[lang]
    <<~MD
      ::: diagram mirror
      alt_#{lang}: #{m[:alt].inspect}
      alt_it: "La frase italiana lei legge un libro sopra la stessa frase nell'altra lingua, pezzo per pezzo: i verbi si corrispondono."
      same_ok: true
      rows:
        - pieces_it: #{m[:it].inspect}
          pieces_#{lang}: #{m[:pieces].inspect}
          links: [[0, 0, same], [1, 1, same], [2, 2, same]]
      :::

    MD
  end

  # The golden lesson with a sentence figure as its hero, one as a diagram block and a mirror figure in the first card.
  def lesson(lang, sentence: true, mirror: true)
    md = DIR.join("lesson_#{lang}.md").read
    md = md.sub("\n---\n\n##", "\nhero:\n#{sentence_yaml(lang, indent: '  ')}\n---\n\n##") if sentence
    figures = +""
    figures << "::: diagram sentence\n#{sentence_yaml(lang).lines.drop(1).join}\n:::\n\n" if sentence
    figures << mirror_block(lang) if mirror
    md.sub("::: check choice", "#{figures}::: check choice")
  end

  # The bare R2 keys of +node+ (at +pointer+) that lack their `_it` twin: [[pointer, base]].
  def gaps(node, pointer = "") = [].tap { |out| Validation::Bilingual.r2_gaps(node, pointer) { |at, base| out << [ at, base ] } }

  def findings(lang, md) = Validation::LessonChecks.call(md, subject: SUBJECT[lang], context: F.context(SUBJECT[lang])).findings

  def figure_findings(lang, md)
    findings(lang, md).select { |f| f.code.start_with?("E-LANG-", "E-LESSON-DIAGRAM", "E-LESSON-LANG", "E-SCHEMA") || f.field.to_s.match?(%r{/hero|/diagram}) }
  end

  def served(lang, md)
    body = Lessons::Parser2.call(md, Validation::Findings.new).body
    Lessons::StudentBody.project(body, revision_id: REVISION[lang], seed: "preview")
  end

  %w[en es].each do |lang|
    key = "text_#{lang}"

    test "#{lang}: a sentence figure in the hero and in a card, and a mirror figure, parse and validate with no pair finding" do
      findings = Validation::Findings.new
      body = Lessons::Parser2.call(lesson(lang), findings).body
      assert_empty findings.map(&:to_h)
      assert_equal SENTENCE[lang][:text], body["hero"][key]
      assert_nil body["hero"]["text_it"], "no Italian twin is needed, none is written"
      assert_empty figure_findings(lang, lesson(lang)).map { |f| [ f.code, f.field, f.message ] }
    end

    test "#{lang}: the sentence and its parts are never padded, folded or paired: Diagrams::Sentence sees them in the same key" do
      body = Lessons::Parser2.call(lesson(lang), Validation::Findings.new).body
      target = Lessons::Parser2.target_view(Lessons::Parser2.pad_pairs(body, lang), lang)
      [ target["hero"], target["cards"][0]["blocks"].find { |b| b["type"] == "diagram" && b["diagram"]["type"] == "sentence" }["diagram"] ].each do |figure|
        assert_equal SENTENCE[lang][:text], figure[key]
        assert_nil figure["text_it"]
        assert_equal [ key ], figure["parts"].map { |p| Lessons::Diagrams::Sentence.key_of(p) }.uniq
        assert_equal key, Lessons::Diagrams::Sentence.key_of(figure)
      end
      assert_equal [], Lessons::Bilingual.pairs(body["hero"], lang).select { |_pointer, base, _t, _i| base == "text" }.to_a
    end

    test "#{lang}: the served sentence figure keeps text_#{lang} on the sentence and on every part; its alt and the part labels fold as usual" do
      hero = served(lang, lesson(lang))["hero"]
      assert_equal SENTENCE[lang][:text], hero[key]
      assert_not hero.key?("text_it")
      assert_equal SENTENCE[lang][:parts].map { |p| p[1] }, hero["parts"].map { |p| p[key] }
      assert hero["parts"].none? { |p| p.key?("text_it") }
      assert_equal SENTENCE[lang][:alt], hero["alt_it"], "the alt is served in the _it slot, as the target text"
      assert_equal SENTENCE[lang][:alt_it], hero["tr"][SENTENCE[lang][:alt]]
      assert_equal SENTENCE[lang][:parts].map { |p| p[3] }, hero["parts"].map { |p| p["label_it"] }
      assert_equal SENTENCE[lang][:parts][0][4], hero["tr"][SENTENCE[lang][:parts][0][3]]
    end

    test "#{lang}: the served shape is the golden served sentence figure, which the renderer draws" do
      body = served(lang, lesson(lang))
      card = body["cards"][0]["blocks"].find { |b| b["type"] == "diagram" && b["diagram"]["type"] == "sentence" }
      assert_equal JSON.parse(DIR.join("served_sentence_#{lang}.json").read), json("hero" => body["hero"], "block" => card["diagram"])
    end

    test "#{lang}: a mirror figure validates clean and keeps its rows: they are not table rows" do
      md = lesson(lang, sentence: false)
      assert_empty findings(lang, md).select { |f| f.code.start_with?("E-LANG-") || f.field.to_s.include?("/diagram") }.map { |f| [ f.code, f.field, f.message ] }
      body = Lessons::Parser2.call(md, Validation::Findings.new).body
      diagram = body["cards"][0]["blocks"].find { |b| b["type"] == "diagram" }["diagram"]
      assert_equal [ "pieces_it", "pieces_#{lang}", "links" ], diagram["rows"][0].keys
      assert_equal [], Lessons::Bilingual.pairs(diagram, lang).reject { |_p, base, _t, _i| %w[alt pieces].include?(base) }.to_a
      assert_equal [], gaps(diagram, "/cards/0/blocks/1/diagram")
    end

    test "#{lang}: a sentence text in the target language needs no Italian, and an Italian twin beside it is a one-language error, not a pair" do
      md = lesson(lang).sub("text_#{lang}: #{SENTENCE[lang][:text].inspect}\n  parts:", "text_#{lang}: #{SENTENCE[lang][:text].inspect}\n  text_it: \"Lei legge un libro\"\n  parts:")
      assert_includes md, "Lei legge un libro"
      found = findings(lang, md)
      assert_empty found.select { |f| f.code.start_with?("E-LANG-") }.map { |f| [ f.code, f.field ] }
      assert(found.any? { |f| f.code == "E-LESSON-DIAGRAM" && f.detail[:rule].to_s.start_with?("one-language") }, found.map(&:code).inspect)
    end
  end

  test "a table block and a table figure are still paired by R2, a mirror or a word_parts figure with rows is not" do
    table = { "type" => "table", "header" => [ "A" ], "rows" => [ [ "x" ] ] }
    assert Lessons::Bilingual.r2?(table, "rows", "/cards/0/blocks/1")
    assert Lessons::Bilingual.r2?(table, "header", "/cards/0/blocks/1/diagram")
    assert Lessons::Bilingual.r2?(table, "rows", "/cards/0/blocks/1/schema")
    assert Lessons::Bilingual.r2?({ "header" => [ "A" ] }, "header", "/table"), "an item's own table has no type"
    mirror = { "type" => "mirror", "rows" => [ { "pieces_it" => [ "Lei" ], "pieces_en" => [ "She" ] } ] }
    assert_not Lessons::Bilingual.r2?(mirror, "rows", "/cards/0/blocks/1/diagram")
    assert_not Lessons::Bilingual.r2?({ "type" => "word_parts", "rows" => [] }, "rows", "/cards/0/hero")
    assert_not Lessons::Bilingual.r2?({ "type" => "dialogue", "rows" => [] }, "rows", "/cards/0/blocks/2")
    assert_equal [ [ "/rows", "rows" ] ], gaps(table, "/cards/0/blocks/1/diagram").select { |_pointer, base| base == "rows" }.map { |pointer, base| [ pointer.delete_prefix("/cards/0/blocks/1/diagram"), base ] }
    assert_equal [], gaps(mirror, "/cards/0/blocks/1/diagram")
  end

  test "the other figures and checks that hold target text: dialogue lines, span_select, tiles, listen, word_parts need no Italian twin and are not folded" do
    dialogue = { "type" => "dialogue", "lines" => [ { "speaker" => "A", "text_en" => "Hello", "gloss_it" => "Ciao" } ] }
    span = { "component" => "span_select", "text_en" => "She reads", "spans" => [ { "id" => "a", "text_en" => "She" } ], "listen" => { "text_en" => "She reads" } }
    tiles = { "component" => "tiles", "tiles" => [ { "id" => "a", "text_en" => "She" } ] }
    words = { "type" => "word_parts", "rows" => [ { "form_en" => "reads", "label_it" => "verbo" } ] }
    { dialogue: dialogue, span: span, tiles: tiles, words: words }.each do |name, node|
      doc = { "cards" => [ { "blocks" => [ node ] } ] }
      orphans = Lessons::Bilingual.pairs(doc, "en").select { |_p, _b, target, italian| target && italian.nil? }.to_a
      assert_empty orphans, "#{name}: #{orphans.inspect}"
      assert_empty Validation::Bilingual.check(Validation::Findings.new, doc, lang: "en").map(&:code), name.to_s
      folded = Lessons::Bilingual.fold(doc, "en")["cards"][0]["blocks"][0]
      assert_equal node.except("gloss_it", "label_it"), folded.except("gloss_it", "label_it", "tr"), "#{name} is served as written"
    end
  end
end
