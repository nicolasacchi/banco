require "test_helper"

# D-093: a number item may list other exact values (accept) and may declare form scientific.
class D093NumbersTest < ActiveSupport::TestCase
  def grade(value, answer:, **opts)
    Grading::Closed::Numbers.grade(Grading::Spec.new(component: "number", answer: answer, **opts), value)
  end

  test "accept lists extra right values" do
    assert_equal "correct", grade("298", answer: 298, accept: [ "298,15" ]).verdict
    assert_equal "correct", grade("298,15", answer: 298, accept: [ "298,15" ]).verdict
    assert_equal "wrong", grade("298,2", answer: 298, accept: [ "298,15" ]).verdict
    assert_equal "wrong", grade("298,15", answer: 298).verdict
  end

  test "scientific: a·10^n with 1 <= a < 10 is correct in every spelling" do
    [ "5,2·10^-4", "5,2 x 10^-4", "5,2×10^{-4}", "5,2 * 10^−4", "5,2·10⁻⁴", "5,2 X 10 ^ -4" ].each do |t|
      assert_equal "correct", grade(t, answer: "0,00052", form: [ "scientific" ]).verdict, t
    end
  end

  test "scientific: the right value in another shape is wrong_form" do
    [ "0,00052", "52·10^-5", "0,52·10^-3" ].each do |t|
      r = grade(t, answer: "0,00052", form: [ "scientific" ])
      assert_equal "wrong_form", r.verdict, t
      assert_equal [ "scientific_notation" ], r.form_violations, t
    end
  end

  test "scientific: a plain number already in range is correct, a wrong value is wrong, junk is invalid" do
    assert_equal "correct", grade("3,5", answer: "3,5", form: [ "scientific" ]).verdict
    assert_equal "wrong", grade("5,3·10^-4", answer: "0,00052", form: [ "scientific" ]).verdict
    assert_predicate grade("5,2·10^", answer: "0,00052", form: [ "scientific" ]), :invalid?
    assert_equal "number_too_large", grade("1·10^9999", answer: 1, form: [ "scientific" ]).invalid_code
  end

  test "without the form, scientific notation stays unparseable" do
    assert_predicate grade("5,2·10^-4", answer: "0,00052"), :invalid?
  end

  test "the validation key round-trip writes the scientific string" do
    assert_equal [ "5,2·10^-4", nil ], Validation::Answers.raw_for("number", "0,00052", form: [ "scientific" ])
    assert_equal [ "-3·10^2".sub("·", "·"), nil ], Validation::Answers.raw_for("number", -300, form: [ "scientific" ])
  end
end
