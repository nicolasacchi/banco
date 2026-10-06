require "test_helper"

# Diagnosis::Rules::V1 holds the numbers of docs/rules/diagnosis-1.md.
class RulesV1Test < ActiveSupport::TestCase
  V1 = Diagnosis::Rules::V1

  test "operator decisions: Q10 near-miss defaults, Q11 second sitting, days, calculator" do
    assert_equal :pending, V1::NEAR_MISS
    assert_equal :credit, V1::WRONG_FORM_DECLARED
    assert_equal :credit, V1::ORTHOGRAPHY_SLIP
    assert_equal 2, V1::SITTINGS_PER_SUBJECT
    assert V1::AUTO_SECOND_SITTING
    assert_equal 2, V1::DAILY_MAX_SUBJECTS
    assert_equal 75, V1::DAILY_MAX_MINUTES
    assert_equal :no, V1.calculator("math")
    assert_equal :yes, V1.calculator("business")
    assert_equal :yes, V1.calculator("chemistry")
    assert_equal :no, V1.calculator("history")
  end

  test "time budget: 30 minutes for mathematics, 25 for the others, up to 60 and 50 in total" do
    assert_equal 30, V1.sitting_budget_minutes("math")
    assert_equal 25, V1.sitting_budget_minutes("english")
    assert_equal 60, V1.subject_budget_minutes("math")
    assert_equal 50, V1.subject_budget_minutes("biology")
    assert_equal 7, V1::OPEN_RESERVE_MINUTES
    assert_equal 30, V1::MAX_ITEMS_PER_SITTING
    assert_equal 600, V1::ITEM_CAP_SECONDS
    assert_equal 1200, V1::TESTLET_CAP_SECONDS
    assert_equal 1800, V1::ABANDON_GAP_SECONDS
  end

  test "two first sittings fit in the daily safety ceiling" do
    assert_operator V1.sitting_budget_minutes("math") + V1.sitting_budget_minutes("italian"), :<=, 55
    assert_operator 55, :<=, V1::DAILY_MAX_MINUTES
  end

  test "evidence table: certain and uncertain verdicts" do
    assert_equal :C, V1.evidence("correct")
    assert_equal :W, V1.evidence("typical_error")
    assert_equal :W, V1.evidence("wrong")
    assert_equal :D, V1.evidence("dont_know")
    assert_equal :pending, V1.evidence("near_miss")
    assert_equal :pending, V1.evidence("undetermined")
    assert_equal :pending, V1.evidence("short_answer")
    assert_equal :ungraded, V1.evidence("ungraded")
    assert_equal :none, V1.evidence("invalid")
  end

  test "evidence table: wrong forms and orthography slips" do
    assert_equal :W, V1.evidence("wrong_form", form: :skill)
    assert_equal :C, V1.evidence("wrong_form", form: :declared)
    assert_equal :pending, V1.evidence("wrong_form")
    assert_equal :pending, V1.evidence("wrong_form", form: :undeclared)
    assert_equal :C, V1.evidence("typical_error", orthography_slip: true)
    assert_equal :W, V1.evidence("typical_error")
  end

  test "the three case constants only take credit or pending" do
    [ V1::NEAR_MISS, V1::WRONG_FORM_DECLARED, V1::ORTHOGRAPHY_SLIP ].each { |c| assert_includes V1::OPTIONS_FOR_CASES, c }
  end

  test "states, reasons and end reasons of B-03 and B-04" do
    assert_equal %w[demonstrated to_recover not_assessed pending], V1::STATES
    assert_equal V1::STATES, V1::REASONS.keys
    assert_equal %w[frontier_empty time_budget item_cap teacher_close], V1::END_REASONS
    assert_includes V1::REASONS["demonstrated"], "two_of_two_choice"
    assert_includes V1::REASONS["not_assessed"], "prerequisite_to_recover"
    assert_includes V1::REASONS["pending"], "grader_unavailable"
    assert_equal V1::REASONS.values.flatten.size, V1::REASONS.values.flatten.uniq.size
  end

  test "recover or learn follows the scope, middle_school is recover, an override wins" do
    assert_equal "learn", V1.kind_for("in_progress")
    assert_equal "learn", V1.kind_for("not_in_prima")
    %w[studied integration_studied middle_school].each { |s| assert_equal "recover", V1.kind_for(s) }
    assert_equal "recover", V1.kind_for("not_in_prima", "recover")
    assert_equal V1::SCOPES.sort, JSON.parse(File.read(Rails.root.join("config/banco/schemas/skill_graph.json")))
                                       .dig("properties", "skills", "items", "properties", "scope", "enum").sort
  end

  test "low-guess components for the first item" do
    %w[number fraction expression normalized_text].each { |c| assert V1.low_guess?(c), c }
    assert V1.low_guess?("ordering", size: 4)
    assert_not V1.low_guess?("ordering", size: 3)
    assert V1.low_guess?("matching", size: 4)
    assert_not V1.low_guess?("matching", size: 3)
    assert_not V1.low_guess?("choice")
  end

  test "discursive subjects are the seven of B-06 and all subjects match the schema enum" do
    assert_equal 7, V1::DISCURSIVE_SUBJECTS.size
    assert_empty V1::DISCURSIVE_SUBJECTS - V1::SUBJECTS
    assert_equal 11, V1::SUBJECTS.size
    assert_equal V1::SUBJECTS.sort, V1::INVENTORY_PREFIXES.values.sort
  end

  test "the rules note names every constant it relies on" do
    note = File.read(Rails.root.join("docs/rules/diagnosis-1.md"))
    %w[NEAR_MISS WRONG_FORM_DECLARED ORTHOGRAPHY_SLIP ORTHOGRAPHY_ALLOWLIST EVIDENCE END_REASONS SITTING_BUDGET_MINUTES
       OPEN_RESERVE_MINUTES MAX_ITEMS_PER_SITTING SITTINGS_PER_SUBJECT AUTO_SECOND_SITTING ABANDON_GAP_SECONDS
       DAILY_MAX_SUBJECTS DAILY_MAX_MINUTES CALCULATOR ITEM_CAP_SECONDS TESTLET_CAP_SECONDS MAX_SERVED_PER_SKILL].each do |const|
      assert_includes note, const, "docs/rules/diagnosis-1.md should mention #{const}"
      assert V1.const_defined?(const), "Rules::V1::#{const} should exist"
    end
  end

  test "testlet_flags decides per skill from the sub items" do
    body = { "sub_items" => [ { "id" => "a", "skill" => "x.a", "component" => "choice" }, { "id" => "b", "skill" => "x.a", "component" => "choice" },
                              { "id" => "c", "skill" => "x.b", "component" => "number" }, { "id" => "d", "skill" => "x.b", "component" => "choice" },
                              { "id" => "e", "skill" => "x.c", "component" => "ordering" } ] }
    display = { "sub_items" => [ { "id" => "e", "display" => { "elements" => [ 1, 2, 3, 4 ] } } ] }
    f = V1.testlet_flags(body, display)
    assert_equal({ low_guess: false, choice: true }, f["x.a"])
    assert_equal({ low_guess: true, choice: false }, f["x.b"])
    assert_equal({ low_guess: true, choice: false }, f["x.c"])
  end
end
