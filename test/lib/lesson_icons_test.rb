require "test_helper"
require "open3"

# D-246: config/banco/icons.yml maps our icon names to the vendored Lucide files; bin/build-icons makes
# the sprite. An agent names our icons only (E-LESSON-ICON).
class LessonIconsTest < ActiveSupport::TestCase
  ICONS = YAML.safe_load_file(Rails.root.join("config/banco/icons.yml"))
  DIR = Rails.root.join("public/vendor/lucide@#{ICONS['lucide']}")
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

  test "the subjects with icons are the eleven of the palette, and the ui list is not the agent's" do
    assert_equal %w[biology business chemistry computer_science english geography history italian law_economics math spanish], ICONS["subjects"].keys.sort
    assert_equal Lessons::Palette.subjects.sort, ICONS["subjects"].keys.sort
    assert_operator ICONS["ui"].size, :>, 10
  end

  test "every sprite has exactly one symbol per icon of its list, no script, no external reference" do
    lists = { "banco-sprite.svg" => ICONS["structural"].merge(ICONS["ui"]) }
    ICONS["subjects"].each { |subject, list| lists["banco-sprite-#{subject}.svg"] = list }
    assert_equal lists.keys.sort, Dir.children(DIR).grep(/\Abanco-sprite.*\.svg\z/).sort
    lists.each do |file, list|
      sprite = DIR.join(file).read
      assert_equal list.keys.sort, sprite.scan(/<symbol id="([^"]+)"/).flatten.sort, file
      assert_no_match(/<script|onload|onclick|href=|xlink:|<image|<foreignObject/i, sprite, file)
      assert_operator sprite.bytesize, :<, 60_000, file
    end
  end

  test "the browser finds the sprite of every icon through palette.js" do
    palette = JSON.parse(Rails.root.join("app/javascript/lesson/palette.js").read[/export default (.*)\n/, 1])
    sprites = palette.dig("icons", "sprites")
    every_entry.each_key { |name| assert sprites.key?(name), name }
    assert_equal "banco-sprite.svg", sprites["lightbulb"]
    assert_equal "banco-sprite-math.svg", sprites["brackets"]
    assert_equal "banco-sprite-biology.svg", sprites["dna"]
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
