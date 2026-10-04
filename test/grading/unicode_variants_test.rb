require "test_helper"

# Number and text input with Unicode look-alikes (audit, D-073): every space and minus
# variant is read as the plain one, invisible characters are dropped, anything else is invalid.
class UnicodeVariantsTest < ActiveSupport::TestCase
  Numbers = Grading::Closed::Numbers
  Text = Grading::Closed::Text

  def number(value, answer: -3)
    Grading::Closed::Numbers.grade(Grading::Spec.new(component: "number", answer: answer), value)
  end

  test "every minus variant reads as a minus" do
    [ "\u2212", "\u2010", "\u2011", "\u2012", "\u2013", "\u2014", "\u2015", "\uFE63", "\uFF0D" ].each do |minus|
      assert_equal "correct", number("#{minus}3").verdict, minus.unpack1("U*").to_s(16)
    end
  end

  test "every space variant around a number is trimmed, and between digits it is still ambiguous" do
    [ "\u00A0", "\u2000", "\u2003", "\u2009", "\u200A", "\u202F", "\u205F", "\u3000", "\u1680" ].each do |space|
      assert_equal "correct", number("#{space}-3#{space}").verdict
      assert_equal "ambiguous_mixed_number", number("1#{space}000", answer: 1000).invalid_code
    end
  end

  test "invisible characters are dropped and look-alike digits stay invalid" do
    assert_equal "correct", number("-\u200B3\uFEFF").verdict
    assert_equal "correct", number("\u00AD-3").verdict
    assert_predicate number("\uFF13", answer: 3), :invalid? # fullwidth digit: not guessed
    assert_predicate number("3\u00B2", answer: 9), :invalid? # superscript two is not a 2
  end

  test "text: ZWSP, ZWNJ, ZWJ, BOM and soft hyphen are stripped" do
    assert_equal "casa", Text.normalize("ca\u200Bsa")
    assert_equal "casa", Text.normalize("\uFEFFcasa")
    assert_equal "casa", Text.normalize("ca\u200C\u200Dsa")
    assert_equal "casa", Text.normalize("ca\u00ADsa")
    assert_equal "la casa", Text.normalize("la\u00A0casa\u2009")
  end

  test "fraction boxes read the same variants" do
    spec = Grading::Spec.new(component: "fraction", answer: { "n" => -1, "d" => 2 }, form: [])
    assert_equal "correct", Grading::Closed::Fractions.grade(spec, { "n" => "\u2212\u200B1", "d" => "\u00A02" }).verdict
  end
end
