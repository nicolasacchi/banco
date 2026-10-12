require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The gallery of the family `words` (WAVE2 5.4, V6): test/fixtures/lesson2/gallery/words.md (spanish) and words-english.md are lesson/2 files with
# every figure and block of the family. They parse with no finding, every diagram passes the Ruby checks of its type, and the server's Chrome draws
# every card at the viewports of lesson2.render with no finding at all (no label under the student's size, none over another, none outside its
# card). BANCO_SHOT_DIR=/some/dir keeps the shots as files for the eye (the look gate).
class LessonWordsGalleryTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  FILES = { "words" => "spanish", "words-english" => "english" }.freeze

  def parsed(name)
    findings = Validation::Findings.new
    result = Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/#{name}.md").read, findings)
    [ result.body, findings ]
  end

  def diagrams(body) = body["cards"].flat_map { |c| c["blocks"].select { |b| b["type"] == "diagram" }.map { |b| [ c["id"], b["diagram"] ] } }

  test "the galleries parse with no finding and every figure passes the checks of its type" do
    shown = []
    FILES.each do |name, subject|
      body, findings = parsed(name)
      assert_empty findings.errors.map(&:to_h), name
      assert_equal subject, body["subject"]
      diagrams(body).each do |id, d|
        assert_empty Lessons::Diagrams.check(d, subject: subject).map(&:to_h), "#{name} #{id}"
        shown << d
      end
      body["cards"].flat_map { |c| c["blocks"] }.select { |b| b["type"] == "dialogue" }.each do |b|
        ctx = Lessons::Blocks::Context.new(subject: subject, findings: Validation::Findings.new)
        Lessons::Blocks::Dialogue.check(b, ctx)
        assert_empty ctx.findings.errors.map(&:to_h), "#{name} dialogue"
      end
    end
    assert_equal %w[mirror word_parts], shown.map { |d| d["type"] }.uniq.sort
    assert_equal %w[decode syllables], shown.select { |d| d["type"] == "word_parts" }.map { |d| d["view"] }.uniq.sort
    assert_equal 2, FILES.keys.sum { |n| parsed(n).first["cards"].sum { |c| c["blocks"].count { |b| b["type"] == "dialogue" } } }
  end

  FILES.each_key do |name|
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
        row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "#{name}-#{s['viewport']}-card#{s['card']}.webp"), LessonShots.read(s["sha256"])) }
      end
      assert_equal "passed", row.status, row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['viewport']}: #{e['message']}" }.join("\n")
    ensure
      ENV.delete("BANCO_LESSON_SHOTS_DIR")
      FileUtils.rm_rf(shots) if shots
    end
  end
end
