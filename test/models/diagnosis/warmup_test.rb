require "test_helper"

# The warm-up (B-11): tasks, immediate "riprova", the editor fallback, completion.
class DiagnosisWarmupTest < ActiveSupport::TestCase
  W = Diagnosis::Warmup

  setup { @student = Student.create!(key: "student", kind: "student") }

  def right_answer(task)
    case task["component"]
    when "choice", "number", "normalized_text" then task["answer"].to_s
    when "fraction" then task["answer"].transform_values(&:to_s).to_json
    when "ordering" then task["answer"].to_json
    when "matching" then task["answer"].to_json
    when "dont_know" then Grading::DONT_KNOW_RAW
    when "pause" then "done"
    when "expression" then task["accept"].first
    end
  end

  test "there is one task per component, then pause, dont know and the editor tasks, and no multi-digit exponent" do
    components = W.tasks.map { |t| t["component"] }
    %w[choice number fraction ordering matching normalized_text dont_know pause expression].each { |c| assert_includes components, c }
    editor = W.tasks.select { |t| t["editor"] }
    assert_equal 7, editor.size
    editor.each { |t| refute_match(/\^\{?\d\d/, t["accept"].join(" ")) }
  end

  test "the browser's copy of the tasks carries no answers" do
    json = W.public_tasks.to_json
    refute_match(/"answer"|"accept"/, json)
    assert_includes json, "prompt_it"
  end

  test "every right answer is right, an empty or wrong one is not" do
    W.tasks.each do |task|
      assert W.right?(task, right_answer(task)), "#{task['id']} should accept its right answer"
      refute W.right?(task, ""), "#{task['id']} should not accept an empty answer"
    end
    refute W.right?(W.task("number"), "0.75"), "a dot is not the decimal comma"
    refute W.right?(W.task("accents"), "piu")
    assert W.right?(W.task("ed_power"), "x^2 + 3x")
    assert W.right?(W.task("ed_square"), '\left(a+b\right)^2')
  end

  test "a wrong answer says retry, a right one moves on, and nothing counts in a diagnosis" do
    assert_equal "retry", W.answer!(@student, "number", "0.75")
    assert_equal "right", W.answer!(@student, "number", "0,75")
    assert_equal [ "number" ], W.done_ids(@student)
    assert_equal 0, Attempt.count
    assert_equal %w[warmup_answer warmup_answer], AppEvent.order(:id).pluck(:kind)
  end

  test "the editor gives up after three tries and switches the student's expression items to text" do
    2.times { assert_equal "retry", W.answer!(@student, "ed_root", "nope") }
    refute W.fallback?(@student)
    assert_equal "skip", W.answer!(@student, "ed_root", "nope")
    assert W.fallback?(@student)
    assert_includes W.done_ids(@student), "ed_root"
  end

  test "a task that is not the editor's never gives up" do
    10.times { assert_equal "retry", W.answer!(@student, "fraction", "{}") }
    refute W.fallback?(@student)
  end

  test "completing needs every task, and writes warmup_completed once per round" do
    refute W.complete!(@student)
    W.tasks.each { |t| assert_equal "right", W.answer!(@student, t["id"], right_answer(t)) }
    assert W.complete!(@student)
    assert W.complete?(@student)
    assert_equal 1, AppEvent.where(kind: "warmup_completed").count
    assert_empty W.done_ids(@student), "a new round starts after the completion"
  end
end
