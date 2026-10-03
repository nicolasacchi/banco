require "test_helper"

# The fraction boxes: the value is exact, and the shape of a mixed number is checked.
class FractionsGradingTest < ActiveSupport::TestCase
  def grade(answer, boxes, form: [ "mixed" ])
    spec = Grading::Spec.new(component: "fraction", answer: answer, form: form)
    Grading::Closed::Fractions.grade(spec, boxes)
  end

  test "a proper mixed number is correct" do
    assert_equal "correct", grade({ "w" => 1, "n" => 2, "d" => 3 }, { "w" => "1", "n" => "2", "d" => "3" }).verdict
    assert_equal "correct", grade({ "w" => -1, "n" => 1, "d" => 2 }, { "w" => "-1", "n" => "1", "d" => "2" }).verdict
  end

  test "an improper fractional part is not a mixed number" do
    r = grade({ "w" => 2, "n" => 2, "d" => 3 }, { "w" => "1", "n" => "5", "d" => "3" })
    assert_equal "wrong_form", r.verdict
    assert_equal [ "improper" ], r.form_violations
  end

  test "a negative numerator beside a whole part is invalid, not read as its absolute value" do
    r = grade({ "w" => 1, "n" => 1, "d" => 2 }, { "w" => "1", "n" => "-1", "d" => "2" })
    assert_predicate r, :invalid?
    assert_equal "signed_fraction_part", r.invalid_code
  end

  test "a negative denominator is invalid" do
    r = grade({ "n" => -1, "d" => 2 }, { "n" => "1", "d" => "-2" }, form: [ "lowest_terms" ])
    assert_predicate r, :invalid?
    assert_equal "negative_denominator", r.invalid_code
    assert_predicate grade({ "n" => -1, "d" => 2 }, { "n" => "-1", "d" => "-2" }, form: [ "lowest_terms" ]), :invalid?
  end

  test "a negative numerator over a positive denominator is correct" do
    assert_equal "correct", grade({ "n" => -3, "d" => 4 }, { "n" => "-3", "d" => "4" }, form: [ "lowest_terms" ]).verdict
  end
end
