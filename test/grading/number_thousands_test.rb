require "test_helper"
require_relative "../support/validation_fixtures"

# Round 8 (D-402): `thousands: true` on a number item. In an english item a comma that groups exactly three digits is thousands grouping («1,704» is 1704);
# «1,5» stays 1.5, the Italian dot grouping still works, and a key that is the decimal reading keeps it.
class NumberThousandsTest < ActiveSupport::TestCase
  def spec(answer, subject: "english", thousands: true, **opts)
    Grading::Spec.from_hash({ "component" => "number", "subject" => subject, "skill" => "#{subject}.numbers", "answer" => answer, "thousands" => thousands }.merge(opts.stringify_keys))
  end

  def verdict(answer, typed, **opts) = Grading::Closed.grade(spec(answer, **opts), typed).verdict

  test "1,704 is 1704 and 12,500 is 12500 in an english item with thousands, and the Italian dot grouping still works" do
    assert_equal "correct", verdict("1704", "1,704")
    assert_equal "correct", verdict("12500", "12,500")
    assert_equal "correct", verdict("1234567", "1,234,567")
    assert_equal "correct", verdict("1704", "1.704")
    assert_equal "correct", verdict("1704", "1704")
    assert_equal "correct", verdict("-1704", "-1,704")
  end

  test "1,5 stays 1.5, and a comma that does not group three digits is a decimal as before" do
    assert_equal "correct", verdict("1.5", "1,5")
    assert_equal "wrong", verdict("15", "1,5")
    assert_equal "correct", verdict("12.25", "12,25")
    assert_equal "wrong", verdict("1704", "1,70")
    assert_equal "wrong", verdict("1704", "1,7045")
  end

  test "when the key is the decimal reading, 1,704 stays the decimal 1.704 (and its accept entries count too)" do
    assert_equal "correct", verdict("1.704", "1,704")
    assert_equal "wrong", verdict("1704", "1,740")
    assert_equal "correct", verdict("1704", "1,704", accept: [ "1700" ]), "an accept entry that is not the decimal reading changes nothing"
    assert_equal "correct", verdict("5", "1,704", accept: [ "1.704" ]), "an accepted decimal reading keeps the decimal"
  end

  test "the item schema allows thousands on a number item" do
    doc = ValidationFixtures.static_item("thousands" => true)
    shape = Validation::Findings.new
    Validation::SchemaCheck.call("item", doc, shape)
    assert_empty shape.map(&:to_h).select { |f| f[:field].to_s.include?("thousands") }, shape.map(&:to_h).inspect
  end

  test "the rule needs thousands: true and the subject english: otherwise the comma is the decimal comma" do
    assert_equal "wrong", verdict("1704", "1,704", thousands: false)
    assert_equal "wrong", verdict("1704", "1,704", subject: "math")
    assert_equal "correct", verdict("1.704", "1,704", subject: "math")
    assert_equal "invalid", Grading::Closed.grade(spec("1704", thousands: false), "1.704").verdict, "the Italian dot without the option stays refused"
  end

  test "a wrong value stays wrong and a declared error value still fires" do
    errors = [ { "code" => "en_digits", "value" => "1740" } ]
    assert_equal "wrong", verdict("1704", "1,705")
    hit = Grading::Closed.grade(spec("1704", errors: errors), "1,740")
    assert_equal [ "typical_error", [ "en_digits" ] ], [ hit.verdict, hit.error_codes ]
  end
end
