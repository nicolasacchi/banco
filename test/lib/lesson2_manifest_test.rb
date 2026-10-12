require "test_helper"

# R0: the lesson/2 fixtures are consistent. R1 adds the test that runs each bad file through the
# real parser and compares code and line with this manifest.
class Lesson2ManifestTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lesson2")
  MANIFEST = JSON.parse(DIR.join("manifest.json").read)

  test "every bad file is listed once, and every listed file exists" do
    listed = MANIFEST["bad"].map { |b| b["file"] }
    assert_equal listed.uniq, listed
    on_disk = Dir.children(DIR.join("bad")).map { |f| "bad/#{f}" }.sort
    assert_equal on_disk, listed.compact.sort
  end

  test "every entry has a registered code, a base that exists, and an integer or null line" do
    codes = YAML.safe_load_file(Rails.root.join("config/banco/error_codes.yml")).to_s
    MANIFEST["bad"].each do |b|
      assert_match(/\A[EW]-[A-Z0-9-]+\z/, b["code"], b["file"])
      assert_includes codes, b["code"], "#{b['file']}: code not in the registry"
      assert(b["base"].start_with?("(") || DIR.join(b["base"]).file?, "#{b['file']}: base missing")
      assert(b["line"].nil? || b["line"].is_a?(Integer), b["file"])
    end
  end

  # Rules version 9 (WAVE2 V5): the new codes each have a bad fixture, written by their track; until then the manifest describes it.
  test "every code added by wave 2 has a bad fixture or a pending description with the track that writes it" do
    registry = YAML.safe_load_file(Rails.root.join("config/banco/error_codes.yml")).fetch("validation")
    wave2 = %w[E-LESSON-DATA E-LESSON-VERIFY E-CHECK-ANSWER-IN-ALT W-CHECK-ANSWER-IN-DIAGRAM E-CHECK-ANSWER-BY-SIMULATION E-DIAGRAM-REACHABLE-CAP E-SELECT-MARKED
               E-DIAGRAM-TARGET W-TYPE-RESERVED W-TYPE-DRAFT E-PROGRAM-BOUND E-LESSON-APPARATUS-WORDS E-CHEM-SYMBOL W-ES-TILDE E-LESSON-LANG W-LANG-LEVEL]
    pending = MANIFEST.dig("pending", "entries")
    wave2.each { |code| assert registry.key?(code), "#{code} is in the registry" }
    assert_equal wave2.sort, (pending.map { |e| e["code"] } + MANIFEST["bad"].map { |b| b["code"] }).uniq.select { |c| wave2.include?(c) }.sort
    pending.each do |e|
      assert_match(/\AT\d+[ab]?\z/, e["track"], e["code"])
      assert e["change"].present?, e["code"]
      assert_nil MANIFEST["bad"].find { |b| b["code"] == e["code"] }, "#{e['code']} has its fixture: remove the pending entry"
    end
    assert_operator YAML.safe_load_file(Rails.root.join("config/banco/error_codes.yml"))["version"], :>=, 20
  end

  # The pending list must not outlive the pieces it waits for: when every registry name an entry needs is available, its bad fixture
  # is writable and the entry has to move to `bad`.
  test "a code stays pending only while a piece it needs is not available" do
    pending = MANIFEST.dig("pending", "entries")
    pending.each do |e|
      needs = e["needs"]
      assert_kind_of Array, needs, "#{e['code']}: needs lists the registry names of the pieces its fixture waits for"
      if needs.empty?
        assert e["standing"].present?, "#{e['code']}: no needs and no `standing` reason"
        next
      end
      statuses = needs.map do |n|
        kind, name = n.split(":", 2)
        status = kind == "option" ? Lessons::Types.data.fetch("check_options")[name]&.fetch("status") : Lessons::Types.status(kind.to_sym, name)
        assert status, "#{e['code']}: #{n} is not in lesson_types.yml"
        status
      end
      assert_not statuses.all?("available"), "#{e['code']} is still pending but #{needs.join(', ')} is available: write its bad fixture and move it to `bad`"
    end
  end
end
