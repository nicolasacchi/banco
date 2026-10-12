require "test_helper"

# check option `input: bits` (T9, WAVE2 2.11): the Ruby checks of the option, what is served for the switches, and that the binary profile
# grades the string the switches give.
class BitsInputTest < ActiveSupport::TestCase
  Ctx = Struct.new(:findings) do
    def add(code, path, _message, **) = findings << [ code, path ]
    def catalogue_code(*) = nil
  end

  def check(over = {})
    { "component" => "normalized_text", "prompt_it" => "Scrivi -3 in complemento a 2 su 8 bit.", "input" => "bits", "answer" => "11111101",
      "profile" => { "name" => "binary", "width" => 8, "leading_zeros" => "required" },
      "errors" => [ { "answer" => "00000001", "code" => "inverted_before_padding", "message_it" => "Hai invertito prima di portare a 8 bit." },
                    { "answer" => "11111100", "code" => "invert_without_plus_one", "message_it" => "Manca il più 1." } ],
      "explain_it" => "3 è 0000 0011; invertito 1111 1100; più 1: 1111 1101." }.merge(over)
  end

  def findings(spec)
    ctx = Ctx.new([])
    Lessons::Blocks::Check.check(spec, ctx)
    ctx.findings
  end

  test "a clean check passes" do
    assert_empty findings(check)
  end

  test "the option is available for normalized_text; what still holds a check back is the profile it carries (T1's option)" do
    assert_equal "available", Lessons::Types.data.fetch("check_options").fetch("input_bits")["status"]
    assert_equal %w[profile], Lessons::Types.held_back_options(check).map(&:first), "input: bits itself is not held back"
  end

  test "switches need the binary profile with its width" do
    assert_includes findings(check("profile" => nil)), %w[E-LESSON-CHECK input]
    assert_includes findings(check("profile" => { "name" => "binary" })), %w[E-LESSON-CHECK input]
  end

  test "the answer is exactly that many bits" do
    assert_includes findings(check("answer" => "1111101")), %w[E-LESSON-CHECK answer]
    assert_includes findings(check("answer" => "1111110X")), %w[E-LESSON-CHECK answer]
  end

  test "with switches an error answer is the whole width too, except under padding_missing which keeps the typed input" do
    short = check("errors" => [ { "answer" => "1101", "code" => "other_error", "message_it" => "x" } ])
    assert_includes findings(short), %w[E-LESSON-CHECK errors/0/answer]
    padded = check("errors" => [ { "answer" => "1101", "code" => "padding_missing", "message_it" => "Mancano gli zeri a sinistra." } ])
    assert_empty findings(padded)
    assert_not Lessons::Checks.bits_switches?(padded)
    assert Lessons::Checks.bits_switches?(check)
  end

  test "served: the switches get their width, never the profile or the answer; padding_missing serves the typed input" do
    served = Lessons::StudentBody.check(check, "computer_science", "seed")
    assert_equal "bits", served["input"]
    assert_equal 8, served["input_width"]
    %w[profile answer errors explain_it].each { |k| assert_not served.key?(k), k }
    typed = Lessons::StudentBody.check(check("errors" => [ { "answer" => "1101", "code" => "padding_missing", "message_it" => "x" } ]), "computer_science", "seed")
    assert_not typed.key?("input")
    assert_not typed.key?("input_width")
    plain = Lessons::StudentBody.check(check.except("input"), "computer_science", "seed")
    assert_not plain.key?("input_width")
  end

  test "the string the switches give is graded by the binary profile: the right one, a typical error, a wrong one" do
    grade = ->(response) { Lessons::Checks.grade(check, response, {}, subject: "computer_science") }
    assert grade.call("11111101").right?
    assert_equal "invert_without_plus_one", grade.call("11111100").code
    assert grade.call("10000011").wrong?
  end
end
