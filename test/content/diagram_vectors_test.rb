require "test_helper"

# D-247: test/fixtures/diagrams/vectors.json is the contract between the schema, the Ruby checks
# (Lessons::Diagrams, R1) and the browser layout (app/javascript/lesson/diagrams, R2). R0 runs the
# schema column and the shape of the file; the semantic column is run by R1, the layout by R2.
class DiagramVectorsTest < ActiveSupport::TestCase
  FILE = Rails.root.join("test/fixtures/diagrams/vectors.json")
  VECTORS = JSON.parse(FILE.read).fetch("vectors")
  PALETTE = YAML.safe_load_file(Rails.root.join("config/banco/lesson_palette.yml"))
  TYPES = %w[equation_parts number_line balance area_model cartesian sentence concept_map flow table].freeze

  def roles_of(subject) = (PALETTE.fetch("common").keys + PALETTE.fetch(subject).fetch("roles").keys)

  test "the schema column holds for every vector, with a pointer for the refused ones" do
    VECTORS.each do |vec|
      errors = Banco::Schemas.validate("diagram", vec["data"])
      if vec["schema"] == "valid"
        assert_empty errors.map(&:to_h), "#{vec['name']} should pass the schema"
      else
        assert_not_empty errors, "#{vec['name']} should be refused by the schema"
        assert(errors.all? { |e| e.code == "E-SCHEMA" })
      end
    end
  end

  test "names are unique and every entry is well formed" do
    assert_equal VECTORS.size, VECTORS.map { |v| v["name"] }.uniq.size
    VECTORS.each do |vec|
      assert_includes %w[valid invalid], vec["schema"], vec["name"]
      assert_includes %w[math italian], vec["subject"], vec["name"]
      if vec["schema"] == "invalid"
        assert_equal "ok", vec["semantic"], "#{vec['name']}: the semantic column only judges data the schema accepts"
      elsif vec["semantic"] != "ok"
        assert_match(/\AE-/, vec["semantic"], vec["name"])
        assert_match(%r{\A/}, vec["path"], "#{vec['name']} names the JSON pointer of the finding")
      end
    end
  end

  test "every release 1 type has vectors that pass and vectors that are refused, both ways" do
    TYPES.each do |type|
      mine = VECTORS.select { |v| v["data"]["type"] == type }
      assert(mine.any? { |v| v["schema"] == "valid" && v["semantic"] == "ok" }, "#{type}: a good vector")
      assert(mine.any? { |v| v["schema"] == "invalid" } || mine.any? { |v| v["semantic"] != "ok" }, "#{type}: a refused vector")
    end
    assert(VECTORS.any? { |v| v["schema"] == "invalid" && v["data"]["type"] == "venn" }, "a type of a later release is refused")
  end

  test "the state rule: top-level keys in a state are refused, inherited ones are accepted" do
    names = VECTORS.to_h { |v| [ v["name"], v ] }
    assert_equal "valid", names.fetch("balance-states-equivalent-inherit-x-value")["schema"]
    assert_equal "invalid", names.fetch("balance-state-carries-alt-it")["schema"]
    assert_equal "invalid", names.fetch("balance-state-carries-x-value")["schema"]
    assert_equal "invalid", names.fetch("sentence-state-carries-layout")["schema"]
    assert_equal "valid", names.fetch("balance-states-equivalent-inherit-x-value")["data"]["states"][1].key?("left") ? "valid" : "invalid"
  end

  test "the roles of the good vectors are roles of their subject's palette" do
    VECTORS.select { |v| v["schema"] == "valid" && v["semantic"] == "ok" }.each do |vec|
      found = []
      walk = lambda do |node|
        case node
        when Hash then node.each { |k, val| found << val if k == "role" && val.is_a?(String); walk.call(val) }
        when Array then node.each { |val| walk.call(val) }
        end
      end
      walk.call(vec["data"])
      assert_empty found - roles_of(vec["subject"]), "#{vec['name']}: roles outside the palette"
    end
  end
end
