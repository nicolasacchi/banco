require "test_helper"
require "open3"

# D-246: config/banco/icons.yml maps our icon names to the vendored Lucide files; bin/build-icons makes
# the sprite. An agent names our icons only (E-LESSON-ICON).
class LessonIconsTest < ActiveSupport::TestCase
  ICONS = YAML.safe_load_file(Rails.root.join("config/banco/icons.yml"))
  DIR = Rails.root.join("public/vendor/lucide@#{ICONS['lucide']}")
  SPRITE = DIR.join("banco-sprite.svg").read
  NAME = /\A[a-z][a-z0-9]*(-[a-z0-9]+)*\z/

  def every_entry
    ICONS["structural"].merge(ICONS["ui"]).merge(*ICONS["subjects"].values)
  end

  test "the version in icons.yml is the vendored directory, with its licence" do
    assert DIR.directory?
    assert_includes DIR.join("LICENSE").read, "ISC License"
    assert_equal "1.54.0", ICONS["lucide"]
  end

  test "every name is ours (lowercase, hyphens), every target is a vendored file, a subject has at most thirty" do
    [ ICONS["structural"], ICONS["ui"], *ICONS["subjects"].values ].each do |list|
      list.each do |ours, lucide|
        assert_match NAME, ours
        assert DIR.join("icons/#{lucide}.svg").file?, "#{ours} -> #{lucide}.svg is not vendored"
      end
    end
    ICONS["subjects"].each { |subject, list| assert_operator list.size, :<=, 30, subject }
  end

  test "an icon name means one thing: a name in two lists points at the same file" do
    pairs = [ ICONS["structural"], ICONS["ui"], *ICONS["subjects"].values ].flat_map(&:to_a)
    pairs.group_by(&:first).each { |ours, group| assert_equal 1, group.map(&:last).uniq.size, "#{ours} points at two files" }
  end

  test "the subjects with icons are the two of release 1, and the ui list is not the agent's" do
    assert_equal %w[italian math], ICONS["subjects"].keys.sort
    assert_operator ICONS["ui"].size, :>, 10
  end

  test "the sprite has exactly one symbol per icon, no script, no external reference" do
    ids = SPRITE.scan(/<symbol id="([^"]+)"/).flatten
    assert_equal every_entry.keys.sort, ids.sort
    assert_no_match(/<script|onload|onclick|href=|xlink:|<image|<foreignObject/i, SPRITE)
    assert_operator SPRITE.bytesize, :<, 60_000
  end

  test "bin/build-icons --check says the committed sprite and SHA256SUMS equal the build" do
    out, status = Open3.capture2e(Rails.root.join("bin/build-icons").to_s, "--check")
    assert status.success?, out
  end

  test "the icons the fixtures name exist for their subject" do
    {
      "demo.md" => "math", "base.md" => "math", "demo-italian.md" => "italian"
    }.each do |file, subject|
      allowed = ICONS["structural"].keys + ICONS["subjects"].fetch(subject).keys
      names = Rails.root.join("test/fixtures/lesson2/#{file}").read.scan(/\bicon[=:] ?([a-z0-9-]+)/).flatten
      assert_empty names - allowed, file
    end
  end
end
