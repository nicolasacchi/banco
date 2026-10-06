require "test_helper"

# C-03: the authoring briefs are versioned files in git.
class BriefTest < ActiveSupport::TestCase
  NAMES = %w[blueprint diagnosis-item grade review skill-graph solve].freeze

  test "the six briefs exist at version 1 with a body" do
    assert_equal NAMES, Brief.names
    NAMES.each do |name|
      brief = Brief.find(name)
      assert_equal 1, brief.version, name
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
end
