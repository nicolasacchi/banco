require "test_helper"
require_relative "../support/lesson2_fixtures"

# R1: the lesson/2 parser and checks against the fixtures of R0 (test/fixtures/lesson2): the good ones pass with no
# error, every bad one gives its code (manifest.json) at its line.
class Lesson2ChecksTest < ActiveSupport::TestCase
  F = Lesson2Fixtures

  def subject_of(file) = file.include?("italian") ? "italian" : "math"

  def outcome(file) = F.check(F.read(file), subject_of(file))

  def errors(outcome) = outcome.findings.errors.map { |f| [ f.code, f.field, f.detail[:line] ] }

  # The point of good/heading-inside-yaml.md is the splitter (a ## line in a block scalar is no card); the strict markup
  # of a solution still refuses a heading in its text, as it must.
  (F::MANIFEST["good_demos"] + F::MANIFEST["good"]).reject { |g| g["file"] == "good/heading-inside-yaml.md" }.each do |g|
    test "#{g['file']} passes with no finding" do
      o = outcome(g["file"])
      assert_empty o.findings.reject { |f| f.code == "W-ABSOLUTE" }.map(&:to_h), g["file"]
      assert_equal "banco.lesson/2", o.body["schema"]
      assert_empty Banco::Schemas.validate("lesson", o.body)
    end
  end

  test "a ## and a # line inside a block scalar are text of that block, not a card or a part" do
    o = outcome("good/heading-inside-yaml.md")
    assert_equal 7, o.body && o.body["cards"].size || o.parsed.cards.size
    assert_empty o.parsed.parts
    assert_equal [ "E-LESSON-MARKUP" ], o.findings.codes
  end

  test "the good fixtures give the cards and parts the manifest counts" do
    F::MANIFEST["good"].reject { |g| g["file"] == "good/heading-inside-yaml.md" }.each do |g|
      body = outcome(g["file"]).body
      assert_equal g["cards"], body["cards"].size, g["file"]
      assert_equal g["parts"], Array(body["parts"]).size, g["file"]
      assert_equal g["extra"].to_i, body["cards"].count { |c| c["level"] == "extra" }, g["file"]
    end
  end

  F::MANIFEST["bad"].each do |bad|
    next if bad["file"].nil? || bad["code"] == "E-LESSON-SCHEMA" || bad["pad_front_matter_bytes"]

    test "#{bad['file']} gives #{bad['code']}#{" at line #{bad['line']}" if bad['line']}" do
      o = F.check(F.read(bad["file"]), subject_of(bad["base"]))
      hits = o.findings.select { |f| f.code == bad["code"] }
      assert hits.any?, "#{bad['file']}: expected #{bad['code']}, got #{o.findings.map { |f| [ f.code, f.detail[:line] ] }.inspect}"
      next unless bad["line"]

      lines = hits.filter_map { |f| f.detail[:line] }
      assert_includes lines, bad["line"], "#{bad['file']}: #{bad['code']} at #{lines.inspect}, the manifest says #{bad['line']}"
    end
  end

  test "a lesson.md over 96 KB is E-LESSON-SIZE" do
    text = F.read("base.md").sub("---\n", "---\n#{"# x\n" * 40_000}")
    assert_operator text.bytesize, :>, 98_304
    assert_includes F.check(text).findings.codes, "E-LESSON-SIZE"
  end

  test "a lesson/1 file is accepted while lesson.accept_schema1 is true, and E-LESSON-SCHEMA after the switch" do
    require_relative "../support/lesson_md"
    md = LessonMd.build
    assert_not_includes Validation::LessonChecks.call(md, subject: "math", context: LessonMd.context).findings.codes, "E-LESSON-SCHEMA"
    Validation::Rules.with(lesson: { accept_schema1: false }) do
      o = Validation::LessonChecks.call(md, subject: "math", context: LessonMd.context)
      assert_equal [ "E-LESSON-SCHEMA" ], o.findings.codes
      assert_nil o.body
    end
  end

  # A fault is a finding, never an exception: whatever an agent sends, the answer is a list of findings.
  RUNS = Integer(ENV.fetch("PROP_RUNS", 50))
  JUNK = [ ":::", "::::", "::: check", "::: diagram balance", "## x {idea}", "## x", "# part", "```", "- punto", "  - sotto", "1. uno", "[[a:b]]", "[x](scheda:y)", "$", "**", "answer: [", "---", "\\", "\t", "" ].freeze

  test "mutated lessons never raise: a fault is a finding (#{RUNS} runs)" do
    sources = %w[base.md demo.md demo-italian.md].map { |f| [ f, F.read(f).lines ] }
    RUNS.times do |run|
      rng = Random.new(run)
      file, lines = sources.sample(random: rng)
      lines = lines.dup
      rng.rand(1..3).times do
        i = rng.rand([ lines.size, 1 ].max)
        case rng.rand(5)
        when 0 then lines.delete_at(i)
        when 1 then lines.insert(i, "#{JUNK.sample(random: rng)}\n")
        when 2 then lines[i] = "#{JUNK.sample(random: rng)}\n"
        when 3 then lines = lines.first(i)
        else j = rng.rand([ lines.size, 1 ].max); lines[i], lines[j] = lines[j], lines[i] if lines[i] && lines[j]
        end
      end
      begin
        outcome = F.check(lines.join, subject_of(file))
        outcome.findings.each(&:to_h)
      rescue StandardError => e
        flunk "run #{run} (#{file}): #{e.class}: #{e.message.first(120)} at #{e.backtrace.first(3).join(' / ')}"
      end
    end
    assert_operator RUNS, :>, 0
  end

  test "a bad fixture gives its code and nothing unrelated (the companions are known)" do
    companions = { "bad/cards-two-summaries.md" => %w[E-LESSON-MAP], "bad/card-callout-words.md" => %w[E-READ], "bad/checks-too-few.md" => %w[W-LESSON-CHECKS-SPARSE],
                   "bad/visuals-thirteen.md" => %w[E-CARD-BLOCKS], "bad/front-kind-disagrees-with-key.md" => %w[E-LESSON-REFS], "bad/front-book-too-long.md" => %w[E-READ],
                   "bad/bold-too-much.md" => %w[E-READ] }
    F::MANIFEST["bad"].each do |bad|
      next if bad["file"].nil? || bad["code"] == "E-LESSON-SCHEMA" || bad["pad_front_matter_bytes"]

      codes = F.check(F.read(bad["file"]), subject_of(bad["base"])).findings.map(&:code).uniq - %w[W-ABSOLUTE]
      assert_empty codes - [ bad["code"] ] - companions.fetch(bad["file"], []), bad["file"]
    end
  end
end
