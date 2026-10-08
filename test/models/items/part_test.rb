require "test_helper"

# Items::Part is what both the diagnosis and the practice pages tell the browser about one answerable part.
class ItemsPartTest < ActiveSupport::TestCase
  Subject = Struct.new(:key)

  def part(subject = "math", **opts) = Items::Part.new(subject: Subject.new(subject), **opts)

  test "only the named parts are copied; the key, errors and solution never are" do
    body = { "component" => "number", "prompt" => { "stem_it" => "Quanto fa?" }, "answer_format_it" => "Solo il numero.", "error_catalogue" => [ { "code" => "x" } ],
             "hints_it" => [ "uno" ], "form" => [ "scientific" ] }
    display = { "stem_it" => "2 + 2", "answer" => "4", "errors" => [ 1 ], "solution" => { "final" => "4" }, "unit" => "cm" }
    out = part.call(body, "number", display)
    assert_equal({ component: "number", stem_it: "Quanto fa?", instance_stem_it: "2 + 2", unit: "cm", scientific: true, answer_format_it: "Solo il numero." }, out)
  end

  test "accents follow the subject and the expression input follows the setting" do
    assert_equal "it", part("italian").call({}, "normalized_text", {})[:accents]
    assert_nil part("math").call({}, "normalized_text", {})[:accents]
    assert_equal "text", part("math", expression_input: "text").call({}, "expression", {})[:input]
    assert_equal "mathlive", part.call({}, "expression", {})[:input]
  end

  test "a figure is only an image from its digest" do
    sha = Digest::SHA256.hexdigest("<svg/>")
    assert_equal({ alt_it: "d", src: "/assets/items/#{sha}.svg" }, part.figure({ "sha256" => sha, "alt_it" => "d" }))
    assert_equal({ alt_it: "d" }, part.figure({ "sha256" => "../x", "alt_it" => "d" }))
    assert_nil part.figure("nope")
  end
end
