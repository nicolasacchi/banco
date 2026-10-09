require "test_helper"
require_relative "../support/lesson2_fixtures"

# R0 of the rich lessons (D-244..D-251): the formats, the fixtures and the tables that R1 (Ruby) and
# R2 (browser) are built against. What cannot be run before the parsers exist is checked here by the
# crude splitter of test/support/lesson2_fixtures.rb (schema level only); the bad files of
# test/fixtures/lesson2/bad are run by R1 (one code each, manifest.json).
class Lesson2FixturesTest < ActiveSupport::TestCase
  F = Lesson2Fixtures
  GOOD_FILES = (F::MANIFEST["good_demos"] + F::MANIFEST["good"]).map { |g| g["file"] }.freeze
  CHROME_CODES = %w[E-LESSON-RENDER E-LESSON-OVERFLOW E-DIAGRAM-LAYOUT E-DIAGRAM-SMALL-TEXT].freeze
  SCHEMA_DEFS = JSON.parse(Rails.root.join("config/banco/schemas/lesson.json").read).fetch("$defs")

  GOOD_FILES.each do |file|
    test "#{file} is a valid banco.lesson/2 body once split" do
      body = F.body(F.read(file))
      assert_empty Banco::Schemas.validate("lesson", body).map(&:to_h), file
      assert_empty Banco::Schemas.validate_front_matter(F.front_matter(F.read(file))).map(&:to_h), "#{file}: front matter"
    end
  end

  test "every fence of every fixture is a block of release 1" do
    allowed = %w[callout math procedure cases legend example mistake check more summary schema diagram table try]
    (GOOD_FILES + F::MANIFEST["bad"].filter_map { |b| b["file"] }).each do |file|
      next if file == "bad/lesson1-after-the-switch.md"

      unknown = F.fences(F.read(file)) - allowed
      next if file.start_with?("bad/block-") # these use unknown or later blocks on purpose

      assert_empty unknown, file
    end
  end

  test "the cards of the good fixtures are counted as the manifest says" do
    F::MANIFEST["good"].each do |g|
      cards, parts = F.headings(F.read(g["file"]))
      assert_equal g["cards"], cards.size, g["file"]
      assert_equal g["parts"], parts.size, g["file"]
    end
  end

  test "a heading inside a YAML block scalar is no card (the fence-aware splitter)" do
    cards, parts = F.headings(F.read("good/heading-inside-yaml.md"))
    assert_equal 7, cards.size
    assert_empty parts
    assert_includes F.read("good/heading-inside-yaml.md"), "## Questa riga non è una scheda"
  end

  test "the manifest names a file, a known code and a line for every bad fixture" do
    registry = YAML.safe_load_file(Rails.root.join("config/banco/error_codes.yml")).fetch("validation")
    names = F::MANIFEST["bad"].map { |b| b["file"] }.compact
    assert_equal names.size, names.uniq.size
    F::MANIFEST["bad"].each do |b|
      assert registry.key?(b["code"]), "#{b['code']} is not in the registry"
      assert b["line"].nil? || b["line"].is_a?(Integer), b["file"]
      assert_path_exists F::DIR.join(b["file"]), b["file"] if b["file"]
      assert_path_exists F::DIR.join(b["base"]), b["file"] unless b["base"].start_with?("(")
      next unless b["line"] && b["file"]

      assert_operator b["line"], :<=, F.read(b["file"]).lines.size, "#{b['file']}: line"
    end
    assert_equal Dir[F::DIR.join("bad/*.md")].size, names.size, "every file in bad/ is in the manifest"
  end

  test "every lesson/2 code of the registry has a bad fixture, the render ones are R4's" do
    registry = YAML.safe_load_file(Rails.root.join("config/banco/error_codes.yml")).fetch("validation")
    lesson2 = registry.keys
    mine = %w[E-LESSON-CARD E-LESSON-CARDS E-CARD-WORDS E-CARD-BLOCKS E-CARD-NO-VISUAL E-CARD-ROLES E-LESSON-BLOCK E-LESSON-EXTRA-WORDS
              E-LESSON-MAP E-LESSON-CHECK E-LESSON-CHECKS E-LESSON-VISUALS E-LESSON-PARTS E-LESSON-DIAGRAM E-LESSON-ALT E-LESSON-ROLE
              E-LESSON-ICON E-LESSON-LINK E-LESSON-SIZE E-LESSON-SCHEMA W-LESSON-CHECKS-SPARSE W-CHECK-ANSWER-IN-PROMPT W-MISTAKE-CODE]
    assert_empty mine - lesson2, "codes missing from the registry"
    assert_empty mine - F::MANIFEST["bad"].map { |b| b["code"] }, "codes without a bad fixture"
    assert_empty CHROME_CODES - lesson2
    assert(CHROME_CODES.all? { |c| registry[c]["stage"] == "chrome" })
  end

  test "the demos cite lines of the invented course, with fragments that are exact substrings" do
    lines = F::CONTEXT.values_at("math", "italian").flat_map { |c| c["source_lines"] }
    %w[demo.md base.md demo-italian.md].each do |file|
      front = F.front_matter(F.read(file))
      subject = F::CONTEXT.fetch(front["subject"])
      assert_empty front["skills"] - subject["skills"], file
      assert_empty front["uses"] - subject["skills"], file
      front["refs"].each do |ref|
        line = lines.find { |l| l["source"] == ref["source"] && l["line"] == ref["line"] }
        assert line, "#{file}: #{ref['source']} line #{ref['line']}"
        assert_includes line["text"], ref["fragment"], file
      end
      codes = F.read(file).scan(/^\s*(?:code|.*\{answer: .*?, code): ?([a-z_]+)/).flatten
      assert_empty codes.uniq - subject["error_codes"], file
    end
  end

  test "numbers.json: the schema pattern accepts exactly the inputs it does not refuse" do
    diagram = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).fetch("$defs")
    num = Regexp.new(diagram["num"]["pattern"])
    num_inf = Regexp.new(diagram["num_or_inf"]["pattern"])
    numbers = JSON.parse(F::DIR.join("numbers.json").read)
    numbers["parse"].each do |v|
      accepted = (v["allow_inf"] ? num_inf : num).match?(v["input"])
      if v["refused"]
        next if v["input"].end_with?("inf") && !v["allow_inf"] # refused by context, not by the pattern

        assert_not accepted, "#{v['input'].inspect} should be refused"
      else
        assert accepted, "#{v['input'].inspect} should be accepted"
        assert_equal Rational(*v["canonical"].split("/").map(&:to_i)).to_s, v["canonical"] unless v["canonical"].end_with?("inf")
      end
    end
    numbers["compare"].each do |c|
      value = ->(s) { s.end_with?("inf") ? (s.start_with?("-") ? -Float::INFINITY : Float::INFINITY) : parse_exact(s) }
      assert_equal c["cmp"], value.call(c["a"]) <=> value.call(c["b"]), c.inspect
    end
  end

  def parse_exact(s)
    return Rational(s.tr(",", ".")) if s.include?(",")

    Rational(s)
  end

  test "the whitelist lists every declared field of every block and component, served or dropped" do
    wl = JSON.parse(F::DIR.join("whitelist.json").read)
    (wl["blocks"].values + wl["checks"].values).each do |entry|
      next unless (name = entry["def"]) && SCHEMA_DEFS.key?(name) && entry["serve"]

      declared = SCHEMA_DEFS.fetch(name).fetch("properties").keys
      listed = entry["serve"] + entry["drop"].map { |d| d[/\A[a-z_]+/] }
      assert_empty declared - listed - [ "line" ], "#{name}: declared and not listed"
      assert_empty (entry["serve"] + entry["drop"]) - declared, "#{name}: listed and not declared"
      assert_empty entry["serve"] & entry["drop"], name
    end
    assert_equal %w[choice fraction matching normalized_text number span_select], wl["checks"].keys.reject { |k| k.start_with?("_") }.sort
  end

  test "the whitelist drops every answer-side field of every component, and the solution fields match the schema" do
    wl = JSON.parse(F::DIR.join("whitelist.json").read)
    wl["checks"].each do |name, entry|
      next if name.start_with?("_")

      assert_includes entry["drop"], "answer", name
      assert_includes entry["drop"], "errors", name
      assert_includes entry["drop"], "explain_it", name
    end
    try = wl["blocks"]["try"]["nested"]["exercises"]
    assert_empty %w[final_it solution_it solution_steps] - try["drop"]
    assert_includes wl["blocks"]["example"]["drop"], "result_it"
    diagram = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).fetch("$defs")
    solution = diagram.select { |_, d| d.is_a?(Hash) && d["properties"]&.values&.any? { |p| p["x-banco-solution"] } }
                      .transform_values { |d| d["properties"].select { |_, p| p["x-banco-solution"] }.keys }
    assert_equal solution, wl["diagram"]["solution_fields"]
  end

  test "the markup cases for roles and links are in the shared v2 fixture, marked with their option" do
    cases = JSON.parse(Rails.root.join("test/fixtures/markup/v2.json").read).select { |c| c["options"] }
    assert_operator cases.count { |c| c["blocks"] }, :>=, 8
    assert_operator cases.count { |c| c["error"] }, :>=, 20
    refused = cases.select { |c| c["error"] }.map { |c| c["input"] }
    %w[\\htmlClass \\htmlId \\htmlStyle \\htmlData \\href \\url \\includegraphics \\def \\gdef \\newcommand].each do |cmd|
      assert(refused.any? { |i| i.include?(cmd) }, "#{cmd} is refused in a formula")
    end
    assert(cases.any? { |c| c["blocks"] && c["input"].include?("\\role{unknown}{x}") })
    assert(refused.any? { |i| i.include?("\\role{Unknown}{x}") })
  end
end
