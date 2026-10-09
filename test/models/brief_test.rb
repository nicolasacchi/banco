require "test_helper"

# C-03: the authoring briefs are versioned files in git.
class BriefTest < ActiveSupport::TestCase
  NAMES = %w[arbiter blueprint course diagnosis-item grade lesson lesson-review lesson-v1 practice-item review skill-graph solve topic].freeze
  VERSION_2 = %w[diagnosis-item review lesson lesson-review].freeze # D-227: practice items, review points 12-13; D-245: lesson/2 and its review

  test "the thirteen briefs exist (version 1, or 2 for the Phase 1b and rich-lesson deltas) with a body" do
    assert_equal NAMES, Brief.names
    NAMES.each do |name|
      brief = Brief.find(name)
      assert_equal VERSION_2.include?(name) ? 2 : 1, brief.version, name
      assert_equal name, brief.name
      assert_operator brief.body.size, :>, 800, name
    end
  end

  test "every brief says to work through banco, never ask for a decision, and keeps the repository public-safe" do
    NAMES.each do |name|
      body = Brief.find(name).body
      assert_match(/banco status/, body, name)
      assert_match(/decision/i, body, name)
      assert_match(/## Public repository/, body, name)
      assert_match(/the student/, body, name)
    end
  end

  test "the item brief carries the writing rules of C-03" do
    body = Brief.find("diagnosis-item").body.squish
    [ "at most 25 words", "never 2", "Exactly one option is defensible", "exact substring",
      "Never invent a page number", "Prova A", "Transcription doubts go to the teacher",
      "metalanguage", "over-absolute", "exam-gaming", "choice_only_reason_it" ].each do |needle|
      assert_includes body, needle
    end
    assert_equal 14, Brief.find("diagnosis-item").body.scan(/^\d+\. \*\*/).size
  end

  test "the solve brief carries a complete example that the schema accepts" do
    body = Brief.find("solve").body
    json = body[/```json\n(.*?)```/m, 1]
    assert json, "the solve brief has a json example"
    doc = JSON.parse(json)
    %w[schema schema_version revision answers].each { |k| assert doc.key?(k), "example lacks #{k}" }
    assert_empty Banco::Schemas.validate("solve", doc)
  end

  test "the solve brief states the testlet and short_answer answer shapes" do
    body = Brief.find("solve").body
    assert_match(/testlet.*object from each sub item id/m, body)
    assert_match(/short_answer.*plain string/m, body)
    assert_match(/never produces a mismatch.*sample answer/m, body)
  end

  test "the solve brief says one submit per session and what --dry-run is for" do
    body = Brief.find("solve").body
    assert_match(/only one submit.*solve submit REV --file answers.json --dry-run/m, body)
    assert_match(/mismatch count; do not change an\s+answer/, body)
  end

  test "briefs mention only formats that exist" do
    NAMES.each do |name|
      Brief.find(name).body.scan(%r{banco\.(\w+)/1}).flatten.each do |format|
        assert_includes Banco::Schemas::NAMES, format, "#{name} mentions banco.#{format}/1"
      end
    end
  end

  test "unknown or unsafe names give nil" do
    [ nil, "", "nope", "../x", "diagnosis-item.md", "Diagnosis-item" ].each { |n| assert_nil Brief.find(n), n.inspect }
  end

  test "a brief without front matter or with a wrong name is refused" do
    assert_raises(ArgumentError) { Brief.new("x", "no front matter") }
    assert_raises(ArgumentError) { Brief.new("x", "---\nname: y\nversion: 1\n---\nbody") }
  end

  test "the sha256 is the hash of the file" do
    assert_equal Digest::SHA256.file(Rails.root.join("briefs/review.md")).hexdigest, Brief.find("review").sha256
  end

  test "session examples in briefs name no concrete agent" do
    Brief.names.each do |n|
      body = Brief.find(n).body
      assert_no_match(/--agent omp\b/, body, n)
    end
  end

  test "the review brief states the evidence minimum and the stock phrase check" do
    body = Brief.find("review").body.squish
    assert_match(/at least #{Review::Checklist::MIN_WORDS} words/, body)
    assert_match(/stock phrase/, body)
    assert_match(/E-REVIEW-EMPTY/, body)
  end

  test "the review brief gives an example for absence points" do
    body = Brief.find("review").body.squish
    assert_match(/points about an absence/, body)
    assert_match(/name the fields you read/, body)
  end

  test "the review brief allocates a unique scratch directory" do
    body = Brief.find("review").body
    assert_includes body, 'mktemp -d "$TMPDIR/rv-SUBJECT-XXXXXX"'
    assert_no_match(/for example `\$TMPDIR\/rv-SUBJECT-1`/, body)
  end

  def json_example(name)
    json = Brief.find(name).body[/```json\n(.*?)```/m, 1]
    assert json, "the #{name} brief has a json example"
    JSON.parse(json)
  end

  test "the course, topic and lesson-review briefs carry examples their schemas accept" do
    assert_empty Banco::Schemas.validate("course", json_example("course"))
    assert_empty Banco::Schemas.validate("topic", json_example("topic"))
    review = json_example("lesson-review")
    review["checklist"] = (1..11).map { |i| { "id" => i, "result" => "pass", "evidence" => "Ho letto l'intera lezione con attenzione." } }
    assert_empty Banco::Schemas.validate("lesson_review", review)
  end

  test "the lesson-v1 brief names the eight sections, the book line and the limits of the rules file" do
    brief = Brief.find("lesson-v1")
    assert_equal "banco.lesson/1", brief.body[/banco\.lesson\/1/]
    body = brief.body
    [ "## Perché ti serve", "## L'idea in breve", "## Esempio svolto", "## Errori da evitare", "## Prova tu",
      "## Soluzioni", "## Sul libro", "## In sintesi" ].each { |h| assert_includes body, h }
    assert_includes body, Validation::Rules.get(:lesson, :book_line)
    squished = body.squish
    assert_includes squished, "At most #{Validation::Rules.get(:lesson, :max_words)} words"
    assert_includes squished, "at most #{(Validation::Rules.get(:lesson, :max_bold_ratio) * 100).to_i}% of the words"
  end

  test "the lesson brief (version 2) states the numbers of the lesson2 block of the rules file" do
    body = Brief.find("lesson").body.squish
    r = ->(key) { Validation::Rules.get(:lesson2, key) }
    l = ->(key) { Validation::Rules.list(:lesson2, key) }
    assert_includes body, "at most #{r.call(:max_bytes) / 1024} KB"
    assert_includes body, "At most #{r.call(:max_words)} words of core prose"
    assert_includes body, "at most #{r.call(:max_card_words)} words per core card and #{r.call(:callout_words)} per callout"
    assert_includes body, "#{l.call(:blocks_per_card).join(' to ')} blocks per card"
    assert_includes body, "Core cards: #{l.call(:core_cards).join(' to ')}"
    assert_includes body, "#{l.call(:checks_core).join(' to ')} checks outside the `try` card"
    assert_includes body, "At most #{r.call(:visuals_core_max)} diagrams, schemas and procedures in core"
    assert_includes body, "at most #{r.call(:states_max)} states"
    assert_includes body, "Depth (`more` blocks and extra cards) at most #{r.call(:extra_words)} words, one `more` at most #{r.call(:more_words)}"
    assert_includes body, "At most 3 roles whose carrier is an icon"
    assert_equal 3, r.call(:icon_roles_per_card)
    assert_includes body, "banco brief show lesson-v1"
  end

  test "the lesson brief names every role, icon, step verb and diagram type of release 1, and no other" do
    body = Brief.find("lesson").body
    palette = YAML.safe_load_file(Rails.root.join("config/banco/lesson_palette.yml"))
    icons = YAML.safe_load_file(Rails.root.join("config/banco/icons.yml"))
    (palette["common"].keys + palette["math"]["roles"].keys + palette["italian"]["roles"].keys).uniq.each { |role| assert_includes body, "`#{role}`", role }
    palette["step_tags"].each_value { |tags| tags.each_key { |tag| assert_includes body, "`#{tag}`", tag } }
    (icons["structural"].keys + icons["subjects"].values.flat_map(&:keys)).uniq.each { |icon| assert_includes body, "`#{icon}`", icon }
    # `check` is also a block name of the brief, so it cannot tell a ui icon from the block
    icons["ui"].keys.reject { |k| icons["structural"].key?(k) || icons["subjects"].values.any? { |l| l.key?(k) } || k == "check" }.each do |name|
      assert_not_includes body, "`#{name}`", "#{name} is a ui icon: an agent does not name it"
    end
    diagram = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read)
    diagram["properties"]["type"]["enum"].each { |type| assert_includes body, "`#{type}`", type }
  end

  test "the lesson brief names the error codes of the lesson/2 checks it teaches" do
    body = Brief.find("lesson").body
    codes = body.scan(/\b[EW]-[A-Z]+(?:-[A-Z]+)*\b/).uniq
    Validation::Findings # Validation::Codes lives in findings.rb
    assert_empty codes - Validation::Codes.all.keys - %w[E-STALE-BASE], "codes the registry does not know" # E-STALE-BASE is an API code
    %w[E-LESSON-CARD E-LESSON-CARDS E-CARD-NO-VISUAL E-CARD-WORDS E-CARD-BLOCKS E-CARD-ROLES E-LESSON-BLOCK E-LESSON-CHECKS
       E-LESSON-VISUALS E-LESSON-DIAGRAM E-LESSON-ALT E-LESSON-ROLE E-LESSON-ICON E-LESSON-LINK E-LESSON-MARKUP E-LESSON-MAP].each do |code|
      assert_includes codes, code
    end
  end

  test "the lesson-review brief (version 2) has the 11 points and the 8 of lesson/1, and says to look at the screenshots" do
    body = Brief.find("lesson-review").body
    assert_includes body, "exactly **11 points**"
    assert_includes body, "exactly **8 points**"
    assert_includes body, "look at every card's screenshot at 390 pixels"
    assert_includes body, "11. Free pages"
  end

  test "the practice-item brief states the pool and hint rules of the rules file" do
    body = Brief.find("practice-item").body.squish
    assert_includes body, "at least #{Validation::Rules.get(:practice, :min_static_instances)} instances"
    assert_includes body, "fewer than #{Validation::Rules.get(:practice, :min_instances_per_code)} instances"
    assert_match(/write 3/i, body)
    assert_includes Brief.find("review").body, "12. Hints"
    assert_includes Brief.find("review").body, "13. Messages and solution"
  end
end
