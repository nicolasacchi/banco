require "test_helper"

# D-362: an answer written in full is graded on its value: «x = 7,4», «5+4 = 9», «5+4 = 9 = 9». The shared vectors (number-written-*,
# fraction-written-*, expr-written-*) hold each case; this file holds the rules around them.
class WrittenAnswersTest < ActiveSupport::TestCase
  def number(value, answer: 9, stem: "$5+4$", **opts)
    Grading::Closed::Numbers.grade(Grading::Spec.new(component: "number", answer: answer, display: { "stem_it" => stem }, **opts), value)
  end

  def fraction(boxes, answer: { "n" => 5, "d" => 6 }, stem: "$\\frac{1}{3}+\\frac{1}{2}$", **opts)
    Grading::Closed::Fractions.grade(Grading::Spec.new(component: "fraction", answer: answer, display: { "stem_it" => stem }, **opts), boxes)
  end

  test "the members of a text are cut at the top-level equals sign only" do
    members = Grading::Closed::Equation.method(:members)
    assert_equal [ "x", "7,4" ], members.("x = 7,4")
    assert_equal [ "a", "b", "c" ], members.("a=b=c")
    assert_equal [ "(1+1=2)", "2" ], members.("(1+1=2) = 2")
    [ "7,4", "x =", "= 2", "x = = 2", "x<=3", "x>=3", "x!=3", "x:=3", "x==3", "(x = 3", "x = 3)", nil, 3 ].each { |t| assert_nil members.(t), t.inspect }
  end

  test "the stems of a spec: the math between dollars of the item's and the instance's stem, or plain arithmetic" do
    spec = Grading::Spec.from_hash("component" => "number", "answer" => 9, "prompt" => { "stem_it" => "Calcola $5+4$." }, "display" => { "stem_it" => "e poi $\\frac{1}{2}$" })
    assert_equal [ "5+4", "\\frac{1}{2}" ], spec.stem_expressions
    assert_equal [ "12 : 3 − 1" ], Grading::Spec.new(component: "number", display: { "stem_it" => "12 : 3 − 1" }).stem_expressions
    assert_empty Grading::Spec.new(component: "number", display: { "stem_it" => "Quanto fa la somma?" }).stem_expressions
    assert_empty Grading::Spec.new(component: "number").stem_expressions
  end

  test "a number: the left side is a letter or the expression shown, in LaTeX or as typed" do
    [ "x = 9", "N=9", "5+4 = 9", "5 + 4 = 9", "5+4=9", "(5+4) = 9" ].each { |t| assert_equal "correct", number(t).verdict, t }
    assert_equal "correct", number("12 : 3 − 1 = 3", answer: 3, stem: "12 : 3 − 1").verdict
    assert_equal "correct", number("12:3−1 = 3", answer: 3, stem: "$12 \\div 3 - 1$").verdict
    assert_equal "correct", number("2·3 = 6", answer: 6, stem: "$2 \\cdot 3$").verdict
    assert_equal "correct", number("1/2+1/4 = 0,75", answer: "3/4", stem: "$\\frac{1}{2}+\\frac{1}{4}$").verdict
  end

  test "a number: another left side is never accepted, even with the right value" do
    [ "5+5 = 9", "4+5 = 9", "y+1 = 9", "9 = 9", "xy = 9", "5+4+0 = 9" ].each do |t|
      r = number(t)
      assert_predicate r, :invalid?, t
      assert_equal "unreadable_number", r.invalid_code, t
    end
    assert_predicate number("5+4 = 9", stem: "Quanto fa la somma?"), :invalid?
    assert_predicate number("5+4 = 9", stem: "$5+4=9$"), :invalid?, "an equation shown is not an expression"
  end

  test "a number: the value keeps the item's rules (errors, unit, scientific form, accepted values)" do
    r = number("x = 5", answer: -5, errors: [ { "code" => "sign_error", "value" => 5 } ])
    assert_equal [ "typical_error", [ "sign_error" ], "5" ], [ r.verdict, r.error_codes, r.normalized ]
    assert_equal "correct", number("x = 9 cm", unit: "cm").verdict
    assert_equal "wrong_form", number("x = 90·10^-1", answer: 9, form: [ "scientific" ]).verdict
    assert_equal "correct", number("x = 9·10^0", answer: 9, form: [ "scientific" ]).verdict
    assert_equal "correct", number("x = 4,5", answer: 9, accept: [ "4,5" ]).verdict
    assert_equal "correct", number("x = 9%", answer: 9).verdict
  end

  test "a number: a chain needs every member to equal the key; a false step is wrong, an unreadable one unreadable" do
    assert_equal "correct", number("5+4 = 9 = 9").verdict
    assert_equal "correct", number("x = 9,0 = 9").verdict
    assert_equal "correct", number("9 = 9,0 = 9").verdict
    assert_equal [ "wrong", "9" ], number("5+4 = 8 = 9").then { |r| [ r.verdict, r.normalized ] }
    assert_equal "wrong", number("8 = 9 = 9").verdict
    assert_equal "wrong", number("x = 8 = 9").verdict
    assert_equal "wrong", number("5+4 = 9 = 8").verdict, "a wrong last value is wrong"
    assert_equal "unreadable_number", number("x = y = 9").invalid_code
    # D-317: two letters stay unreadable (held for the teacher) whatever the last member says, right or wrong
    [ 9, 2 ].each { |last| assert_equal "unreadable_number", number("n = m = #{last}").invalid_code, last.to_s }
    assert_equal "unreadable_fraction", fraction({ "n" => "n = m = 1/2", "d" => "" }).invalid_code
    assert_equal "unreadable_number", number("5+4 = 3+6 = 9").invalid_code, "a step that is not a number cannot be checked here"
  end

  test "a number: a slash is still not a number, with or without the letter (D-295)" do
    assert_equal "unreadable_number", number("x = 37/5", answer: "37/5").invalid_code
    assert_equal "unreadable_number", number("37/5", answer: "37/5").invalid_code
  end

  test "a fraction: the whole answer in the numerator box, the other boxes empty" do
    [ "x = 5/6", "x=5/6", "x = (5/6)", "1/3 + 1/2 = 5/6", "\\frac{1}{3}+\\frac{1}{2} = 5/6" ].each do |t|
      assert_equal "correct", fraction({ "n" => t, "d" => "" }).verdict, t
    end
    r = fraction({ "n" => "x = 5/6", "d" => "" })
    assert_equal "5/6", r.normalized
    assert_equal "correct", fraction({ "n" => "x = 37/5" }, answer: "37/5").verdict
    assert_equal "wrong", fraction({ "n" => "x = 37/4" }, answer: "37/5").verdict
  end

  test "a fraction: declared forms and errors apply to the last member" do
    forms = [ "lowest_terms" ]
    r = fraction({ "n" => "x = 10/12", "d" => "" }, form: forms)
    assert_equal [ "wrong_form", [ "lowest_terms" ] ], [ r.verdict, r.form_violations ]
    assert_equal "correct", fraction({ "n" => "x = 10/12 = 5/6", "d" => "" }, form: forms).verdict
    mixed = fraction({ "n" => "x = 11/6", "d" => "" }, answer: "11/6", form: [ "mixed" ])
    assert_equal [ "wrong_form", [ "improper" ] ], [ mixed.verdict, mixed.form_violations ]
    slip = fraction({ "n" => "x = 6/5", "d" => "" }, errors: [ { "code" => "flipped", "value" => "6/5" } ])
    assert_equal [ "typical_error", [ "flipped" ] ], [ slip.verdict, slip.error_codes ]
  end

  test "a fraction: another left side, a false step, a zero denominator, a decimal" do
    assert_equal "unreadable_fraction", fraction({ "n" => "1+1 = 5/6", "d" => "" }).invalid_code
    assert_equal "wrong", fraction({ "n" => "x = 1/2 = 5/6", "d" => "" }).verdict
    assert_equal "wrong", fraction({ "n" => "1/2 = 5/6 = 5/6", "d" => "" }).verdict
    assert_equal "zero_denominator", fraction({ "n" => "x = 5/0", "d" => "" }).invalid_code
    assert_equal "unreadable_fraction", fraction({ "n" => "x = y = 5/6", "d" => "" }).invalid_code
  end

  test "a fraction: the boxes read as before (D-295): a letter in a box, a lone numerator, a slash with the denominator box filled" do
    assert_equal "correct", fraction({ "n" => "x = 5", "d" => "6" }).verdict
    assert_equal "empty", fraction({ "n" => "x = 5", "d" => "" }).invalid_code
    assert_equal "empty", fraction({ "n" => "5", "d" => "" }).invalid_code
    assert_equal "unreadable_fraction", fraction({ "n" => "5/6", "d" => "1" }).invalid_code
  end
end
