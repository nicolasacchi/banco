require "test_helper"

# Lessons::Diagrams against the shared vectors (test/fixtures/diagrams/vectors.json): the semantic column of every
# schema-valid vector, and the state overlay.
class LessonsDiagramsTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(Rails.root.join("test/fixtures/diagrams/vectors.json").read).fetch("vectors")

  VECTORS.select { |v| v["schema"] == "valid" }.each do |vec|
    test "semantic column: #{vec['name']}" do
      found = Lessons::Diagrams.check(vec["data"], subject: vec["subject"])
      if vec["semantic"] == "ok"
        assert_empty found.map(&:to_h), vec["name"]
      else
        assert found.any? { |f| f.code == vec["semantic"] && f.path == vec["path"] },
               "#{vec['name']}: expected #{vec['semantic']} at #{vec['path']}, got #{found.map { |f| [ f.code, f.path ] }.inspect}"
      end
    end
  end

  test "a state overlays the top level shallowly" do
    data = { "type" => "balance", "alt_it" => "x", "x_value" => "2", "left" => { "x" => 2, "units" => 3 }, "right" => { "units" => 7 },
             "states" => [ { "op_it" => "Partenza" }, { "left" => { "x" => 2 }, "right" => { "units" => 4 }, "op_it" => "Togli" } ] }
    merged = Lessons::Diagrams.merge_states(data)
    assert_equal({ "x" => 2, "units" => 3 }, merged["states"][0]["left"])
    assert_equal({ "x" => 2 }, merged["states"][1]["left"], "the whole left is replaced, not merged key by key")
    assert_equal "2", merged["states"][1]["x_value"], "a state inherits x_value"
    assert_equal "Partenza", merged["states"][0]["op_it"]
    assert_equal data, Lessons::Diagrams.merge_states(data.except("states")).merge("states" => data["states"]), "the input is not changed"
  end

  test "the solution fields come from the schema" do
    assert_equal [ "x_value" ], Lessons::Diagrams.solution_fields("balance")
    assert_empty Lessons::Diagrams.solution_fields("flow")
  end

  test "balance tilt is computed" do
    left = { "x" => 2, "units" => 3 }
    assert_equal 0, Lessons::Diagrams::Balance.tilt(left, { "units" => 7 }, 2r)
    assert_equal 1, Lessons::Diagrams::Balance.tilt(left, { "units" => 7 }, 3r)
    assert_equal(-1, Lessons::Diagrams::Balance.tilt({ "units" => 3 }, { "units" => 10 }, nil))
  end

  test "the lines of a cartesian plane" do
    c = Lessons::Diagrams::Cartesian
    assert_equal({ a: -2r, b: 1r, c: 1r }, c.line("y = 2x + 1"))
    assert_equal({ a: 1r, b: 0r, c: 3r }, c.line("x = 3"))
    assert_equal({ a: 1r, b: 1r, c: 7r }, c.line("x + y = 7"))
    assert_equal({ a: 1r / 2, b: 1r, c: 3r }, c.line("y = -1/2x + 3"))
    assert_nil c.line("y = x^2")
    assert_nil c.line("2x + 3 = y + 1")
    assert_nil c.line("y")
  end
end
