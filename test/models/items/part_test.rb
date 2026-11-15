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
    dir = Dir.mktmpdir
    Rails.application.config.x.item_assets_dir = dir
    File.write(File.join(dir, "#{sha}.svg"), "<svg/>")
    assert_equal({ alt_it: "d", src: "/assets/items/#{sha}.svg" }, part.figure({ "sha256" => sha, "alt_it" => "d" }))
    assert_equal({ alt_it: "d" }, part.figure({ "sha256" => "../x", "alt_it" => "d" }))
    assert_nil part.figure("nope")
  ensure
    Rails.application.config.x.item_assets_dir = nil
    FileUtils.rm_rf(dir) if dir
  end

  # D-335 (item 29): a number whose key and accepted forms are all whole is served `integer: true`, a fact about the key's kind and never the key.
  test "a number part is integer when the key and every accepted form are whole numbers, and only then" do
    body = { "component" => "number", "prompt" => { "stem_it" => "Quanto?" } }
    integer = ->(answer, accept = [], b = body) { part.call(b, "number", {}, answer: answer, accept: accept)[:integer] }
    assert_equal true, integer.call("12")
    assert_equal true, integer.call(12)
    assert_equal true, integer.call("-3")
    assert_equal true, integer.call("\u22123", %w[4 5])
    assert_nil integer.call("1,5")
    assert_nil integer.call("12", %w[12,0])
    assert_nil integer.call("12", Items::Part.accepted(body.merge("accept" => [ "12,5" ]), []))
    assert_nil integer.call("0.5")
    assert_nil integer.call(nil), "no key given (a caller that does not know it): nothing is said"
    assert_nil integer.call("12", [], body.merge("form" => [ "scientific" ])), "a scientific form has its own line"
    assert_nil part.call(body, "fraction", {}, answer: "12")[:integer]
    assert_nil part.call(body, "number", {})[:integer]
    refute_includes part.call(body, "number", {}, answer: "12").to_json, "\"12\""
  end
end
