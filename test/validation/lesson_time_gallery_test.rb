require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The galleries of the family `time` (WAVE2 5.4, V6): test/fixtures/lesson2/gallery/time.md (years, history) and time-english.md (tense) are
# lesson/2 files with every figure of the family. Each parses with no finding, every diagram passes the Ruby checks of its type, and the server's
# Chrome draws every card at the viewports of lesson2.render with no finding at all (no label under the student's size, none over another, none
# outside its card). BANCO_SHOT_DIR=/some/dir keeps the shots as files for the eye (the look gate).
class LessonTimeGalleryTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  GALLERIES = { "time" => "history", "time-english" => "english" }.freeze

  def parsed(name)
    findings = Validation::Findings.new
    result = Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/#{name}.md").read, findings)
    [ result.body, findings ]
  end

  def diagrams(body) = body["cards"].flat_map { |c| c["blocks"].select { |b| b["type"] == "diagram" }.map { |b| [ c["id"], b["diagram"] ] } }

  test "the galleries parse with no finding and every figure passes the checks of its type" do
    GALLERIES.each do |name, subject|
      body, findings = parsed(name)
      assert_empty findings.errors.map(&:to_h), name
      assert_equal subject, body["subject"]
      shown = diagrams(body)
      assert_equal [ "timeline" ], shown.map { |_, d| d["type"] }.uniq
      shown.each { |id, d| assert_empty Lessons::Diagrams.check(d, subject: subject).map(&:to_h), "#{name} #{id}" }
    end
    assert_equal %w[years], diagrams(parsed("time").first).map { |_, d| d["scale"] }.uniq
    assert_equal %w[tense], diagrams(parsed("time-english").first).map { |_, d| d["scale"] }.uniq
    assert_equal 5, diagrams(parsed("time").first).size
    assert_equal 2, diagrams(parsed("time-english").first).size
  end

  GALLERIES.each_key do |name|
    test "Chrome draws every card of #{name} at every viewport with no finding" do
      require_chrome!
      shots = Dir.mktmpdir("lesson-shots")
      ENV["BANCO_LESSON_SHOTS_DIR"] = shots
      body, = parsed(name)
      revision = store_lesson2!(body)
      Validation::LessonRenderCheck.new(revision).call
      row = LessonRender.where(lesson_revision_id: revision.id).order(:id).last
      if ENV["BANCO_SHOT_DIR"]
        FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
        row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "render-#{name}-#{s['viewport']}-card#{s['card']}.webp"), LessonShots.read(s["sha256"])) }
      end
      assert_equal "passed", row.status, row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['viewport']}: #{e['message']}" }.join("\n")
    ensure
      ENV.delete("BANCO_LESSON_SHOTS_DIR")
      FileUtils.rm_rf(shots) if shots
    end
  end
end
