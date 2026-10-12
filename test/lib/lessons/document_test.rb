require "test_helper"

# Lessons::Diagrams::Document (T8) against test/fixtures/diagrams/types/document.json (the browser runs the same file in
# lesson/test/document.test.mjs): the semantic column with the same code and path, the schema column, what is served, the select targets
# in the order the browser returns them, and the hidden rows that never reach a printed string.
class LessonsDocumentTest < ActiveSupport::TestCase
  FILE = JSON.parse(Rails.root.join("test/fixtures/diagrams/types/document.json").read)
  VECTORS = FILE.fetch("vectors")
  D = Lessons::Diagrams

  def vector(name) = VECTORS.find { |v| v["name"] == name }.fetch("data")

  VECTORS.select { |v| v["schema"] == "valid" }.each do |v|
    test "semantic column: #{v['name']}" do
      findings = D.check(v["data"], subject: v["subject"])
      if v["semantic"] == "ok"
        assert_empty findings.map(&:to_h), v["name"]
      else
        hit = findings.find { |f| f.code == v["semantic"] && f.path == v["path"] }
        assert hit, "#{v['name']}: expected #{v['semantic']} at #{v['path']}, got #{findings.map { |f| [ f.code, f.path ] }.inspect}"
      end
    end
  end

  test "the select targets are the zones the sheet has and the rows it draws, in the order of the browser" do
    cover = vector("invoice-sheet-cover")
    assert_equal %w[seller buyer number date lines costs], D::Document.targets(cover, "zones")
    assert_equal %w[gross discounts net costs_in base vat costs_out total], D::Document.targets(cover, "rows")
    assert_equal %w[seller buyer lines], D::Document.targets(vector("invoice-two-rates"), "zones")
    assert_raises(ArgumentError) { D::Document.targets(cover, "cells") }
  end

  test "a hidden row's amount is in no printed string and not in the served figure" do
    data = vector("invoice-hidden-rows")
    printed = D::Document.printed(data, 0).join(" ")
    assert_not_includes printed, "1860,00"
    assert_not_includes printed, "409,20"
    assert_includes printed, "2000,00"
    served = D::Document.served(data).to_json
    assert_not_includes served, "1860,00"
    assert_equal data["hide"], D::Document.served(data)["hide"]
  end

  test "the whitelist projection keeps the drawing's fields and nothing else" do
    served = D::Document.served(vector("invoice-sheet-cover"))
    declared = D.schema_def("document").fetch("properties").keys
    assert_empty served.keys - declared
    assert_equal "invoice", served["kind"]
  end

  test "the typical error is checked against the invoice, and every name of the closed list is accepted somewhere" do
    ex = { "type" => "document", "alt_it" => "Una fattura di prova per cinque parole e più ancora per essere lunga.", "kind" => "invoice",
           "lines" => [ { "text_it" => "Sedie", "qty" => "40", "price" => "75,00", "vat" => "22" } ], "discounts" => [ "10", "5" ],
           "costs" => [ { "text_it" => "Trasporto", "amount" => "120,00" }, { "text_it" => "Assicurazione", "amount" => "25,00", "documented" => true } ] }
    (Lessons::Money::ERROR_VARIANTS - %w[two_rates_single_rate two_rates_combined]).each do |e|
      assert_empty D.check(ex.merge("error" => e), subject: "business").map(&:to_h), e
    end
  end

  test "money.row is the verify function of the figure" do
    assert_equal "2000,00", D::Document.verify_functions.fetch("money.row").call("qty" => "800", "price" => "2,50")
  end

  test "the other kinds are not checked here: the reserved dry run reads their draft schema only" do
    assert_empty D.check({ "type" => "document", "alt_it" => "Un contratto di prova con le parti e la firma in fondo alla pagina.", "kind" => "contract" }, subject: "business").map(&:to_h)
  end
end
