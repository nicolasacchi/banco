require "test_helper"
require_relative "../support/student_ui_rows"

# A testlet is one attempt: its raw answer is a JSON object of the raw answers of
# its sub items, and the unit settles only when that is certain (D-047).
class TestletGradingTest < ActiveSupport::TestCase
  include StudentUiRows

  setup do
    rows = build_ui_subject(components: %w[testlet])
    @instance = rows[:revisions]["testlet"].instances.order(:id).first
    @key = JSON.parse(@instance.answer_json) # {"q1"=>"o2", ...}
  end

  def raw(overrides = {})
    @key.merge(overrides).to_json
  end

  def verdict(raw_text, id_map: nil) = Grading.grade(@instance, raw_text, id_map: id_map)

  test "every sub item right is correct" do
    assert_equal "correct", verdict(raw).verdict
  end

  test "every sub item wrong or given up is wrong, all given up is dont_know" do
    wrong = @key.transform_values { |id| id == "o1" ? "o2" : "o1" }
    assert_equal "wrong", verdict(wrong.to_json).verdict
    assert_equal "dont_know", verdict(@key.transform_values { Grading::DONT_KNOW_RAW }.to_json).verdict
    mixed_with_dont_know = wrong.merge("q1" => Grading::DONT_KNOW_RAW)
    assert_equal "wrong", verdict(mixed_with_dont_know.to_json).verdict
  end

  test "a mixture goes to the teacher: undetermined counts neither way" do
    one_wrong = raw("q3" => (@key["q3"] == "o1" ? "o2" : "o1"))
    result = verdict(one_wrong)
    assert_equal "undetermined", result.verdict
    assert_equal({ "q3" => "wrong" }, JSON.parse(result.normalized)["sub_verdicts"].select { |_k, v| v != "correct" })
  end

  test "a sub item missing or unreadable makes the whole answer invalid" do
    assert verdict(@key.except("q2").to_json).invalid?
    assert verdict(raw("q1" => "")).invalid?
    assert verdict("not json").invalid?
  end

  test "the serve layer's shuffle is undone per sub item" do
    # Shown ids are o1..o4 in a shuffled order: the map says which stored id each is.
    map = (1..5).to_h { |n| [ "q#{n}", { "o1" => "o2", "o2" => "o1", "o3" => "o3", "o4" => "o4" } ] }
    shown = @key.transform_values { |id| map.values.first.key(id) }
    assert_equal "correct", verdict(shown.to_json, id_map: map).verdict
  end

  test "an all-wrong unit carries the typical error codes of its sub items (D-112)" do
    spec = Struct.new(:sub_specs).new({ "a" => :a, "b" => :b, "c" => :c })
    outcomes = { a: Grading::Result.new(verdict: "typical_error", grader: "closed", error_codes: [ "en_wrong_referent" ]),
                 b: Grading::Result.new(verdict: "wrong", grader: "closed"),
                 c: Grading::Result.new(verdict: "typical_error", grader: "closed", error_codes: [ "en_wrong_referent", "en_x" ]) }
    stub = ->(sub, *_a, **_k) { outcomes.fetch(sub) }
    Grading.stub(:grade_spec, stub) do
      result = Grading::Testlet.grade(spec, { "a" => "1", "b" => "1", "c" => "1" })
      assert_equal "typical_error", result.verdict
      assert_equal %w[en_wrong_referent en_x], result.error_codes
      outcomes[:b] = Grading::Result.new(verdict: "correct", grader: "closed")
      mixed = Grading::Testlet.grade(spec, { "a" => "1", "b" => "1", "c" => "1" })
      assert_equal "undetermined", mixed.verdict
      assert_empty mixed.error_codes
    end
  end
end
