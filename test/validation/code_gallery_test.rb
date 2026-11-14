require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The gallery of the `code` block (test/fixtures/lesson2/gallery/code.md, D-329) drawn by the render check in the server's Chrome: every card at every
# viewport (390 px cream, 1280 px cream and dark) with no finding at all, so no card is wider than its window although a program has a line of 90
# characters (it scrolls inside its box), and one WebP per core card and viewport. BANCO_SHOT_DIR=/some/dir keeps the shots as files for the eye.
# Needs Chrome (BROWSER_PATH); skips without.
class CodeGalleryTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  GALLERY = Rails.root.join("test/fixtures/lesson2/gallery/code.md")

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
    @body ||= Lessons::Parser2.call(GALLERY.read, Validation::Findings.new).body
  end

  test "the gallery passes the render check at every viewport, among them the phone, and its shots can be kept for the eye" do
    revision = store_lesson2!(body, key: "ripasso.computer_science.gallery-code")
    Validation::LessonRenderCheck.new(revision).call
    row = LessonRender.where(lesson_revision_id: revision.id).order(:id).last
    assert_equal "passed", row.status, row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['viewport']}: #{e['message']}" }.join("\n")
    if ENV["BANCO_SHOT_DIR"]
      FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
      row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "code-#{s['viewport']}-card#{s['card']}.webp"), LessonShots.read(s["sha256"])) }
    end
    phone = row.shots.select { |s| s["viewport"] == "390x844-cream" && s["level"] == "core" }
    assert_equal body["cards"].size, phone.size, "a picture of every card at 390 px"
  end
end
