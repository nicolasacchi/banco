require "test_helper"

# Lessons::Money against the shared vectors of the browser twin (test/fixtures/lesson2/money.json).
class LessonsMoneyTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(Rails.root.join("test/fixtures/lesson2/money.json").read)

  VECTORS["functions"].each do |fn, spec|
    spec["cases"].each_with_index do |c, i|
      test "#{fn} #{i}: #{c['args'].to_json[0, 60]}" do
        if c["refused"]
          assert_raises(Lessons::Money::Refused) { Lessons::Money.public_send(fn, *c["args"]) }
        else
          assert_equal c["result"], Lessons::Money.public_send(fn, *c["args"])
        end
      end
    end
  end

  test "the closed list of invoice errors is the vectors' list and each one changes the exam invoice" do
    assert_equal VECTORS["functions"]["invoice"]["error_variants"], Lessons::Money::ERROR_VARIANTS
    ex = VECTORS["functions"]["invoice"]["cases"][1]["args"][0]
    right = Lessons::Money.invoice(ex)["rows"]["total"]
    Lessons::Money::ERROR_VARIANTS.each do |e|
      next if e.start_with?("two_rates")

      assert_not_equal right, Lessons::Money.invoice(ex.merge("error" => e))["rows"]["total"], e
    end
  end

  test "an amount is displayed with the thousands dot" do
    assert_equal "2.319,20", Lessons::Money.display("2319,20")
    assert_equal "1.240.000,05", Lessons::Money.display("1240000,05")
    assert_equal "60,00", Lessons::Money.display("60,00")
    assert_equal "-1.000,00", Lessons::Money.display("-1000,00")
  end

  test "the rows are exact: no float anywhere" do
    spec = { "lines" => [ { "qty" => "3", "price" => "0,335", "vat" => "22" } ] }
    assert_equal "1,01", Lessons::Money.invoice(spec)["lines"].first
    assert_equal "0,22", Lessons::Money.invoice(spec)["rows"]["vat"]
  end
end
