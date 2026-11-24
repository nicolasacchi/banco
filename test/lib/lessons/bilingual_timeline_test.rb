require "test_helper"
require_relative "../../support/lesson2_fixtures"

# D-402, tooling round 4: the marks of a `scale: tense` timeline hold their sentence in `text_en|es`, which the diagram schema has no `text_it` for. A bilingual
# lesson must not pad that text with a copy of itself (the dry run refused it, E-SCHEMA / E-LESSON-BLOCK, in the cover, in a diagram block and in a case).
class BilingualTimelineTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  CODES = %w[E-SCHEMA E-LESSON-BLOCK E-LESSON-DIAGRAM E-LESSON-CHECK E-LESSON-LANG W-LANG-LEVEL].freeze

  def source = DIR.join("lesson_en_timeline.md").read
  def check(md) = Validation::LessonChecks.call(md, subject: "english", context: F.context("english"))
  def mine(outcome) = outcome.findings.select { |f| f.code.start_with?("E-LANG-") || CODES.include?(f.code) }

  test "a bilingual english lesson with a tense timeline in the cover, a diagram block, a case and a select check is clean" do
    assert_empty mine(check(source)).map { |f| [ f.code, f.field, f.message ] }
  end

  test "the marks keep their text_en: no text_it is made of it, in any of the four places" do
    body = Lessons::Parser2.call(source, Validation::Findings.new).body
    padded = Lessons::Parser2.pad_pairs(body, "en")
    marks = [ padded["hero"]["marks"], padded.dig("cards", 0, "blocks", 1, "diagram", "marks"), padded.dig("cards", 0, "blocks", 2, "cases", 0, "diagram", "marks"), padded.dig("cards", 0, "blocks", 3, "diagram", "marks") ]
    assert_equal 4, marks.size
    marks.flatten.each { |m| assert_not m.key?("text_it"), m.inspect }
    assert_empty Banco::Schemas.for_subject("lesson", "english").validate(Lessons::Parser2.for_schema(padded)).to_a
  end

  test "the served lesson keeps each mark's text_en and gives its label the target text, with the Italian in tr" do
    body = Lessons::Parser2.call(source, Validation::Findings.new).body
    served = Lessons::StudentBody.project(body, revision_id: 1, seed: "preview")
    hero = served["hero"]
    assert_equal [ "I arrive", "I will call you" ], hero["marks"].map { |m| m["text_en"] }
    assert_equal [ "when?", "what happens" ], hero["marks"].map { |m| m["label_it"] }
    assert_equal "quando?", hero["tr"]["when?"]
  end

  test "a mark of a spanish lesson says text_es and is no pair either" do
    mark = { "id" => "a", "at" => "1", "span" => "point", "text_es" => "Llamo", "label_es" => "¿cuándo?", "label_it" => "quando?" }
    pairs = Lessons::Bilingual.pairs({ "marks" => [ mark ] }, "es").map { |pointer, base, _t, _i| [ pointer, base ] }
    assert_equal [ [ "/marks/0/label_es", "label" ] ], pairs
  end

  test "a mark with no label_en but a label_it is still the orphan the pairs say" do
    mark = { "id" => "a", "at" => "1", "span" => "point", "text_en" => "I called", "label_it" => "quando?" }
    pairs = Lessons::Bilingual.pairs({ "marks" => [ mark ] }, "en").to_a
    assert_equal [ [ "/marks/0/label_en", "label", nil, "quando?" ] ], pairs
  end

  # The same copy would hurt any other property that is a target text with no `_it` twin in its schema: the list is short and each one is a field the pairs
  # leave alone (a dialogue line's text with its gloss, a paradigm's forms, a listen text, the teaches lists, a tense mark's sentence).
  test "the schema properties that are _en|_es with no _it twin are exactly the ones the pairs leave alone" do
    found = Dir[Rails.root.join("config/banco/schemas/*.json")].flat_map do |file|
      walk = lambda do |node, path|
        case node
        when Hash
          keys = node["properties"].is_a?(Hash) ? node["properties"].keys : []
          own = keys.filter_map { |k| (m = k.match(/\A(.+)_(?:en|es)\z/)) && keys.exclude?("#{m[1]}_it") && "#{File.basename(file)}#{path.sub(/\/properties\/.*/, '')} #{k}" }
          own + node.flat_map { |k, v| walk.call(v, "#{path}/#{k}") }
        when Array then node.each_with_index.flat_map { |v, i| walk.call(v, "#{path}/#{i}") }
        else []
        end
      end
      walk.call(JSON.parse(File.read(file)), "")
    end
    keys = found.map { |f| f.split.last }.uniq.sort
    assert_equal %w[base_en participle_en past_en teaches_en teaches_es text_en text_es], keys
    # text_en|es: a dialogue line (its gloss is `gloss_it`), a `listen` text, a tense mark; none of them is a pair of its own
    doc = { "cards" => [ { "blocks" => [ { "type" => "diagram", "diagram" => { "type" => "timeline", "marks" => [ { "text_en" => "I go" } ] } } ] } ] }
    assert_empty Lessons::Bilingual.pairs(doc, "en").to_a
    assert_empty Lessons::Bilingual.pairs({ "listen" => { "text_en" => "Hello" } }, "en").to_a
    assert_empty Lessons::Bilingual.pairs({ "verbs" => [ { "base_en" => "go", "past_en" => "went", "participle_en" => "gone" } ] }, "en").to_a
  end
end
