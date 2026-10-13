require "test_helper"
require_relative "../support/page_world"
require_relative "../support/lesson2_fixtures"

# The page block against the server's pages (D-289, SPEC B4): the pin must exist, belong to the lesson's subject and have passed
# validation; `latest` is stored as an integer; the student's body carries the view, never the code.
class PagesLessonTest < ActiveSupport::TestCase
  include PageWorld
  F = Lesson2Fixtures

  setup do
    @subject = page_subject!
    @store = Dir.mktmpdir
    ENV["BANCO_PAGES_DIR"] = @store
    ENV["BANCO_PAGE_SHOTS_DIR"] = Dir.mktmpdir
    @revision = store_page!
  end

  teardown do
    ENV.delete("BANCO_PAGES_DIR")
    FileUtils.rm_rf(ENV.delete("BANCO_PAGE_SHOTS_DIR").to_s)
    FileUtils.rm_rf(@store)
  end

  def context
    c = F::CONTEXT.fetch("math")
    skills = c["skills"].to_h { |k| [ k, { "key" => k, "errors" => c["error_codes"].map { |code| { "code" => code } } } ] }
    lines = c["source_lines"].to_h { |l| [ [ l["source"], l["line"] ], l["text"] ] }
    Validation::Context.new(subject: "math", skill: ->(k) { skills[k] }, source_line: ->(s, n) { (t = lines[[ s, n ]]) && { text: t, origin: "pdf" } },
                            topic: ->(k) { c["topics"].include?(k) }, page: ->(key, rev) { Pages::Embed.lookup(@subject, key, rev) })
  end

  def lesson(revision: "latest", key: "math.pages-sample")
    md = F.read("good/page-extra-card.md")
    md = md.sub("page: math.pages-sample\nrevision: latest", "page: #{key}\nrevision: #{revision}")
    Validation::LessonChecks.call(md, subject: "math", context: context)
  end

  def messages(outcome, code = "E-LESSON-FREEPAGE") = outcome.findings.select { |f| f.code == code }.map(&:message)

  test "a page that exists but has not been validated cannot be embedded" do
    assert_match(/has not been validated yet/, messages(lesson).first)
    PageValidation.create!(page_revision: @revision, kit_version: "1.0", status: "failed", harness_version: "t", result_json: JSON.generate("errors" => [ { "code" => "E-PAGE-READY" } ]), shots_json: "[]")
    assert_match(/did not pass validation/, messages(lesson).first)
  end

  test "a validated page is embedded; latest is stored as the revision's integer" do
    pass_page!(@revision)
    outcome = lesson
    assert_empty messages(outcome)
    assert_not outcome.findings.any_error?, outcome.findings.errors.map(&:message).inspect
    block = outcome.body["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "page" }
    assert_equal @revision.id, block["revision"]
    assert_equal @revision.id, lesson(revision: @revision.id).body["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "page" }["revision"]
  end

  test "an unknown page, a page of another subject and an unknown revision are refused" do
    pass_page!(@revision)
    assert_match(/no page math.nope/, messages(lesson(key: "math.nope")).first)
    assert_match(/has no revision 99999/, messages(lesson(revision: 99_999)).first)
    english = Subject.find_by(key: "english") || Subject.create!(key: "english", name_it: "Inglese", position: 2)
    other = Page.create!(key: "english.elsewhere", subject: english)
    PageRevision.create!(page: other, seq: 1, manifest_json: "{}", bundle_sha256: "f" * 64, rules_version: "9", warnings_json: "[]")
    assert_match(/belongs to english, not to math/, messages(lesson(key: "english.elsewhere")).first)
  end

  test "a string of the page equal to a final of the lesson's exercises is W-PAGE-KEY" do
    pass_page!(@revision)
    files = page_files { |f| f["maths.mjs"] += "\nexport const secret = '$x = \\frac{7}{3}$'\n" }
    rev = store_page!(files)
    pass_page!(rev)
    md = F.read("good/page-extra-card.md").sub("revision: latest", "revision: #{rev.id}")
    outcome = Validation::LessonChecks.call(md, subject: "math", context: context)
    assert(outcome.findings.any? { |f| f.code == "W-PAGE-KEY" }, outcome.findings.map(&:code).inspect)
  end

  test "a caption that repeats the page's instructions is W-PAGE-REPEAT, a different one is not" do
    pass_page!(@revision)
    md = F.read("good/page-extra-card.md")
    outcome = Validation::LessonChecks.call(md, subject: "math", context: context)
    assert(outcome.findings.any? { |f| f.code == "W-PAGE-REPEAT" }, outcome.findings.map(&:code).inspect)
    other = md.sub(/caption_it: ".*"/, 'caption_it: "Il punto in cui si incrociano le strade."')
    outcome = Validation::LessonChecks.call(other, subject: "math", context: context)
    assert_not(outcome.findings.any? { |f| f.code == "W-PAGE-REPEAT" }, outcome.findings.map(&:code).inspect)
  end

  test "the student's body carries the view of the page, never its code; the poster only when it exists" do
    shot = PageShots.put("RIFF1234WEBPdata")
    pass_page!(@revision, shots: [ { "kind" => "ready", "seed_index" => 0, "width" => 1280, "height" => 300, "sha256" => shot, "bytes" => 16 } ])
    lr = lesson_revision_with(@revision)
    with_env("BANCO_PAGES_ENABLED" => "1") do
      served = Lessons::StudentBody.for(lr, seed: "student-1")
      block = served["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "page" }
      assert_equal %w[n type page revision caption_it view].sort, block.keys.sort
      view = block["view"]
      assert_equal "/page-posters/#{shot}", view["poster"]
      assert_equal Pages.shell_url(@revision.bundle_sha256, "1.0"), view["src"]
      assert_equal Pages.origin, view["frame_origin"]
      assert_equal Pages.seed_for("student-1", "math.pages-sample"), view["seed"]
      assert_equal Pages.teacher_seed, Lessons::StudentBody.for(lr, seed: "preview")["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "page" }["view"]["seed"]
      assert_operator view["transfer_kb"], :>=, 40
      assert_no_match(/main\.mjs|maths|createElement/, JSON.generate(served))
    end
    with_env("BANCO_PAGES_ENABLED" => "0") do
      view = Lessons::StudentBody.for(lr, seed: "student-1")["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "page" }["view"]
      assert_nil view["src"], "switched off: the card shows poster, caption and fallback without the button"
      assert_equal "Muovi il cursore e guarda dove le due rette si incontrano.", view["instructions_it"]
    end
  end

  test "the seed of a student for a page is one of the eight, stable, and spread" do
    seeds = (1..200).map { |i| Pages.seed_for("student-#{i}", "math.pages-sample") }
    assert_equal Pages::SEEDS.sort, seeds.uniq.sort
    assert_equal Pages.seed_for("a", "k"), Pages.seed_for("a", "k")
    assert_equal 8, Pages::SEEDS.uniq.size
  end

  def lesson_revision_with(page_revision)
    outcome = lesson(revision: page_revision.id)
    body = outcome.body
    lesson = Lesson.create!(subject: @subject, key: body["key"], kind: "ripasso")
    LessonRevision.create!(lesson: lesson, seq: 1, source_md: "x", source_sha256: "a" * 64, body_json: JSON.generate(body), rules_version: "9", warnings_json: "[]")
  end
end
