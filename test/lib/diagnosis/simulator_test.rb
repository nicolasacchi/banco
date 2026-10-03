require "test_helper"
require_relative "../../support/diagnosis_helper"

# The simulator and the scripted student: the same engine, no database. The
# three-skill fixture is the one `banco diagnosis simulate` is verified with.
class DiagnosisSimulatorTest < ActiveSupport::TestCase
  include DiagnosisHelper

  FIXTURE = Rails.root.join("test/fixtures/blueprints/three-skill.json")

  def fixture_plan
    doc = JSON.parse(File.read(FIXTURE))
    Diagnosis::Plan.build(blueprint: doc["blueprint"], graph: doc["graph"])
  end

  def run_script(script)
    Diagnosis::Simulator.run(fixture_plan, Diagnosis::ScriptedStudent.new(script))
  end

  test "all-wrong ends with frontier_empty and every skill to_recover" do
    out = run_script("all-wrong")
    assert_equal "frontier_empty", out[:result][:end_reason]
    assert_equal %w[to_recover], out[:result][:skills].map { |s| s[:state] }.uniq
    assert_equal 6, out[:result][:served]
  end

  test "all-correct demonstrates the top skill and the rest sits below it" do
    out = run_script("all-correct")
    states = out[:result][:skills].to_h { |s| [ s[:skill], [ s[:state], s[:reason] ] ] }
    assert_equal %w[demonstrated two_of_two], states["math.linear-equation-integer"]
    assert_equal %w[not_assessed below_demonstrated], states["math.fractions-operations"]
    assert_equal "frontier_empty", out[:result][:end_reason]
  end

  test "mixed asks a third item and is demonstrated by it" do
    out = run_script("mixed")
    assert_equal %w[demonstrated two_of_three],
                 out[:result][:skills].find { |s| s[:skill] == "math.linear-equation-integer" }.values_at(:state, :reason)
  end

  test "a script file: rules by skill and nth item, seconds, typical errors" do
    script = { "default" => { "verdict" => "correct" }, "seconds" => 20,
               "rules" => [ { "skill" => "math.linear-equation-integer", "verdict" => "typical_error", "error_code" => "none_in_catalogue" } ] }
    out = run_script(script)
    # Unknown code: unclassified, so the descent goes to the direct prerequisite.
    assert_equal %w[to_recover two_wrong],
                 out[:result][:skills].find { |s| s[:skill] == "math.linear-equation-integer" }.values_at(:state, :reason)
    assert_equal out[:result][:served] * 20, out[:result][:counted_seconds]
  end

  test "an unknown script name is refused" do
    assert_raises(Diagnosis::ScriptedStudent::UnknownScript) { Diagnosis::ScriptedStudent.new("all-maybe") }
  end

  test "the trace is plain data with ISO times, no key to any answer" do
    out = run_script("all-wrong")
    row = out[:trace].find { |t| t[:kind] == "item_served" }
    assert_match(/\A\d{4}-\d\d-\d\dT/, row[:at])
    assert_empty out[:trace].flat_map(&:keys) & %i[answer solution key]
  end

  test "simulate is a pure dry run: it makes no database writes" do
    tables = ActiveRecord::Base.connection.tables - %w[schema_migrations ar_internal_metadata]
    before = tables.sum { |t| ActiveRecord::Base.connection.select_value("SELECT count(*) FROM #{t}") }
    run_script("all-wrong")
    after = tables.sum { |t| ActiveRecord::Base.connection.select_value("SELECT count(*) FROM #{t}") }
    assert_equal before, after
  end

  test "a bare blueprint (no graph) simulates as a flat subject" do
    doc = JSON.parse(File.read(FIXTURE))["blueprint"]
    plan = Diagnosis::Plan.build(blueprint: doc)
    out = Diagnosis::Simulator.run(plan, Diagnosis::ScriptedStudent.new("all-wrong"))
    assert_equal 6, out[:result][:served]
    assert_equal "frontier_empty", out[:result][:end_reason]
  end

  test "short answer in a script: confirm_short settles it" do
    base = build_plan(skills: { "math.a" => {}, "math.s" => {} }, entries: [ "math.a" ])
    plan = with_instances(base, [ instance("sa#1", skills: [ "math.s" ], kind: "short_answer", component: "short_answer") ])
    open = Diagnosis::Simulator.run(plan, Diagnosis::ScriptedStudent.new("all-correct"))
    assert_equal %w[pending grade_unconfirmed], open[:result][:skills].find { |s| s[:skill] == "math.s" }.values_at(:state, :reason)
    confirmed = Diagnosis::Simulator.run(plan, Diagnosis::ScriptedStudent.new({ "default" => { "verdict" => "correct" }, "confirm_short" => true }))
    assert_equal %w[demonstrated short_answer_above_threshold],
                 confirmed[:result][:skills].find { |s| s[:skill] == "math.s" }.values_at(:state, :reason)
  end

  test "the fixture blueprint is a valid banco.blueprint/1 apart from the entry count" do
    doc = JSON.parse(File.read(FIXTURE))["blueprint"]
    errors = Banco::Schemas.validate("blueprint", doc)
    assert_equal [ "/entries" ], errors.map(&:field).uniq, errors.map(&:to_h).inspect
  end
end
