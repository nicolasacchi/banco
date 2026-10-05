require "test_helper"
require_relative "../support/validation_fixtures"

# D-118: a table cell may be empty (a spreadsheet grid). Arrows pass the lint in every _it field (D-095).
class D118Test < ActiveSupport::TestCase
  F = ValidationFixtures

  test "empty table cells in the header and the rows pass the item run and the leak scan still reads the others" do
    table = { "header" => [ "", "A", "B" ], "rows" => [ [ "1", "3", "" ], [ "2", "", "7" ] ] }
    ok = F.static_item("prompt" => { "table" => table }, "instances" => [ F.number_instance(25, 150), F.number_instance(4, 13) ])
    result = Validation::ItemRunner.new(files: F.files_for(ok), context: F.context).call
    assert_empty result.findings.select { |f| f.code == "E-SCHEMA" && f.field.to_s.include?("table") }.map(&:to_h)
    leak = F.static_item("prompt" => { "table" => table.merge("rows" => [ [ "7", "13 e 125", "" ] ]) }, "instances" => [ F.number_instance(25, 150), F.number_instance(4, 13) ])
    assert_includes Validation::ItemRunner.new(files: F.files_for(leak), context: F.context).call.findings.map(&:code), "E-SOLUTION-IN-DISPLAY"
  end

  test "an assignment arrow in an error description passes the readability lint" do
    f = Validation::Findings.new
    Validation::Readability.lint_document({ "error_catalogue" => [ { "description_it" => "Crede che a ← b seguito da b ← a scambi i valori." } ] }, "", f)
    assert_empty f.select { |x| x.code == "E-READ" }.map(&:to_h)
  end
end
