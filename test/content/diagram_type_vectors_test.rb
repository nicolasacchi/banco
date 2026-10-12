require "test_helper"

# W2-0: the per-type vector files of test/fixtures/diagrams/types (WAVE2 1.2: "vectors in test/fixtures/diagrams/types/TYPE.json, the 106
# release-1 vectors stay in vectors.json"). A skeleton holds, for each type with a schema, the plan's example and a refused case; the track
# of the type fills the semantic, layout and select columns. Both implementations run the schema column: this test in Ruby (json_schemer),
# app/javascript/lesson/test/type_vectors.test.mjs in the browser's compiled schema.
class DiagramTypeVectorsTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/diagrams/types")
  TYPES = Lessons::Types.data.fetch("diagrams").select { |name, e| e["family"] != "core" && e["schema"] != "none" }.keys.freeze
  FILES = TYPES.to_h { |t| [ t, JSON.parse(DIR.join("#{t}.json").read) ] }.freeze

  test "every type of wave 2 with a schema has its file, and nothing else is in the directory" do
    assert_equal TYPES.map { |t| "#{t}.json" }.sort, Dir.children(DIR).sort
    assert_equal 26, TYPES.size
  end

  test "each file says the status, batch and track of the registry, and has a case that passes the schema and one refused" do
    FILES.each do |type, doc|
      entry = Lessons::Types.entry(:diagram, type)
      assert_equal type, doc["type"]
      assert_equal entry["status"], doc["status"], type
      assert_equal entry["batch"], doc["batch"], type
      assert_equal entry["track"], doc["track"], type
      assert_equal entry["status"] == "draft", doc["provisional"], type
      names = doc["vectors"].map { |v| v["name"] }
      assert_equal names.uniq, names, type
      assert(doc["vectors"].any? { |v| v["schema"] == "valid" }, "#{type}: a case the schema accepts")
      assert(doc["vectors"].any? { |v| v["schema"] == "invalid" }, "#{type}: a case the schema refuses")
    end
  end

  test "the schema column holds for every case, valid or refused with E-SCHEMA" do
    FILES.each_value do |doc|
      doc["vectors"].each do |v|
        errors = Banco::Schemas.validate("diagram", v["data"])
        if v["schema"] == "valid"
          assert_empty errors.map(&:to_h), "#{v['name']} should pass the schema"
        else
          assert_not_empty errors, "#{v['name']} should be refused by the schema"
        end
      end
    end
  end

  test "roles in the cases are roles of their subject's palette, and an available type has no pending column" do
    FILES.each do |type, doc|
      doc["vectors"].select { |v| v["schema"] == "valid" }.each do |v|
        roles = []
        walk = ->(x) { x.is_a?(Hash) ? x.each { |k, val| (roles << val if k == "role" && val.is_a?(String)) || walk.call(val) } : (x.is_a?(Array) && x.each { |i| walk.call(i) }) }
        walk.call(v["data"])
        assert_empty roles - Lessons::Palette.roles(v["subject"]).keys - Lessons::Palette.roles(Lessons::Types.home_palette(type) || v["subject"]).keys, "#{v['name']}: roles of #{v['subject']}"
      end
      next unless Lessons::Types.available?(:diagram, type)

      assert(doc["vectors"].none? { |v| v["semantic"] == "pending" || v["layout"] == "pending" }, "#{type} is available: its pending columns are filled")
    end
  end

  test "the home palette of a type is the same in the schema and in the registry" do
    schema = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).fetch("$defs")
    Lessons::Types.data.fetch("diagrams").each do |type, entry|
      next if entry["schema"] == "none"

      home = schema.fetch(type)["x-banco-home-palette"]
      entry["home_palette"] ? assert_equal(entry["home_palette"], home, type) : assert_nil(home, type)
    end
  end
end
