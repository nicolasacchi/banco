require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The gallery of the biology figures (test/fixtures/lesson2/gallery/science-biology.md: `cell` and `nested`, D-312) drawn by the render check in the
# server's Chrome (WAVE2 V6): every card at every viewport with no finding, one WebP per core card and viewport. BANCO_SHOT_DIR=/some/dir keeps the shots
# as files for the look gate. The Ruby checks run without Chrome; the render check needs it (BROWSER_PATH) and skips without.
class BiologyGalleryTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  GALLERY = Rails.root.join("test/fixtures/lesson2/gallery/science-biology.md")

  def body
    @body ||= Lessons::Parser2.call(GALLERY.read, Validation::Findings.new, allow_reserved: true).body
  end

  def diagrams
    list = []
    walk = ->(n) { n.is_a?(Hash) ? ((list << n) if n["type"] && n["alt_it"]; n.each_value(&walk)) : (n.each(&walk) if n.is_a?(Array)) }
    walk.call(body)
    list
  end

  test "the gallery parses with nothing held back, and every figure is clean for the Ruby checks" do
    findings = Validation::Findings.new
    Lessons::Parser2.call(GALLERY.read, findings)
    assert_empty findings.map { |f| "#{f.code} #{f.field}: #{f.message}" }, "cell and nested are available: no reserved dry run is needed"
    assert_equal %w[cell nested], diagrams.map { |d| d["type"] }.uniq.sort
    diagrams.each { |d| assert_empty Lessons::Diagrams.check(d, subject: "biology").map(&:message), d["alt_it"] }
  end

  test "the select checks of the gallery are clean: targets, answers, the alt text that names nothing, the candidates alike" do
    checks = body["cards"].flat_map { |c| c["blocks"].select { |b| b["type"] == "check" && b["component"] == "select" } }
    assert_equal 4, checks.size
    checks.each do |check|
      findings = Validation::Findings.new
      ctx = Lessons::Blocks::Context.new(subject: "biology", findings: findings)
      ctx.at("/cards/1/blocks/0", 1) { Lessons::Blocks::Check.check(check, ctx) }
      assert_empty findings.map { |f| "#{f.code} #{f.field}: #{f.message}" }, check["prompt_it"]
    end
    assert_equal "c1.nucleoid", Lessons::SelectTargets.id_map(checks[0])["t4"]
    assert_equal %w[c1.wall c1.membrane c1.cytoplasm c1.nucleoid c1.ribosomes c2.membrane c2.cytoplasm c2.nucleus c2.ribosomes c2.mitochondria],
                 Lessons::SelectTargets.id_map(checks[2]).values, "two cells: the first one's parts, then the second's"
  end

  test "the gallery passes the render check at every viewport and its shots can be kept for the eye" do
    require_chrome!
    shots_dir = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = shots_dir
    revision = store_lesson2!(body, key: "ripasso.biology.gallery-science")
    Validation::LessonRenderCheck.new(revision).call
    row = LessonRender.where(lesson_revision_id: revision.id).order(:id).last
    assert_equal "passed", row.status, row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['viewport']}: #{e['message']}" }.join("\n")
    if ENV["BANCO_SHOT_DIR"]
      FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
      row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "biology-#{s['viewport']}-card#{s['card']}.webp"), LessonShots.read(s["sha256"])) }
    end
    assert_operator row.shots.size, :>=, 4 * 3
  ensure
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(shots_dir) if shots_dir
  end
end
