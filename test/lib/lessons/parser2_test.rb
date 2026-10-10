require "test_helper"

# Lessons::Parser2 and Lessons::Directives: the splitter and the directive bodies, on small inline sources (the bad
# files of test/fixtures/lesson2 are run by Lesson2ChecksTest).
class LessonsParser2Test < ActiveSupport::TestCase
  FRONT = <<~YAML
    ---
    schema: banco.lesson/2
    key: ripasso.math.demo-equations
    kind: ripasso
    subject: math
    title_it: "Prova"
    goals_it: ["**Fare** una prova"]
    skills: [math.demo-equation]
    refs:
      - {source: seconda-2025-26, line: 12, fragment: "x", role: needed_by}
    scope: studied
    minutes: 20
    calculator: false
    why_it: "Una frase. Un'altra frase."
    ---
  YAML

  def parse(body)
    findings = Validation::Findings.new
    [ Lessons::Parser2.call("#{FRONT}\n#{body}", findings), findings ]
  end

  def lines_of(findings, code) = findings.select { |f| f.code == code }.map { |f| f.detail[:line] }

  test "a card has a role, an id, an icon, a level and the lines of its heading and blocks" do
    parsed, findings = parse("## Prima {idea icon=scale id=prima}\n\nUn testo.\n\n::: callout tip\nBreve.\n:::\n\n## Dopo {example extra}\n\nAltro.\n")
    assert_empty findings.errors.map(&:to_h)
    first, second = parsed.body["cards"]
    assert_equal [ "prima", "idea", "core", "scale", 17 ], first.values_at("id", "role", "level", "icon", "line")
    assert_equal [ "c2", "example", "extra", "telescope" ], second.values_at("id", "role", "level", "icon")
    assert_equal [ "text", "callout" ], first["blocks"].map { |b| b["type"] }
    assert_equal [ 19, 21 ], first["blocks"].map { |b| b["line"] }
    assert_equal [ 1, 2 ], first["blocks"].map { |b| b["n"] }
    assert_nil second["part"]
  end

  test "a card may have a short name in quotes, for the map and the Avanti button" do
    parsed, findings = parse("## Tre casi: una soluzione, nessuna o tutte {idea short=\"Tre casi\" icon=scale}\n\nx\n\n## B {idea}\n\nx\n")
    assert_empty findings.errors.map(&:to_h)
    first, second = parsed.body["cards"]
    assert_equal [ "Tre casi", "scale", "Tre casi: una soluzione, nessuna o tutte" ], first.values_at("short_it", "icon", "title_it")
    assert_not second.key?("short_it")
    assert_equal "Tre casi", Lessons::StudentBody.project(parsed.body, revision_id: 1, seed: "s")["cards"][0]["short_it"]
  end

  test "a heading inside a block's YAML is text of that block, not a card or a part" do
    parsed, findings = parse("## A {idea}\n\n::: mistake\nwrong_it: x\nright_it: y\nwhy_it: |-\n  uno\n  ## Non una scheda\n  # Nemmeno una parte\ngroup_it: g\n:::\n")
    assert_empty findings.errors.map(&:to_h)
    assert_equal 1, parsed.body["cards"].size
    assert_empty parsed.parts
    assert_equal "uno\n## Non una scheda\n# Nemmeno una parte", parsed.body["cards"][0]["blocks"][0]["why_it"]
  end

  test "parts: each core card belongs to the part before it, an extra card to none" do
    parsed, = parse("# Uno\n\n## A {idea}\n\nx\n\n## B {idea}\n\nx\n\n# Due\n\n## C {idea}\n\nx\n\n## D {summary}\n\nx\n\n## E {idea extra}\n\nx\n")
    assert_equal [ 1, 1, 2, 2, nil ], parsed.body["cards"].map { |c| c["part"] }
    assert_equal [ "Uno", "Due" ], parsed.body["parts"].map { |p| p["title_it"] }
  end

  test "words count the prose of core cards and of the extra depth apart" do
    parsed, = parse("## A {idea}\n\nUno due tre.\n\n:::: more \"Di più\"\nQuattro cinque sei sette.\n::::\n\n## B {idea extra}\n\nOtto nove.\n")
    assert_equal({ "core" => 4, "extra" => 7 }, parsed.body["words"])
  end

  test "an unclosed block reports its own line, and a new directive inside it closes the report there" do
    _, findings = parse("## A {idea}\n\n::: callout tip\nBreve.\n\n::: callout tip\nAltro.\n:::\n")
    assert_equal [ 19 ], lines_of(findings, "E-LESSON-BLOCK")
  end

  test "a blank line is required before and after a fence" do
    _, findings = parse("## A {idea}\n\nTesto.\n::: callout tip\nBreve.\n:::\nAltro testo.\n")
    assert_equal [ 20, 23 ], lines_of(findings, "E-LESSON-BLOCK")
  end

  test "a more block holds text and blocks, and closes with four colons" do
    parsed, findings = parse("## A {idea}\n\n:::: more \"Titolo\"\nTesto.\n\n::: math\nx = 1\n:::\n::::\n")
    assert_empty findings.errors.map(&:to_h)
    more = parsed.body["cards"][0]["blocks"][0]
    assert_equal [ "text", "math" ], more["blocks"].map { |b| b["type"] }
    assert_equal "Titolo", more["title_it"]
  end

  test "a card heading needs a tag; a tag has one role, then optional tokens once each" do
    {
      "## Senza tag\n\nx\n" => "heading",
      "## A {}\n\nx\n" => "tag",
      "## A {idea extra extra}\n\nx\n" => "tag",
      "## A {idea icon=Scale}\n\nx\n" => "tag",
      "## A {idea colour=red}\n\nx\n" => "tag",
      "## A {idea short=\"x\"}\n\nx\n" => "tag: a short name has 2 characters at least",
      "## A {idea short=\"Uno\" short=\"Due\"}\n\nx\n" => "tag: short once",
      "## A {idea short=\"con $x$\"}\n\nx\n" => "tag: no formulas in a short name",
      "## A {idea short=Uno}\n\nx\n" => "tag: a short name is quoted",
      "## A {idea id=a}\n\nx\n\n## B {idea id=a}\n\nx\n" => "id"
    }.each do |source, what|
      _, findings = parse(source)
      assert_includes findings.errors.map(&:code), "E-LESSON-CARD", "#{what}: #{source.inspect}"
    end
  end

  test "math is one formula or a lines list; a summary is one list of points" do
    parsed, findings = parse("## A {summary}\n\n::: math\nlines:\n  - {tex: 'a'}\n  - {tex: 'b', note_it: 'poi'}\n:::\n\n::: summary\n- Uno.\n- Due.\n- Tre.\n:::\n")
    assert_empty findings.errors.map(&:to_h)
    assert_equal 2, parsed.body["cards"][0]["blocks"][0]["lines"].size
    assert_equal [ "Uno.", "Due.", "Tre." ], parsed.body["cards"][0]["blocks"][1]["points_it"]
  end

  test "a double-quoted YAML value with a backslash is refused; single quotes, block scalars and comments are not" do
    refused = ->(yaml) { Lessons::Directives.double_quoted_with_backslash(yaml) }
    assert refused.call('explain_it: "Con $x \neq 0$"')
    assert refused.call('  - {a: "x \cdot y"}')
    assert refused.call('- "a\nb"')
    assert_nil refused.call("explain_it: 'Con $x \\neq 0$'")
    assert_nil refused.call('explain_it: "Con $x$ senza barra"')
    assert_nil refused.call("key: dov'è \"questo\" \\ ok")
    assert_nil refused.call('prompt_it: x # un "commento \\ con barra"')
    assert_nil refused.call("note: 'it''s \"fine\" \\ really'")
  end

  test "a block scalar may hold double quotes with backslashes" do
    parsed, findings = parse("## A {idea}\n\n::: mistake\nwrong_it: |-\n  \"a \\neq b\"\nright_it: 'x'\nwhy_it: 'y'\n:::\n")
    assert_empty findings.errors.map(&:to_h)
    assert_equal "\"a \\neq b\"", parsed.body["cards"][0]["blocks"][0]["wrong_it"]
  end

  test "the front matter errors name the line of their member" do
    findings = Validation::Findings.new
    Lessons::Parser2.call(FRONT.sub("minutes: 20", "minutes: 'venti'") + "\n## A {idea}\n\nx\n", findings)
    assert_equal [ 12 ], lines_of(findings, "E-SCHEMA")
  end
end
