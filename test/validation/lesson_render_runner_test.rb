require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The render check in the server's Chrome (R4, A12.2, D-249): every card drawn at the viewports of lesson2.render,
# the layout findings as errors, the shots stored by content. Needs Chrome (BROWSER_PATH); skips without.
class LessonRenderRunnerTest < ActiveSupport::TestCase
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

  def render(body)
    revision = store_lesson2!(body)
    Validation::LessonRenderCheck.new(revision).call
    LessonRender.where(lesson_revision_id: revision.id).order(:id).last
  end

  # BANCO_SHOT_DIR=/some/dir keeps the shots as files for the eye.
  def keep_shots(row, name)
    return unless ENV["BANCO_SHOT_DIR"]

    FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
    row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "#{name}-#{s['viewport']}-card#{s['card']}.webp"), LessonShots.read(s["sha256"])) }
  end

  def dump(row)
    row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['viewport']}: #{e['message']}" }.join("\n")
  end

  test "a readable lesson passes at every viewport and stores one WebP per core card and viewport" do
    row = render(served("equations"))
    keep_shots(row, "equations")
    assert_equal "passed", row.status, dump(row)
    core = served("equations")["cards"].count { |c| c["level"] == "core" }
    extra = served("equations")["cards"].count { |c| c["level"] == "extra" }
    assert_equal core * 3 + extra, row.shots.size
    row.shots.each do |shot|
      bytes = LessonShots.read(shot["sha256"])
      assert_equal "RIFF", bytes[0, 4]
      assert_equal "WEBP", bytes[8, 4]
    end
    assert_equal row.shots.size, Dir[File.join(@shots_dir, "*.webp")].size + row.shots.size - Dir[File.join(@shots_dir, "*.webp")].size
    assert_equal Validation::Harness.lesson_version, row.harness_version
    assert row.chrome_version.present?
  end

  def codes(row) = row.result["errors"].map { |e| e["code"] }.uniq.sort

  test "a number line too dense for its labels is E-DIAGRAM-LAYOUT" do
    marks = (-5..5).map { |i| { "at" => i.to_s, "kind" => "dot", "role" => "known", "label_it" => "una etichetta davvero molto lunga #{i}" } }
    line = { "type" => "number_line", "alt_it" => "Retta dei numeri da meno cinque a cinque con molte etichette lunghe.", "min" => "-5", "max" => "5", "step" => "1", "labels" => "all", "marks" => marks }
    row = render(with_card(served("equations"), [ { "type" => "diagram", "diagram" => line } ]))
    keep_shots(row, "dense")
    assert_equal "failed", row.status, dump(row)
    assert_includes (codes(row) & %w[E-DIAGRAM-LAYOUT E-DIAGRAM-SMALL-TEXT]), "E-DIAGRAM-LAYOUT", dump(row)
  end

  test "a table wider than the page is E-LESSON-OVERFLOW" do
    wide = "x" * 160
    table = { "type" => "table", "caption_it" => "Una tabella troppo larga", "header" => %w[A B C D], "rows" => [ [ wide, wide, wide, wide ] ] }
    row = render(with_card(served("equations"), [ table ]))
    keep_shots(row, "wide")
    assert_equal "failed", row.status, dump(row)
    assert_includes codes(row), "E-LESSON-OVERFLOW", dump(row)
  end

  test "a formula KaTeX cannot draw is E-LESSON-RENDER, on its card" do
    math = { "type" => "math", "tex" => "\\frac{1}{" }
    row = render(with_card(served("equations"), [ math ]))
    assert_equal "failed", row.status
    error = row.result["errors"].find { |e| e["code"] == "E-LESSON-RENDER" }
    assert error, dump(row)
    assert_equal 14, error["card"]
  end

  test "an unchanged card costs nothing: a second render of the same revision stores (almost) no new file" do
    revision = store_lesson2!(served("sentences"))
    first = Validation::LessonRenderCheck.new(revision).call
    files = Dir[File.join(@shots_dir, "*.webp")].sort
    second = Validation::LessonRenderCheck.new(revision).call
    after = Dir[File.join(@shots_dir, "*.webp")].sort
    shared = first.shots.map { |s| s["sha256"] } & second.shots.map { |s| s["sha256"] }
    assert_operator files.size, :<=, first.shots.size
    # the pictures are named by their content; Chrome's raster may differ by a pixel on an image now and then (a sub-pixel
    # antialiasing of a button), which costs one file, never a lost one
    assert_operator after.size - files.size, :<=, 3, "a second render added #{after.size - files.size} files"
    assert_operator shared.size, :>=, first.shots.size - 3
  end

  test "the revision's time budget ends the check with E-LESSON-RENDER timeout, a verdict and not an error" do
    Validation::Rules.with(lesson2: { render: { budget_seconds: 0 } }) do
      row = render(served("equations"))
      assert_equal "failed", row.status
      assert row.result["errors"].any? { |e| e["code"] == "E-LESSON-RENDER" && e["message"].start_with?("timeout") }, dump(row)
    end
  end

  test "text under the minimum is E-DIAGRAM-SMALL-TEXT (the guard against a style that shrinks a label)" do
    revision = store_lesson2!(served("equations"))
    token = Validation::Harness.issue("lrev", revision.id)
    found = Validation::ChromeRunner.session do |session|
      session.context do |ctx|
        page = ctx.create_page
        page.command("Emulation.setDeviceMetricsOverride", width: 1280, height: 800, deviceScaleFactor: 1, mobile: false)
        page.go_to(Validation::Harness.lesson_page_url(token))
        page.evaluate_async("window.bancoLessonRender.ready.then(arguments[0])", 30)
        page.evaluate("document.head.appendChild(Object.assign(document.createElement('style'), { textContent: '.dg-label { font-size: 12px !important }' })) && 1")
        page.evaluate_async("window.bancoLessonRender.inspect(2).then(arguments[0])", 10)
      end
    end
    assert found["findings"].any? { |f| f["code"] == "E-DIAGRAM-SMALL-TEXT" }, found.inspect
  end

  test "a summary card whose schema and points do not fit one A4 page is E-LESSON-RENDER (Stampa riassunto e schema)" do
    body = served("equations")
    summary = body["cards"].find { |c| c["role"] == "summary" }
    points = summary["blocks"].find { |b| b["type"] == "summary" }
    points["points_it"] = (1..40).map { |i| "Il punto numero #{i} dice una cosa da ricordare, con parole semplici e chiare per chi legge." }
    row = render(body)
    keep_shots(row, "longsummary")
    assert_equal "failed", row.status
    error = row.result["errors"].find { |e| e["where"] == "print" }
    assert error, dump(row)
    assert_equal summary["n"], error["card"]
    assert_match(/Stampa riassunto e schema takes \d+ pages/, error["message"])
  end

  test "the normal summary fits one A4 page" do
    row = render(served("equations"))
    assert_nil row.result["errors"].find { |e| e["where"] == "print" }, dump(row)
  end
end
