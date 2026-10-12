require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"
require_relative "../support/lesson2_fixtures"

# V6 for the docs family (T8): the gallery lesson passes the render check in the server's Chrome with no finding at all, at every viewport of
# lesson2.render (390 and 1280, cream and dark): every figure inside its width, no text under the base size, no label over another. Needs Chrome.
class DocsRenderTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  setup do
    require_chrome!
    @shots_dir = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = @shots_dir
  end

  teardown do
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(@shots_dir)
  end

  test "the gallery lesson of the docs family passes the render check with no finding" do
    body = Lesson2Fixtures.check(Lesson2Fixtures::DIR.join("gallery/docs-lesson.md").read, "business").body
    revision = store_lesson2!(body)
    Validation::LessonRenderCheck.new(revision).call
    row = LessonRender.where(lesson_revision_id: revision.id).order(:id).last
    errors = row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['viewport']}: #{e['message']}" }
    assert_equal "passed", row.status, errors.join("\n")
    assert_empty errors
    assert_empty Array(row.result["warnings"]).map(&:to_s)
  end
end
