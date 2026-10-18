require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The renderer problems the authors reported in wave 3 (D-310): test/fixtures/lesson2/gallery/polish-spanish.md and polish-math.md hold one
# card per problem. They parse with no finding, and the server's Chrome draws every card at the viewports of lesson2.render with no finding
# at all: no markup printed as text, no mirror text crossing its box, no overflow, no KaTeX error. BANCO_SHOT_DIR=/some/dir keeps the shots.
class LessonPolishGalleryTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  FILES = { "polish-spanish" => "spanish", "polish-math" => "math" }.freeze

  def parsed(name)
    findings = Validation::Findings.new
    result = Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/#{name}.md").read, findings)
    [ result.body, findings ]
  end

  def blocks(body) = body["cards"].flat_map { |c| c["blocks"] }

  test "the galleries parse with no finding, and every figure passes the checks of its type" do
    FILES.each do |name, subject|
      body, findings = parsed(name)
      assert_empty findings.errors.map(&:to_h), name
      assert_equal subject, body["subject"]
      blocks(body).select { |b| %w[diagram schema].include?(b["type"]) }.each do |b|
        assert_empty Lessons::Diagrams.check(b["diagram"] || b["schema"], subject: subject).map(&:to_h), "#{name} #{b['type']}"
      end
    end
  end

  test "a math block written in YAML quotes keeps only the formula" do
    body, = parsed("polish-math")
    assert_equal [ '(a^2)^3 = a^{2 \cdot 3} = a^6', "a^7 : a^3 = a^{7 - 3} = a^4" ], blocks(body).select { |b| b["type"] == "math" }.map { |b| b["tex"] }
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
