require "test_helper"
require_relative "../../support/lesson2_fixtures"

# The checks of the docs family's blocks (T8): source (legal), reveal and oral, and the apparatus budget, on the parsed gallery lesson changed
# after parsing (the schema has made the shape right; these are the rules it cannot hold).
class LessonsDocsBlocksTest < ActiveSupport::TestCase
  F = Lesson2Fixtures

  # The findings of the checks on the gallery lesson after +edit+ has changed its parsed body.
  def findings_after
    findings = Validation::Findings.new
    parsed = F.check(F.read("gallery/docs-lesson.md"), "business").parsed
    parsed.body = Marshal.load(Marshal.dump(parsed.body))
    yield parsed.body
    Validation::Lesson2Checks::Run.new(parsed, "business", F.context("business"), findings).call
    findings
  end

  def block_of(body, type, &condition)
    body["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == type && (condition.nil? || condition.call(b)) }
  end

  def hits(findings, code, rule = nil)
    findings.select { |f| f.code == code && (rule.nil? || f.detail[:rule].to_s.include?(rule)) }
  end

  test "the gallery lesson itself has no finding" do
    assert_empty findings_after { |_| }.map(&:to_h)
  end

  test "a legal source must quote its reference: a changed word, an unknown reference and no reference are refused" do
    changed = findings_after { |b| block_of(b, "source")["parts"][0]["text_it"] = "Il venditore spedisce la merce nel luogo e nel giorno indicati nel contratto." }
    assert_equal 1, hits(changed, "E-QUOTE-REF").size
    unknown = findings_after { |b| block_of(b, "source")["ref"] = "codice-inventato" }
    assert_equal [ "/cards/2/blocks/0/ref" ], hits(unknown, "E-QUOTE-REF").map(&:field)
    missing = findings_after { |b| block_of(b, "source").delete("ref") }
    assert_equal 1, hits(missing, "E-LESSON-BLOCK", "ref-missing").size
    spaces = findings_after { |b| block_of(b, "source")["parts"][0]["text_it"] = "Il venditore consegna  la merce\nnel luogo e nel giorno indicati nel contratto." }
    assert_empty hits(spaces, "E-QUOTE-REF"), "whitespace is not part of a quotation"
  end

  test "on a core card every part has its plain version, on an extra card all or none" do
    core = findings_after { |b| block_of(b, "source")["parts"][1].delete("plain_it") }
    assert_equal 1, hits(core, "E-LESSON-BLOCK", "plain-missing").size
    extra = findings_after do |b|
      b["cards"][2]["level"] = "extra"
      block_of(b, "source")["parts"][1].delete("plain_it")
    end
    assert_equal 1, hits(extra, "E-LESSON-BLOCK", "plain-partial").size
    none = findings_after do |b|
      b["cards"][2]["level"] = "extra"
      block_of(b, "source")["parts"].each { |p| p.delete("plain_it") }
    end
    assert_empty hits(none, "E-LESSON-BLOCK", "plain-")
  end

  test "a part is at most 60 words, a mark and a guided span are exact pieces of the quotation, a legal source has no historical fields" do
    long = Array.new(61) { "ab" }.join(" ")
    f = findings_after do |b|
      p = block_of(b, "source")["parts"][0]
      p["text_it"] = long
      p["plain_it"] = long
    end
    assert_equal 1, hits(f, "E-LESSON-BLOCK", "part-words-0").size
    assert_equal 1, hits(f, "E-LESSON-BLOCK", "plain-words-0").size
    mark = findings_after { |b| block_of(b, "source")["parts"][0]["marks"] = [ { "text_it" => "la nave", "role" => "creditor" } ] }
    assert_equal 1, hits(mark, "E-LESSON-BLOCK", "mark-0-0").size
    role = findings_after { |b| block_of(b, "source")["parts"][0]["marks"] = [ { "text_it" => "Il venditore", "role" => "colour-that-does-not-exist" } ] }
    assert_equal 1, hits(role, "E-LESSON-ROLE").size
    guide = findings_after { |b| block_of(b, "source")["guide"] = [ { "span_it" => "a spese del cliente", "note_it" => "x" } ] }
    assert_equal 1, hits(guide, "E-LESSON-BLOCK", "guide-0").size
    historical = findings_after { |b| block_of(b, "source")["translation"] = "simplified" }
    assert_equal 1, hits(historical, "E-LESSON-BLOCK").size
  end

  test "a reveal with options has exactly one real road, short outcomes and no prompt; a plain reveal has no year" do
    two = findings_after { |b| block_of(b, "reveal") { |r| r["options"] }["options"][0]["real"] = true }
    assert_equal 1, hits(two, "E-LESSON-BLOCK", "real-count").size
    none = findings_after { |b| block_of(b, "reveal") { |r| r["options"] }["options"].each { |o| o.delete("real") } }
    assert_equal 1, hits(none, "E-LESSON-BLOCK", "real-count").size
    mixed = findings_after { |b| block_of(b, "reveal") { |r| r["options"] }["prompt_it"] = "Pensaci." }
    assert_equal 1, hits(mixed, "E-LESSON-BLOCK", "mixed-prompt_it").size
    long = findings_after { |b| block_of(b, "reveal") { |r| r["options"] }["options"][1]["then_it"] = Array.new(26) { "ab" }.join(" ") }
    assert_equal 1, hits(long, "E-LESSON-BLOCK", "then-words-1").size
    answer = findings_after { |b| block_of(b, "reveal") { |r| r["answer_it"] }["answer_it"] = Array.new(41) { "ab" }.join(" ") }
    assert_equal 1, hits(answer, "E-LESSON-BLOCK", "answer-words").size
    year = findings_after { |b| block_of(b, "reveal") { |r| r["answer_it"] }["year"] = "14" }
    assert_equal 1, hits(year, "E-LESSON-BLOCK", "plain-year").size
  end

  test "an oral's answer is the outline in order, its typical errors are other orders, its model is at most 120 words" do
    answer = findings_after { |b| block_of(b, "oral")["answer"] = %w[o1 o2 o3 o3] }
    assert_equal 1, hits(answer, "E-LESSON-BLOCK", "answer-permutation").size
    same = findings_after { |b| block_of(b, "oral")["errors"][0]["answer"] = block_of(b, "oral")["answer"] }
    assert_equal 1, hits(same, "E-LESSON-CHECK").size
    partial = findings_after { |b| block_of(b, "oral")["errors"][0]["answer"] = %w[o1 o2] }
    assert_equal 1, hits(partial, "E-LESSON-CHECK").size
    model = findings_after { |b| block_of(b, "oral")["model_it"] = Array.new(121) { "ab" }.join(" ") }
    assert_equal 1, hits(model, "E-LESSON-BLOCK", "model-words").size
    ids = findings_after { |b| block_of(b, "oral")["outline"][1]["id"] = "o1" }
    assert_equal 1, hits(ids, "E-LESSON-BLOCK", "outline-ids").size
  end

  test "the apparatus: 250 words open by default beside the prose, 240 words of originals behind a tap" do
    assert_equal 33, Lessons::Blocks.apparatus_words(block_of(F.check(F.read("gallery/docs-lesson.md"), "business").body, "source")) # the two plain versions
    blocks = F.check(F.read("gallery/docs-lesson.md"), "business").body["cards"].flat_map { |c| c["blocks"] }
    cross = blocks.find { |b| b["type"] == "reveal" && b["options"] }
    assert_operator Lessons::Blocks.apparatus_words(cross), :>, 30
    assert_equal 0, Lessons::Blocks.apparatus_words(blocks.find { |b| b["type"] == "oral" })
    assert_operator Lessons::Blocks.closed_original_words(block_of(F.check(F.read("gallery/docs-lesson.md"), "business").body, "source")), :>, 20

    over = findings_after do |b|
      b["cards"][0]["blocks"] << block_of(b, "source").merge("n" => 7, "parts" => [ { "text_it" => "Il venditore consegna la merce", "plain_it" => Array.new(90) { "a" }.join(" ") } ])
      b["cards"][1]["blocks"] << block_of(b, "source").merge("n" => 7, "parts" => [ { "text_it" => "Il venditore consegna la merce", "plain_it" => Array.new(90) { "a" }.join(" ") } ])
      b["cards"][3]["blocks"] << block_of(b, "source").merge("n" => 7, "parts" => [ { "text_it" => "Il venditore consegna la merce", "plain_it" => Array.new(90) { "a" }.join(" ") } ])
    end
    assert_equal 1, hits(over, "E-LESSON-APPARATUS-WORDS", "open").size
    closed = findings_after do |b|
      source = block_of(b, "source")
      source["parts"] = Array.new(4) { |i| { "text_it" => Array.new(60) { "legge#{i}" }.join(" "), "plain_it" => "Una frase." } }
      b["cards"].find { |c| c["blocks"].any? { |x| x["type"] == "oral" } }["blocks"] << source.merge("n" => 7)
    end
    assert_equal 1, hits(closed, "E-LESSON-APPARATUS-WORDS", "closed").size
  end

  test "open: original puts the law's words first and then the quotation counts as open, not as closed" do
    body = F.check(F.read("gallery/docs-lesson.md"), "business").body
    source = block_of(body, "source").merge("open" => "original")
    assert_equal 0, Lessons::Blocks.closed_original_words(source)
    assert_equal source["parts"].sum { |p| Lessons::Blocks.words(p["text_it"]) }, Lessons::Blocks.apparatus_words(source)
  end
end
