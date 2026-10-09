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
end
