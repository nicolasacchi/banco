require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"

# The render check of a bilingual lesson (D-402): the golden lesson of test/fixtures/lang, folded by the server, drawn in the server's Chrome. Every card has its
# state `tr` (the translation open: pictured at the phone, measured at every viewport), the exercise states have `exN-tr`, and a lesson whose target texts all
# have their Italian has no «translation missing». Needs Chrome (BROWSER_PATH); skips without.
class LessonRenderTranslationTest < ActiveSupport::TestCase
  include ChromeHelper

  PHONE = "390x844-cream"

  setup do
    require_chrome!
    @shots_dir = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = @shots_dir
  end

  teardown do
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(@shots_dir)
  end

  def render_golden
    body = JSON.parse(Rails.root.join("test/fixtures/lang/projected_lesson.json").read).merge("bilingual" => true)
    subject = Subject.find_by(key: "english") || Subject.create!(key: "english", name_it: "Inglese", position: 2)
    lesson = Lesson.create!(subject: subject, key: body["key"], kind: "lezione")
    md = "---\nkey: #{body['key']}\n---\n"
    revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(body),
                                      rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
    Validation::LessonRenderCheck.new(revision).call
    LessonRender.where(lesson_revision_id: revision.id).order(:id).last
  end

  def dump(row) = row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['state'] || '-'} #{e['viewport']} #{e['where']}: #{e['message']}" }.join("\n")

  test "the golden bilingual lesson draws: no «translation missing», and each card with a translation has its `tr` picture at the phone" do
    row = render_golden
    assert_equal "passed", row.status, dump(row)
    assert_empty row.result["errors"].select { |e| e["message"].to_s.start_with?("translation") }, dump(row)
    pictured = row.shots.select { |s| s["state"] == "tr" }
    assert_equal [ 1, 2 ], pictured.map { |s| s["card"] }.sort, "the cards with a translation"
    assert(pictured.all? { |s| s["viewport"] == PHONE }, "pictured at the phone only")
  end
end
