require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The gallery of the family `graph` (WAVE2 5.4, V6): test/fixtures/lesson2/gallery/graph.md is a lesson/2 file with every figure of the
# family. It parses with no finding, every diagram passes the Ruby checks of its type, and the server's Chrome draws every card at the
# viewports of lesson2.render with no finding at all (no label under the student's size, none over another, none outside its card).
# BANCO_SHOT_DIR=/some/dir keeps the shots as files for the eye (the look gate).
class LessonGraphGalleryTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  FILE = Rails.root.join("test/fixtures/lesson2/gallery/graph.md")

  def parsed
    findings = Validation::Findings.new
    result = Lessons::Parser2.call(FILE.read, findings)
    [ result.body, findings ]
  end

  def diagrams(body) = body["cards"].flat_map { |c| c["blocks"].select { |b| b["type"] == "diagram" }.map { |b| [ c["id"], b["diagram"] ] } }

  test "the gallery parses with no finding and every figure passes the checks of its type" do
    body, findings = parsed
    assert_empty findings.errors.map(&:to_h)
    assert_equal "law_economics", body["subject"]
    shown = diagrams(body)
    assert_equal %w[chain flow nested network], shown.map { |_, d| d["type"] }.uniq.sort
    assert_equal %w[fan grid hub pair row triangle], shown.select { |_, d| d["type"] == "network" }.map { |_, d| d["layout"] }.uniq.sort
    assert_equal %w[fan line ring], shown.select { |_, d| d["type"] == "chain" }.map { |_, d| d["layout"] }.uniq.sort
    assert_equal [ "line" ], shown.select { |_, d| d["type"] == "flow" }.map { |_, d| d["layout"] }.uniq
    shown.each { |id, d| assert_empty Lessons::Diagrams.check(d, subject: "law_economics").map(&:to_h), id }
    assert_equal 14, shown.size
  end

  test "Chrome draws every card at every viewport with no finding" do
    require_chrome!
    shots = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = shots
    body, = parsed
    revision = store_lesson2!(body)
    Validation::LessonRenderCheck.new(revision).call
    row = LessonRender.where(lesson_revision_id: revision.id).order(:id).last
    if ENV["BANCO_SHOT_DIR"]
      FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
      row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "graph-#{s['viewport']}-card#{s['card']}.webp"), LessonShots.read(s["sha256"])) }
    end
    assert_equal "passed", row.status, row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['viewport']}: #{e['message']}" }.join("\n")
  ensure
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(shots) if shots
  end
end
