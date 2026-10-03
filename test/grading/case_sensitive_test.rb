require "test_helper"

# banco.item/1 case_sensitive (optional, default false) reaches Grading::Closed::Text (D-041).
class CaseSensitiveTest < ActiveSupport::TestCase
  ITEM = Rails.root.join("test/fixtures/content/item/good/normalized-text-static.json")

  def item(**extra) = JSON.parse(File.read(ITEM)).merge(extra.stringify_keys)

  def verdict(item_hash, raw)
    instance = item_hash["instances"].first
    spec = Grading::Spec.from_hash(item_hash.merge("answer" => "Na", "errors" => [], "display" => instance["display"]))
    Grading.grade_spec(spec, raw).verdict
  end

  test "the schema accepts the field and rejects a non-boolean" do
    assert_empty Banco::Schemas.validate("item", item(case_sensitive: true))
    assert_not_empty Banco::Schemas.validate("item", item(case_sensitive: "yes"))
  end

  test "default is case-insensitive" do
    assert_equal "correct", verdict(item, "NA")
    assert_equal "correct", verdict(item, "na")
  end

  test "true keeps case" do
    sensitive = item(case_sensitive: true)
    assert_equal "correct", verdict(sensitive, "Na")
    assert_not_equal "correct", verdict(sensitive, "NA")
    assert_not_equal "correct", verdict(sensitive, "na")
  end

  test "explicit false is the default" do
    assert_equal "correct", verdict(item(case_sensitive: false), "nA")
  end
end
