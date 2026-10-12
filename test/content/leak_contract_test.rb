require "test_helper"
require_relative "../support/lesson2_fixtures"

# W2-0 review: the leak annotations of the schemas (x-banco-solution, x-banco-hide, x-banco-withheld) and the whitelist
# (test/fixtures/lesson2/whitelist.json) say the same things. The schema is machine-readable (booleans and path lists); the whitelist
# repeats the paths so a reader of one sees the other, and this test fails when they drift.
class LeakContractTest < ActiveSupport::TestCase
  WL = JSON.parse(Rails.root.join("test/fixtures/lesson2/whitelist.json").read)
  DIAGRAM = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).fetch("$defs")
  LESSON = JSON.parse(Rails.root.join("config/banco/schemas/lesson.json").read).fetch("$defs")

  def solution_of(defn) = (defn["properties"] || {}).select { |_, p| p.is_a?(Hash) && p["x-banco-solution"] }.keys

  test "every diagram type declares its hidden paths as a list of paths, the same in the schema and in the whitelist" do
    WL["diagram"]["types"].each do |name, row|
      defn = DIAGRAM.fetch(name)
      schema_hide = defn["x-banco-hide"]
      refute_kind_of String, schema_hide, "#{name}: x-banco-hide is a list of paths, not prose"
      refute_kind_of String, row["hide"], "#{name}: whitelist hide is a list of paths, not prose"
      assert_equal Array(schema_hide), Array(row["hide"]), "#{name}: hide paths differ between diagram.json and whitelist.json"
      Array(schema_hide).each { |path| assert_match(/\A[a-z_]+(\[\])?(\.[a-z_]+(\[\])?)*\z/, path, "#{name}: #{path}") }
    end
  end

  test "every diagram type declares its solution fields in both places" do
    WL["diagram"]["types"].each do |name, row|
      assert_equal solution_of(DIAGRAM.fetch(name)), Array(row["solution"]), "#{name}: solution fields differ"
    end
    expected = WL["diagram"]["types"].each_with_object({}) { |(n, r), h| h[n] = r["solution"] if r["solution"] }
    assert_equal expected, WL["diagram"]["solution_fields"]
  end

  test "no schema type with a hide or solution annotation is missing from the whitelist" do
    annotated = DIAGRAM.select { |_, d| d.is_a?(Hash) && (d.key?("x-banco-hide") || solution_of(d).any?) }.keys
    assert_empty annotated - WL["diagram"]["types"].keys
  end

  test "every withheld field of a block is listed in the whitelist and the other way round" do
    WL["blocks"].each do |name, row|
      defn = LESSON.fetch(row["def"])
      schema = (defn["properties"] || {}).select { |_, p| p.is_a?(Hash) && p["x-banco-withheld"] }.keys
      assert_equal schema, Array(row["withheld"]), "#{name}: withheld fields differ"
      assert_empty schema - row["drop"], "#{name}: a withheld field is dropped from the student's page"
    end
  end
end
