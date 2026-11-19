require "test_helper"

# The tree layout of flow (D-383): the way back (`loops`) is the one cycle a flow may have, from a node under a decision to that decision. The
# vectors (test/fixtures/diagrams/vectors.json, flow-loop-*) hold the refusals both implementations share; this file holds what only Ruby does.
class LessonsFlowTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(Rails.root.join("test/fixtures/diagrams/vectors.json").read).fetch("vectors")

  def vector(name) = Marshal.load(Marshal.dump(VECTORS.find { |v| v["name"] == name }.fetch("data")))

  def findings(data) = Lessons::Diagrams.check(data, subject: "math").map { |f| [ f.code, f.path ] }

  test "a Do While validates: the step that loops back has no edge, the question has its two branches" do
    assert_empty findings(vector("flow-loop-do-while"))
    assert_empty findings(vector("flow-loop-nested-two"))
    assert_empty findings(vector("flow-loop-long-question"))
  end

  test "the cap on loops is a rule and the schema says the same number" do
    cap = Validation::Rules.get(:lesson2, :flow_loops_max)
    assert_equal 2, cap
    assert_equal cap, Lessons::Diagrams.schema_def("flow").dig("properties", "loops", "maxItems")
    data = vector("flow-loop-do-while")
    data["loops"] = [ { "from" => "b", "to" => "q" }, { "from" => "b", "to" => "q" }, { "from" => "b", "to" => "q" } ]
    assert_includes findings(data), [ "E-LESSON-DIAGRAM", "/loops" ]
  end

  test "a loop goes back to a decision, from a node under it that is not an end" do
    data = vector("flow-loop-do-while")
    assert_includes findings(data.merge("loops" => [ { "from" => "b", "to" => "a" } ])), [ "E-LESSON-MAP", "/loops/0/to" ]
    assert_includes findings(data.merge("loops" => [ { "from" => "e", "to" => "q" } ])), [ "E-LESSON-MAP", "/loops/0/from" ]
    assert_includes findings(data.merge("loops" => [ { "from" => "a", "to" => "q" } ])), [ "E-LESSON-MAP", "/loops/0/from" ]
    assert_includes findings(data.merge("loops" => [ { "from" => "q", "to" => "q" } ])), [ "E-LESSON-MAP", "/loops/0/from" ]
    assert_includes findings(data.merge("loops" => [ { "from" => "zz", "to" => "q" } ])), [ "E-LESSON-MAP", "/loops/0" ]
  end

  test "the messages say what is wrong" do
    data = vector("flow-loop-do-while")
    message = ->(loops) { Lessons::Diagrams.check(data.merge("loops" => loops), subject: "math").map(&:message).join(" | ") }
    assert_match(/goes back to a decision.*a is a step/, message.call([ { "from" => "b", "to" => "a" } ]))
    assert_match(/does not start from an end node/, message.call([ { "from" => "e", "to" => "q" } ]))
    assert_match(/drawn under q: a cannot be reached from it/, message.call([ { "from" => "a", "to" => "q" } ]))
    assert_match(/written twice/, message.call([ { "from" => "b", "to" => "q" }, { "from" => "b", "to" => "q" } ]))
  end

  test "a step that loops back has no edge; a step with an edge and a loop leaves twice" do
    data = vector("flow-loop-do-while")
    assert_includes findings(data.merge("edges" => data["edges"] + [ %w[b e] ])), [ "E-LESSON-MAP", "/nodes/2" ]
    assert_includes findings(data.except("loops")), [ "E-LESSON-MAP", "/nodes/2" ], "without the loop the step leads nowhere"
  end

  test "the label of a loop follows the label word rules" do
    data = vector("flow-loop-do-while")
    data["loops"][0]["label_it"] = "si torna alla domanda di prima per un altro giro"
    assert_includes findings(data), [ "E-LESSON-DIAGRAM", "/loops/0/label_it" ]
  end

  test "cycles among the edges stay refused, and a line has returns, not loops" do
    data = vector("flow-loop-do-while")
    assert_includes findings(data.merge("edges" => data["edges"] + [ %w[b q] ])), [ "E-LESSON-MAP", "/edges/3" ]
    assert_includes findings(vector("flow-loop-on-a-line")), [ "E-LESSON-DIAGRAM", "/loops" ]
  end

  test "the loops are served and printed (the browser draws the label)" do
    data = vector("flow-loop-do-while")
    assert_equal data["loops"], Lessons::Diagrams::Flow.served(data)["loops"]
    assert_includes Lessons::Diagrams::Flow.printed(data, 0), "torna alla domanda"
  end
end
