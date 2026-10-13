require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The gallery of the family science (test/fixtures/lesson2/gallery/science.md) drawn by the render check in the server's Chrome (WAVE2 V6):
# every card at every viewport with no finding, one WebP per core card and viewport. BANCO_SHOT_DIR=/some/dir keeps the shots as files for the
# look gate. Needs Chrome (BROWSER_PATH); skips without.
class ScienceGalleryTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  GALLERY = Rails.root.join("test/fixtures/lesson2/gallery/science.md")

  setup do
    require_chrome!
    @shots_dir = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = @shots_dir
  end

  teardown do
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(@shots_dir)
  end

  def body
    @body ||= Lessons::Parser2.call(GALLERY.read, Validation::Findings.new, allow_reserved: true).body
  end

  test "every diagram of the gallery is clean for the Ruby checks" do
    diagrams = []
    walk = ->(n) { n.is_a?(Hash) ? ((diagrams << n) if n["type"] && n["alt_it"]; n.each_value(&walk)) : (n.each(&walk) if n.is_a?(Array)) }
    walk.call(body)
    assert_equal %w[formula molecule periodic_table strand], diagrams.map { |d| d["type"] }.uniq.sort
    diagrams.each { |d| assert_empty Lessons::Diagrams.check(d, subject: "chemistry").map(&:message), d["alt_it"] }
  end

  test "the gallery passes the render check at every viewport and its shots can be kept for the eye" do
    revision = store_lesson2!(body, key: "ripasso.chemistry.gallery-science")
    Validation::LessonRenderCheck.new(revision).call
    row = LessonRender.where(lesson_revision_id: revision.id).order(:id).last
    assert_equal "passed", row.status, row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['viewport']}: #{e['message']}" }.join("\n")
    if ENV["BANCO_SHOT_DIR"]
      FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
      row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "science-#{s['viewport']}-card#{s['card']}.webp"), LessonShots.read(s["sha256"])) }
    end
    assert_operator row.shots.size, :>=, 4 * 3
  end
end
