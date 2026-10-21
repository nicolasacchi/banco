require "test_helper"

# D-295: a number or a fraction box may carry one leading Latin letter and "=", and one pair of
# parentheses around the whole value. Nothing else about the reading changes.
class NumberWrappersTest < ActiveSupport::TestCase
  def number(value, answer: -2, **opts)
    Grading::Closed::Numbers.grade(Grading::Spec.new(component: "number", answer: answer, **opts), value)
  end

  def fraction(boxes, answer: { "n" => -3, "d" => 4 })
    Grading::Closed::Fractions.grade(Grading::Spec.new(component: "fraction", answer: answer, form: [ "lowest_terms" ]), boxes)
  end

  test "a letter and an equals sign are dropped" do
    [ "n=-2", "n = -2", "n=−2", "N = -2", "x =  -2", "n = - 2" ].each do |t|
      r = number(t)
      assert_equal "correct", r.verdict, t
      assert_equal "-2", r.normalized, t
    end
    assert_equal "correct", number("x=3", answer: 3).verdict
    assert_equal "correct", number("N = 2,5", answer: "2,5").verdict
  end

  test "one pair of parentheses around the whole value is dropped" do
    [ "(-2)", "(−2)", "( -2 )", "(- 2)", "n = (-2)", "n=(-2)" ].each { |t| assert_equal "correct", number(t).verdict, t }
    assert_equal "correct", number("(+3)", answer: 3).verdict
    assert_equal "correct", number("( 2,5 )", answer: "2,5").verdict
  end

  test "the stripped form is what is normalized and matched against declared errors" do
    errors = [ { "code" => "sign_error", "value" => 5 } ]
    r = number("n = 5", answer: -5, errors: errors)
    assert_equal "typical_error", r.verdict
    assert_equal [ "sign_error" ], r.error_codes
    assert_equal "5", r.normalized
    assert_equal "wrong", number("(7)", answer: -5, errors: errors).verdict
  end

  test "every other rule still applies inside the wrapper" do
    assert_equal "correct", number("n = 2.5", answer: "2,5").verdict
    assert_equal "thousands_separator", number("(5.300)", answer: 5300).invalid_code
    assert_equal "correct", number("n = 5.300", answer: 5300, thousands: true).verdict
    assert_equal "correct", number("n = 2,5·10^3", answer: 2500, form: [ "scientific" ]).verdict
  end

  test "anything else stays unreadable, with the number message" do
    [ "n = m = 2", "2 = n", "nn = 2", "n =", "= 2", "()", "((2))", "(2", "2)", "(2)(3)", "(n = 2)", "n = (2", "1 = 2", "3 = x", "ab" ].each do |t|
      r = number(t, answer: 2)
      assert_predicate r, :invalid?, t
      assert_equal "unreadable_number", r.invalid_code, t
      assert_equal "Scrivi solo il numero, per esempio −3 oppure 2,5.", r.message_it, t
    end
  end

  test "fraction boxes take the same wrappers" do
    assert_equal "correct", fraction({ "n" => "(-3)", "d" => "4" }).verdict
    assert_equal "correct", fraction({ "n" => "n = -3", "d" => "(4)" }).verdict
    assert_equal "correct", fraction({ "n" => "-3", "d" => "d = 4" }).verdict
  end

  test "an unreadable fraction box says how to write a fraction" do
    [ "-3/4", "(-3/4)", "n = m = 3", "3 = n", "((3))" ].each do |t|
      r = fraction({ "n" => t, "d" => "4" })
      assert_equal "unreadable_fraction", r.invalid_code, t
      assert_equal "Scrivi la frazione, per esempio −3/4.", r.message_it, t
    end
  end
end
