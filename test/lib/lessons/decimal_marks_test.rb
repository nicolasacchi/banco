require "test_helper"
require_relative "../../support/lesson2_fixtures"

# D-409: an English lesson writes the numbers of a bar_model with a decimal point, as its text does («18.8%»); the parser turns them into the exact numbers of
# Lessons::Num (comma), so the figure is checked, stored and served as ever, and chart/format.js prints them with a point again. Italian and Spanish lessons
# still refuse a point (a «1.500» there would be a thousands dot).
class DecimalMarksTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures

  BAR = <<~MD
    ::: diagram bar_model
    alt_en: "One bar of a hundred percent: young people with a job, 18.8, and the rest."
    alt_it: "Una barra del cento per cento: i giovani con un lavoro, 18,8, e il resto."
    view: parts
    total: {value: %<total>s, label_en: "All", label_it: "Tutti"}
    bars:
      - label_en: "Young people"
        label_it: "Giovani"
        parts:
          - {value: %<first>s, label_en: "with a job", label_it: "con un lavoro"}
          - {value: %<second>s, label_en: "the rest", label_it: "il resto"}
    :::

  MD

  def lesson(first: "18.8", second: "81.2", total: "\"100\"")
    DIR.join("lesson_en.md").read.sub("::: check choice", "#{format(BAR, first: first, second: second, total: total)}::: check choice")
  end

  def parse(md)
    findings = Validation::Findings.new
    body = Lessons::Parser2.call(md, findings).body
    [ body, findings ]
  end

  def figure(body) = body["cards"][0]["blocks"].find { |b| b["type"] == "diagram" }["diagram"]

  test "an english bilingual lesson accepts 18.8 (quoted or a YAML number) and keeps the exact number with a comma" do
    [ [ "18.8", "81.2" ], [ "\"18.8\"", "\"81.2\"" ] ].each do |first, second|
      body, findings = parse(lesson(first: first, second: second))
      assert_empty findings.map(&:to_h), first
      parts = figure(body)["bars"][0]["parts"]
      assert_equal %w[18,8 81,2], parts.map { |p| p["value"] }
      assert_equal "100", figure(body)["total"]["value"]
    end
  end

  test "the whole lesson validates, and the figure is served with the comma the renderer reads" do
    md = lesson
    found = Validation::LessonChecks.call(md, subject: "english", context: F.context("english")).findings
    assert_empty found.select { |f| f.field.to_s.include?("/diagram") || f.code == "E-LESSON-BLOCK" }.map { |f| [ f.code, f.field, f.message ] }
    body = Lessons::StudentBody.project(Lessons::Parser2.call(md, Validation::Findings.new).body, revision_id: 1, seed: "preview")
    served = body["cards"][0]["blocks"].find { |b| b["type"] == "diagram" }["diagram"]
    assert_equal %w[18,8 81,2], served["bars"][0]["parts"].map { |p| p["value"] }
  end

  test "a comma still works, and a point that is no decimal is left to the schema" do
    body, findings = parse(lesson(first: "\"18,8\"", second: "\"81,2\""))
    assert_empty findings.map(&:to_h)
    assert_equal %w[18,8 81,2], figure(body)["bars"][0]["parts"].map { |p| p["value"] }
    _, findings = parse(lesson(first: "\"18.\"", second: "\"81.2\""))
    assert_equal [ "E-LESSON-BLOCK" ], findings.map(&:code).uniq
  end

  test "outside an english bilingual lesson a point is still refused: the schema reads the exact numbers of Lessons::Num" do
    block = { "type" => "diagram", "diagram" => { "type" => "bar_model", "alt_it" => "Una barra del cento per cento con due parti, diciotto e il resto.", "view" => "parts",
                                                   "total" => { "value" => "100" }, "bars" => [ { "label_it" => "Barra", "parts" => [ { "value" => "18.8", "label_it" => "uno" }, { "value" => "81,2", "label_it" => "resto" } ] } ] } }
    assert_match(/value/, Lessons::Parser2.block_errors(block, "geography").join)
    fixed = Lessons::Diagrams::BarModel.decimal_commas(JSON.parse(JSON.generate(block)))
    assert_empty Lessons::Parser2.block_errors(fixed, "geography")
    assert_equal "18,8", fixed.dig("diagram", "bars", 0, "parts", 0, "value")
  end
end
