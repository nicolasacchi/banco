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
end
