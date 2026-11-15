require "test_helper"

# W-MATH-LAST-NOTE (Lessons::Blocks::Simple.math): the page draws the note of a line between it and the next line, so the note of the
# last line is never shown. The case of lesson revision 1138 (Euclid's proof): the reason was written on the line it produces.
class MathBlockTest < ActiveSupport::TestCase
  def run_check(block)
    findings = Validation::Findings.new
    ctx = Lessons::Blocks::Context.new(subject: "math", findings: findings)
    ctx.at("/cards/2/blocks/1", 7) { Lessons::Blocks::Simple.check(block, ctx) }
    findings.map { |f| [ f.code, f.field ] }
  end

  def math(*lines) = { "n" => 2, "type" => "math", "lines" => lines }

  test "a note on the last line fires once, on that line's note_it" do
    block = math({ "tex" => "a = b" }, { "tex" => "a + c = b + c", "note_it" => "aggiungi c" }, { "tex" => "x = y", "note_it" => "perché le due parti restano uguali" })
    assert_equal [ [ "W-MATH-LAST-NOTE", "/cards/2/blocks/1/lines/2/note_it" ] ], run_check(block)
    assert_equal "warning", Validation::Codes.all.fetch("W-MATH-LAST-NOTE")["severity"]
  end

  test "notes between the lines, a last line without a note and a one-formula block are quiet" do
    assert_empty run_check(math({ "tex" => "a = b", "note_it" => "aggiungi c" }, { "tex" => "a + c = b + c", "note_it" => "semplifica" }, { "tex" => "x = y" }))
    assert_empty run_check(math({ "tex" => "a = b", "note_it" => "aggiungi c" }, { "tex" => "a + c = b + c", "note_it" => "  " }))
    assert_empty run_check({ "n" => 2, "type" => "math", "tex" => "a = b" })
  end

  test "the message tells where the reason of a line goes" do
    findings = Validation::Findings.new
    ctx = Lessons::Blocks::Context.new(subject: "math", findings: findings)
    ctx.at("/cards/0/blocks/0", 1) { Lessons::Blocks::Simple.check(math({ "tex" => "a" }, { "tex" => "b", "note_it" => "x" }), ctx) }
    assert_match(/never shown.*next one.*line before it/, findings.first.message)
  end
end
