require "test_helper"
require_relative "../support/lesson2_fixtures"

# Rules version 9 (WAVE2 1.8): a source, a dialogue, a reveal with options and an oral count as visuals, one of each at most per card, and
# at most three cards have a source as their only visual. The parser refuses the blocks until their track makes them available, so the
# checks run here on a body that was changed after parsing.
class Lesson2Wave2ChecksTest < ActiveSupport::TestCase
  F = Lesson2Fixtures

  # +edit+ changes the parsed body of base.md; the checks run on it
  def run_checks
    findings = Validation::Findings.new
    parsed = F.check(F.read("base.md")).parsed
    parsed.body = Marshal.load(Marshal.dump(parsed.body))
    yield parsed.body
    Validation::Lesson2Checks::Run.new(parsed, "math", F.context("math"), findings).call
    findings
  end

  # blocks that pass the schema of lesson.json
  VALID = {
    "source" => { "kind" => "legal", "title_it" => "Costituzione, art. 1", "parts" => [ { "text_it" => "Testo di prova." } ] },
    "dialogue" => { "title_it" => "Due amici", "speakers" => [ { "id" => "t", "name" => "Tom" } ], "lines" => [ { "speaker" => "t", "text_en" => "Hello", "gloss_it" => "Ciao" }, { "speaker" => "t", "text_en" => "Bye", "gloss_it" => "Ciao" } ] },
    "oral" => { "question_it" => "Perché?", "outline" => [ { "id" => "o1", "text_it" => "uno" }, { "id" => "o2", "text_it" => "due" }, { "id" => "o3", "text_it" => "tre" } ], "answer" => %w[o1 o2 o3], "model_it" => "Così." },
    "reveal" => { "prompt_it" => "Pensaci", "answer_it" => "Ecco" },
    "image" => { "file" => "a.png", "alt_it" => "x", "source_it" => "y", "license" => "pd", "author" => "z", "source_url" => "https://example.org/a" }
  }.freeze

  def block(type, **fields) = { "n" => 1, "type" => type, "line" => 1 }.merge(VALID.fetch(type, {})).merge(fields.transform_keys(&:to_s))

  test "the new blocks are visuals, a plain reveal is not, and each kind has its single-per-card name" do
    assert Lessons::Blocks.visual?(block("source"))
    assert Lessons::Blocks.visual?(block("dialogue"))
    assert Lessons::Blocks.visual?(block("oral"))
    assert Lessons::Blocks.visual?(block("image"))
    assert Lessons::Blocks.visual?(block("reveal", options: [ { "id" => "a" } ]))
    assert_not Lessons::Blocks.visual?(block("reveal"))
    assert_equal "reveal_options", Lessons::Blocks.single_kind(block("reveal", options: [ { "id" => "a" } ]))
    assert_nil Lessons::Blocks.single_kind(block("reveal"))
    assert_equal "source", Lessons::Blocks.single_kind(block("source"))
    assert_equal 1, Lessons::Blocks.visual_count(block("source"))
    assert_equal 0, Lessons::Blocks.visual_count(block("reveal"))
    assert_equal 1, Lessons::Blocks.visual_count(block("reveal", options: [ { "id" => "a" } ]))
  end

  test "two sources, two dialogues or two oral blocks in one card are E-CARD-BLOCKS; one each is fine" do
    %w[source dialogue oral].each do |type|
      two = run_checks { |body| body["cards"][1]["blocks"] += [ block(type, n: 7), block(type, n: 8) ] }
      assert two.any? { |f| f.code == "E-CARD-BLOCKS" && f.message.include?("at most 1") }, type
      one = run_checks { |body| body["cards"][1]["blocks"] += [ block(type, n: 7) ] }
      assert_not one.any? { |f| f.code == "E-CARD-BLOCKS" && f.message.include?("at most 1") }, type
    end
  end

  test "four cards whose only visual is a source are E-CARD-NO-VISUAL, three are not" do
    sources = lambda do |n|
      run_checks { |body| body["cards"].select { |c| c["level"] == "core" }.first(n).each { |c| c["blocks"] = [ block("source") ] } }
        .select { |f| f.code == "E-CARD-NO-VISUAL" && f.message.include?("source as their only visual") }
    end
    assert_empty sources.call(3)
    assert_equal 1, sources.call(4).size
  end
end
