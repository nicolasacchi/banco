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
    body = JSON.parse(Rails.root.join("test/fixtures/lang/projected_lesson.json").read).merge("bilingual" => true, "schema" => "banco.lesson/2")
    subject = Subject.find_by(key: "english") || Subject.create!(key: "english", name_it: "Inglese", position: 2)
    lesson = Lesson.create!(subject: subject, key: body["key"], kind: "lezione")
    md = "---\nkey: #{body['key']}\n---\n"
    revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(body),
                                      rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
    Validation::LessonRenderCheck.new(revision).call
    LessonRender.where(lesson_revision_id: revision.id).order(:id).last
  end

  # A bilingual lesson written as the author does (test/fixtures/lang/lesson_<lang>_figures.md, the figures of the pilot lessons), parsed and rendered.
  def render_figures(lang, file = "lesson_#{lang}_figures.md", md: nil)
    key = { "en" => "english", "es" => "spanish" }.fetch(lang)
    md ||= Rails.root.join("test/fixtures/lang/#{file}").read
    body = Lessons::Parser2.call(md, Validation::Findings.new).body
    subject = Subject.find_by(key: key) || Subject.create!(key: key, name_it: key.capitalize, position: 2)
    lesson = Lesson.create!(subject: subject, key: body["key"], kind: "lezione")
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
    assert_equal [ 0, 1, 2 ], pictured.map { |s| s["card"] }.sort, "the cover (title, goals, why) and the cards with a translation"
    assert(pictured.all? { |s| s["viewport"] == PHONE }, "pictured at the phone only")
  end

  %w[es en].each do |lang|
    test "the pilot figures of a #{lang} lesson (sentence and word_parts with states, mirror, flow, table, legend, select, input fragments) have no «translation missing»" do
      row = render_figures(lang)
      if ENV["BANCO_SHOT_DIR"] # keeps the pictures for the eye
        FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
        row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "#{lang}-#{s['viewport']}-card#{s['card']}#{"-#{s['state']}" if s['state']}.webp"), LessonShots.read(s["sha256"])) }
      end
      assert_empty row.result["errors"].select { |e| e["message"].to_s.start_with?("translation") }, dump(row)
      assert_equal "passed", row.status, dump(row)
    end
  end

  test "a `more` box of a bilingual lesson shows its translation: the title, the text and the callout inside have their Italian (no «translation missing»)" do
    row = render_figures("en", "lesson_en_more.md")
    assert_empty row.result["errors"].select { |e| e["message"].to_s.start_with?("translation") }, dump(row)
    assert_equal "passed", row.status, dump(row)
  end

  test "a decode word_parts whose pieces and meaning have only their Italian gloss (parts_it, meaning_it) draws: the gloss is Italian text, no «en text with no Italian translation» (round 6)" do
    row = render_figures("en", "lesson_en_decode.md")
    assert_empty row.result["errors"].select { |e| e["message"].to_s.start_with?("translation") }, dump(row)
    assert_equal "passed", row.status, dump(row)
  end

  test "a concept_map of verb forms (translate_material: false) draws its nodes in English with no Italian: no «translation missing» (round 6)" do
    row = render_figures("en", "lesson_en_concept_map.md")
    assert_empty row.result["errors"].select { |e| e["message"].to_s.start_with?("translation") }, dump(row)
    assert_equal "passed", row.status, dump(row)
  end

  test "a decode word_parts with parts_it and no meaning_it (the brief allows it) draws in Spanish with its Italian gloss alone: the layout and the translation scan agree with the dry run (round 7)" do
    row = render_figures("es", "lesson_es_decode.md")
    assert_empty row.result["errors"].select { |e| e["message"].to_s.start_with?("translation") }, dump(row)
    assert_equal "passed", row.status, dump(row)
  end

  test "a table with an empty cell and a blank corner header is drawn blank: no «translation missing», no «translation empty» (round 7)" do
    md = Rails.root.join("test/fixtures/lang/lesson_en_figures.md").read
    md = md.sub('  - ["he, she", "Has she got a dog?"]', '  - ["he, she", ""]').sub('  - ["lui, lei", "Ha un cane?"]', '  - ["lui, lei", ""]')
    md = md.sub('header: ["Subject", "Question"]', 'header: ["", "Question"]').sub('header_it: ["Soggetto", "Domanda"]', 'header_it: ["", "Domanda"]')
    row = render_figures("en", md: md)
    assert_empty row.result["errors"].select { |e| e["message"].to_s.start_with?("translation") }, dump(row)
    assert_equal "passed", row.status, dump(row)
  end

  test "a phone card with an example's choice step (two quoted options with a word of Italian), a typed gap ending in a lone full stop and suffixes with a leading hyphen: nothing overflows, nothing is missing" do
    row = render_figures("en", "lesson_en_example_choice.md")
    if ENV["BANCO_SHOT_DIR"]
      FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
      row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "example-choice-#{s['viewport']}-card#{s['card']}#{"-#{s['state']}" if s['state']}.webp"), LessonShots.read(s["sha256"])) }
    end
    assert_equal "passed", row.status, dump(row)
  end
end
