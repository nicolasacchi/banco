require "test_helper"
require_relative "../support/lesson2_fixtures"

# D-402, round 5 of the tooling: the headers of a table of forms are chrome, not material. `translate_material: false` on a table says that its cells are forms
# with no Italian; its headers may still be written as a pair (`header` + `header_it`) and are then drawn with their translation.
class BilingualToolingFiveTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  B = Lessons::Bilingual
  GUARDED = %w[E-LANG-PAIR-ORPHAN E-LANG-PAIR-MISSING E-SCHEMA E-LESSON-BLOCK E-LESSON-DIAGRAM].freeze

  def en = DIR.join("lesson_en_figures.md").read
  def check(md) = Validation::LessonChecks.call(md, subject: "english", context: F.context("english"))
  def guarded(outcome) = outcome.findings.select { |f| GUARDED.include?(f.code) }.map { |f| [ f.code, f.field ] }

  ROWS_IT = <<~Y.freeze
    rows_it:
      - ["lui, lei", "Ha un cane?"]
      - ["voi, loro", "Hanno una macchina?"]
  Y

  # the golden table figure of lesson_en_figures.md as a table of forms: the marker on it, the cells with no Italian, the headers still a pair
  def material_table
    md = en.sub("alt_it: \"Tabella di domande: il soggetto e la forma di have got.\"\n", "\\&translate_material: false\n")
    assert_includes md, ROWS_IT
    md.sub(ROWS_IT, "")
  end

  test "the headers of a table of forms are a pair: header_it beside material cells is no E-LANG-PAIR-ORPHAN, and the lesson stays clean" do
    assert_empty guarded(check(en))
    assert_empty guarded(check(material_table))
  end

  test "the cells stay material: rows_it beside them is still E-LANG-PAIR-ORPHAN, and a header with no Italian is no finding either" do
    with_rows_it = en.sub("alt_it: \"Tabella di domande: il soggetto e la forma di have got.\"\n", "\\&translate_material: false\n")
    assert_includes guarded(check(with_rows_it)).map(&:first), "E-LANG-PAIR-ORPHAN"
    no_header_it = material_table.sub("header_it: [\"Soggetto\", \"Domanda\"]\n", "")
    assert_empty guarded(check(no_header_it))
  end

  test "pairs and fold: the headers of a table of forms are a pair (their Italian goes to tr), the cells have none" do
    table = { "type" => "table", "translate_material" => false, "header" => [ "Subject", "Verb" ], "header_it" => [ "Soggetto", "Verbo" ], "rows" => [ [ "he", "plays" ] ] }
    pointer = "/cards/0/blocks/0"
    assert_equal [ [ "#{pointer}/header/0", "header", "Subject", "Soggetto" ], [ "#{pointer}/header/1", "header", "Verb", "Verbo" ] ], B.pairs(table, "en", pointer).to_a
    assert_not B.material?(table, "header", pointer, true), "a header written with its header_it is chrome"
    assert B.material?(table.except("header_it"), "header", pointer, true), "a header with no Italian is as the cells are"
    assert B.material?(table, "rows", pointer, true)
    layer = B.italian_layer({ "cards" => [ { "blocks" => [ table ] } ] })["cards"][0]["blocks"][0]
    assert_equal %w[Soggetto Verbo], layer["header"]
    assert_equal [ [ "he", "plays" ] ], layer["rows"], "the cells stay as the student reads them"
  end
end
