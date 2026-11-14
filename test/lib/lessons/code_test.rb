require "test_helper"
require_relative "../../support/lesson2_fixtures"

# The `code` block (D-329): the limits the schema leaves to a code of their own, the words it never adds to a word count, what the student's page
# is told about it, and the gallery that shows it.
class LessonsCodeTest < ActiveSupport::TestCase
  PROGRAM = "Module Program\n    Sub Main()\n        Console.WriteLine(\"Ciao\")\n    End Sub\nEnd Module\n".freeze
  BLOCK = { "n" => 1, "type" => "code", "lang" => "vb", "text" => PROGRAM }.freeze
  GALLERY = Rails.root.join("test/fixtures/lesson2/gallery/code.md")

  def run_check(block)
    findings = Validation::Findings.new
    ctx = Lessons::Blocks::Context.new(subject: "computer_science", findings: findings)
    ctx.at("/cards/0/blocks/0", 7) { Lessons::Blocks::Code.check(block, ctx) }
    findings.map { |f| [ f.code, f.field ] }
  end

  def with(**changes) = BLOCK.merge(changes.transform_keys(&:to_s))

  # The base lesson with the block as the only block of its second card, against the lesson schema.
  def schema_errors(block)
    body = Marshal.load(Marshal.dump(Lesson2Fixtures.check(Lesson2Fixtures.read("base.md")).parsed.body))
    body["cards"][1]["blocks"] = [ { "n" => 1 }.merge(block) ]
    Banco::Schemas.validate("lesson", body).map(&:to_h)
  end

  def lines(count, width: 20) = Array.new(count) { |i| "x#{i}".ljust(width, "x") }.join("\n")

  test "a good block passes, with or without what is typed and what the screen shows" do
    assert_empty run_check(BLOCK)
    assert_empty run_check(with(title_it: "La torre saluta", input_it: %w[35000 Marta], output: "Quota: 35000 piedi\nCiao, Marta!", note_it: "Scrivi 35000 e premi Invio."))
  end

  test "only vb is a language of the block" do
    assert_equal [ [ "E-LESSON-CODE-LANG", "/cards/0/blocks/0/lang" ] ], run_check(with(lang: "c"))
    assert_equal [ [ "E-LESSON-CODE-LANG", "/cards/0/blocks/0/lang" ] ], run_check(with(lang: "VB"))
  end

  test "a program has at most 60 lines of at most 90 characters; the newline it ends with is no line" do
    assert_empty run_check(with(text: "#{lines(60, width: 90)}\n"))
    assert_equal [ [ "E-LESSON-CODE-SIZE", "/cards/0/blocks/0/text" ] ], run_check(with(text: lines(61)))
    assert_equal [ [ "E-LESSON-CODE-SIZE", "/cards/0/blocks/0/text" ] ], run_check(with(text: "#{lines(60)}\n\n"))
    assert_equal [ [ "E-LESSON-CODE-SIZE", "/cards/0/blocks/0/text" ] ], run_check(with(text: "x" * 91))
    assert_empty run_check(with(text: "x" * 90))
    assert_equal [ [ "E-LESSON-CODE-SIZE", "/cards/0/blocks/0/text" ] ], run_check(with(text: " \n  \n"))
  end

  test "a tab is refused in the program and in the output, with the line" do
    assert_equal [ [ "E-LESSON-CODE-TAB", "/cards/0/blocks/0/text" ] ], run_check(with(text: "Module Program\n\tSub Main()\n"))
    assert_equal [ [ "E-LESSON-CODE-TAB", "/cards/0/blocks/0/output" ] ], run_check(with(output: "a\tb"))
    findings = Validation::Findings.new
    ctx = Lessons::Blocks::Context.new(subject: "computer_science", findings: findings)
    ctx.at("/cards/0/blocks/0", 7) { Lessons::Blocks::Code.check(with(text: "a\nb\n\tc"), ctx) }
    assert_match(/line 3 /, findings.first.message)
  end

  test "the output has at most 30 lines of at most 90 characters" do
    assert_empty run_check(with(output: lines(30, width: 90)))
    assert_equal [ [ "E-LESSON-CODE-SIZE", "/cards/0/blocks/0/output" ] ], run_check(with(output: lines(31)))
    assert_equal [ [ "E-LESSON-CODE-SIZE", "/cards/0/blocks/0/output" ] ], run_check(with(output: "y" * 91))
  end

  test "what S types is at most 12 lines of at most 40 characters, each one line" do
    assert_empty run_check(with(input_it: Array.new(12) { "4" * 40 }))
    assert_equal [ [ "E-LESSON-CODE-SIZE", "/cards/0/blocks/0/input_it" ] ], run_check(with(input_it: Array.new(13, "1")))
    assert_equal [ [ "E-LESSON-CODE-SIZE", "/cards/0/blocks/0/input_it/0" ] ], run_check(with(input_it: [ "4" * 41 ]))
    assert_equal [ [ "E-LESSON-CODE-TAB", "/cards/0/blocks/0/input_it/1" ] ], run_check(with(input_it: [ "1", "a\tb" ]))
  end

  test "the schema holds the shape: required fields, no other field, strings" do
    assert_empty schema_errors(BLOCK.merge("line" => 3))
    assert_empty schema_errors(with(title_it: "T", input_it: [ "1" ], output: "1", note_it: "n"))
    [ { "lang" => nil }, { "text" => nil }, { "answer" => "x" }, { "input_it" => "35000" }, { "input_it" => [] }, { "output" => "" }, { "text" => "" }, { "title_it" => "x" * 81 } ].each do |change|
      block = BLOCK.merge(change).compact
      assert_not_empty schema_errors(block), change.inspect
    end
  end

  test "a code block is never prose: no word count reads its program, its screen, its title or its note" do
    long = with(title_it: "uno due tre", text: ([ "' una riga di commento con molte parole dentro" ] * 50).join("\n"), output: "ciao " * 30, note_it: "una nota", input_it: %w[uno due])
    assert_empty Lessons::Blocks.prose(long)
    card = { "title_it" => "Un titolo", "blocks" => [ long ] }
    assert_equal Lessons::Blocks.words("Un titolo"), Lessons::Blocks.prose_words(card)
    assert_equal 0, Lessons::Blocks.apparatus_words(long)
    assert_not Lessons::Blocks.visual?(long)
    assert_equal 0, Lessons::Blocks.visual_count(long)
    assert_equal [], Lessons::Blocks.checks(long)
  end

  test "only the title and the note are markup; the program is plain characters" do
    block = with(title_it: "Il **programma**", note_it: "Scrivi `x`", text: "Dim s As String = $\"{a} e {b}\"\n' [[code:no]] $x_1$")
    assert_equal %w[title_it note_it], Lessons::Blocks.markup_fields(block).map(&:first)
  end

  test "the student's page is told the whole block, and not the line of the source" do
    body = { "cards" => [ { "n" => 1, "id" => "c", "role" => "idea", "level" => "core", "title_it" => "T", "blocks" => [ BLOCK.merge("line" => 9, "title_it" => "Titolo", "input_it" => [ "1" ], "output" => "1\n", "note_it" => "n") ] } ] }
    served = Lessons::StudentBody.project(body, revision_id: 1, seed: "s")["cards"][0]["blocks"][0]
    assert_equal %w[lang n note_it input_it output text title_it type].sort, served.keys.sort
    assert_equal PROGRAM, served["text"], "the program is served as written, every space and newline"
    assert_equal({ "n" => 1, "type" => "code", "lang" => "vb", "text" => PROGRAM }, Lessons::StudentBody.project({ "cards" => [ { "n" => 1, "blocks" => [ BLOCK.merge("line" => 9) ] } ] }, revision_id: 1, seed: "s")["cards"][0]["blocks"][0])
  end

  test "the registry lists the block as available, and its caps are in the rules" do
    assert Lessons::Types.available?(:block, "code")
    assert_equal({ "lines" => 60, "line_chars" => 90, "input_lines" => 12, "input_chars" => 40, "output_lines" => 30 }, Validation::Rules.get(:lesson2, :types, :code).transform_keys(&:to_s))
  end

  test "the gallery parses with no finding, keeps the programs as written, and every block of it passes the checks" do
    findings = Validation::Findings.new
    body = Lessons::Parser2.call(GALLERY.read, findings).body
    assert_empty findings.errors.map(&:to_h)
    assert_empty Banco::Schemas.validate("lesson", body).map(&:to_h)
    blocks = body["cards"].flat_map { |c| c["blocks"] }.select { |b| b["type"] == "code" }
    assert_equal 4, blocks.size
    # a `|` block ends with a newline only when another key follows it: both are programs, and "Copia" copies the one that is stored
    assert_equal "Module Program\n    Sub Main()\n        Console.WriteLine(\"Ciao, mondo!\")\n    End Sub\nEnd Module", blocks[0]["text"]
    assert blocks[1]["text"].end_with?("End Module\n")
    assert_includes blocks[1]["text"], "Imports System\n\nModule Program", "an empty line is kept"
    assert_equal [ "35000" ], blocks[1]["input_it"]
    wide = blocks[2]["text"].lines.map { |l| l.chomp.length }.max
    assert_equal 90, wide, "the gallery has a line as long as the rules allow"
    assert_includes blocks[2]["text"], "\n\n", "an empty line inside the program is kept"
    blocks.each { |b| assert_empty run_check(b), b["text"] }
  end

  test "the lesson checks give the code of the fixture and the line of the field" do
    codes = { "bad/code-lang.md" => [ "E-LESSON-CODE-LANG", 46 ], "bad/code-size.md" => [ "E-LESSON-CODE-SIZE", 47 ], "bad/code-tab.md" => [ "E-LESSON-CODE-TAB", 47 ] }
    codes.each do |file, (code, line)|
      out = Lesson2Fixtures.check(Lesson2Fixtures.read(file), "math")
      hit = out.findings.find { |f| f.code == code }
      assert hit, "#{file}: #{out.findings.map(&:code).inspect}"
      assert_equal line, hit.detail[:line], file
    end
  end

  test "a code block in a lesson of the course adds no word to its card (the cap of 90 counts the prose only)" do
    text = Lesson2Fixtures.read("base.md").sub("## Un'equazione è una bilancia {idea icon=scale id=bilancia}\n", "## Un'equazione è una bilancia {idea icon=scale id=bilancia}\n\n::: code\nlang: vb\ntext: |\n#{([ '  \' una riga con tante parole una dopo l altra per molte volte' ] * 40).join("\n")}\n:::\n")
    out = Lesson2Fixtures.check(text, "math")
    assert_equal Lesson2Fixtures.check(Lesson2Fixtures.read("base.md"), "math").findings.map(&:code), out.findings.map(&:code)
  end
end
