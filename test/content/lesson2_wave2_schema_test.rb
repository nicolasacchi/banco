require "test_helper"
require_relative "../support/lesson2_fixtures"

# W2-0: the blocks, check components and options that wave 2 adds to config/banco/schemas/lesson.json accept what the plan's examples
# write (invented content) and refuse what it forbids. The registry (Lessons::Types) decides what an author may use today; the schema
# is what the reserved dry run validates against.
class Lesson2Wave2SchemaTest < ActiveSupport::TestCase
  F = Lesson2Fixtures
  NET = { "type" => "network", "alt_it" => "Due nodi collegati da una freccia, per provare lo schema.", "layout" => "pair",
          "nodes" => [ { "id" => "a", "label_it" => "A" }, { "id" => "b", "label_it" => "B" } ] }.freeze

  def errors_with(*blocks, card: 1)
    body = Marshal.load(Marshal.dump(F.check(F.read("base.md")).parsed.body))
    body["cards"][card]["blocks"] = blocks.map.with_index(1) { |b, i| b.merge("n" => i) }
    yield body if block_given?
    Banco::Schemas.validate("lesson", body).map(&:to_h)
  end

  def check(component, **fields) = { "type" => "check", "component" => component, "prompt_it" => "Domanda di prova" }.merge(fields.transform_keys(&:to_s))

  test "the new blocks accept the plan's examples" do
    assert_empty errors_with(
      { "type" => "reveal", "situation_it" => "Che cosa fai?", "year" => "-27", "who_it" => "Ottaviano", "real_it" => "Ecco.",
        "options" => [ { "id" => "a", "text_it" => "Uno", "then_it" => "Dopo" }, { "id" => "b", "text_it" => "Due", "then_it" => "Poi", "real" => true } ] },
      { "type" => "reveal", "prompt_it" => "Pensaci", "answer_it" => "Ecco" },
      { "type" => "source", "kind" => "legal", "title_it" => "Costituzione, art. 74", "ref" => "costituzione-artt-55-96", "open" => "plain",
        "parts" => [ { "text_it" => "Testo di prova.", "plain_it" => "In parole semplici.", "marks" => [ { "text_it" => "Testo", "role" => "known" } ] } ] },
      { "type" => "dialogue", "title_it" => "Due amici", "transcript" => "shown", "speakers" => [ { "id" => "t", "name" => "Tom", "voice" => 1 } ],
        "lines" => [ { "speaker" => "t", "text_en" => "Hello", "gloss_it" => "Ciao" }, { "speaker" => "t", "text_en" => "Bye", "gloss_it" => "Ciao" } ] }
    )
    assert_empty errors_with(
      { "type" => "oral", "question_it" => "Perché?", "outline" => %w[uno due tre].each_with_index.map { |t, i| { "id" => "o#{i + 1}", "text_it" => t } },
        "answer" => %w[o1 o2 o3], "errors" => [ { "answer" => %w[o2 o1 o3], "message_it" => "Ordine." } ], "connectives" => [ "perché" ], "terms" => [ "latifondo" ], "model_it" => "Così." },
      { "type" => "image", "file" => "a.png", "alt_it" => "x", "source_it" => "y", "license" => "cc-by-sa-4.0", "author" => "z", "source_url" => "https://commons.wikimedia.org/x",
        "text_it" => "Equivalente.", "hotspots" => [ { "id" => "h1", "x" => 10, "y" => 20, "label_it" => "Nucleo" } ], "tour" => true }
    )
  end

  test "the new check components accept their examples, the options and the glossary" do
    assert_empty errors_with(
      check("select", diagram: NET, targets: "nodes", pick: "many", answer: [ "a" ], errors: [ { "answer" => [ "b" ], "message_it" => "No" } ], reachable_ok_it: "Perché."),
      check("tiles", tiles: %w[I go home].each_with_index.map { |w, i| { "id" => "t#{i + 1}", "text_en" => w } }, answer: %w[t1 t2 t3], accept: [ %w[t1 t3 t2] ]),
      check("ordering", items: %w[uno due tre].each_with_index.map { |t, i| { "id" => "i#{i + 1}", "text_it" => t } }, answer: %w[i1 i2 i3]),
      check("amount_words", amount: "1240,50")
    )
    assert_empty errors_with(
      check("choice", options: [ { "id" => "a", "text_it" => "A" }, { "id" => "b", "text_it" => "B" } ], answer: "a", listen: { "text_es" => "Hola" },
                      verify: { "fn" => "chrono.duration", "args" => { "from" => "-133", "to" => "-27" } }),
      check("normalized_text", answer: "00000101", profile: { "name" => "binary", "width" => 8, "leading_zeros" => "required" }, input: "bits", contractions: "en"),
      check("number", answer: "1115", thousands: true)
    ) do |body|
      body["glossary"] = [ { "term_it" => "promulgare", "def_it" => "firmare" } ]
      body["teaches_en"] = [ "go" ]
    end
  end

  test "what the plan forbids is refused" do
    assert_not_empty errors_with(check("select", diagram: NET, targets: "nodes", answer: [ "a" ])), "select needs pick"
    assert_not_empty errors_with(check("tiles", tiles: [ { "id" => "t1", "text_en" => "I" }, { "id" => "t2", "text_en" => "go" } ], answer: %w[t1 t2])), "tiles: at least 3"
    assert_not_empty errors_with({ "type" => "dialogue", "title_it" => "x", "speakers" => [ { "id" => "t", "name" => "Tom" } ], "lines" => [ { "speaker" => "t", "text_en" => "Hi", "gloss_it" => "Ciao" }, { "speaker" => "t", "gloss_it" => "Ciao" } ] }), "a line has its target text"
    assert_not_empty errors_with({ "type" => "oral", "question_it" => "x", "outline" => [ { "id" => "o1", "text_it" => "a" }, { "id" => "o2", "text_it" => "b" }, { "id" => "o3", "text_it" => "c" } ], "answer" => %w[o1 o2 o3] }), "oral needs model_it"
    assert_not_empty errors_with({ "type" => "reveal", "prompt_it" => "Solo la domanda" }), "reveal needs its answer or its options"
    assert_not_empty errors_with({ "type" => "image", "file" => "a.png", "alt_it" => "x", "source_it" => "y", "license" => "all-rights-reserved", "author" => "z", "source_url" => "https://x.org" }), "a licence of the list"
    assert_not_empty errors_with({ "type" => "source", "kind" => "legal", "title_it" => "x", "parts" => [] }), "a source has parts"
    assert_not_empty errors_with(check("choice", options: [ { "id" => "a", "text_it" => "A" }, { "id" => "b", "text_it" => "B" } ], answer: "a", listen: {})), "listen has a text"
    assert_not_empty errors_with({ "type" => "page", "key" => "x" }), "free pages are not a block of the schema yet"
  end

  test "the schema of each new piece says it is a draft where the plan does" do
    lesson = JSON.parse(Rails.root.join("config/banco/schemas/lesson.json").read).fetch("$defs")
    assert_equal true, lesson["b_image"]["x-banco-draft"]
    assert_equal true, lesson["check_amount_words"]["x-banco-draft"]
    assert_nil lesson["b_source"]["x-banco-draft"]
    assert_equal true, lesson["b_oral"]["properties"]["model_it"]["x-banco-withheld"]
    assert_equal %w[choice number fraction normalized_text select amount_words], lesson["blank"]["allOf"][1]["properties"]["component"]["enum"]
  end
end
