require "test_helper"
require "rake"
require "tempfile"
require_relative "../../support/grading_review_world"

# D-368: every `resolve_attempt` that made an answer right is a candidate grading vector (the shape of test/fixtures/grading/vectors.json), printed by
# `bin/rails banco:grading:vectors` for the operator to paste. Print only: nothing is written.
class TeacherGradingVectorsTest < ActiveSupport::TestCase
  include GradingReviewWorld

  setup { build_grading_review_world }

  def cases(file: nil) = (file ? Teacher::GradingVectors.new(@official, file: file) : Teacher::GradingVectors.new(@official)).cases

  def grade(vector)
    spec = Grading::Spec.from_hash(vector["item"].merge("component" => vector["component"]))
    Grading.grade_spec(spec, vector["raw"], source: vector["source"] || "mathlive")
  end

  test "one case for each correction that made an answer right: the practice try and the entry-test answer" do
    list = cases
    assert_equal [ "resolved-practice-#{@resolved_try.id}", "resolved-diagnosis-#{@diag_resolved.id}" ], list.map { |c| c["id"] }

    practice, diagnosis = list
    assert_equal %w[id component raw item expect], practice.keys
    assert_equal [ "normalized_text", "play", { "verdict" => "correct" } ], practice.values_at("component", "raw", "expect")
    assert_equal({ "subject" => "math", "skill" => SKILL, "answer" => "don't eat", "errors" => [ { "code" => "does_eat", "value" => "doesn't eat" } ],
                   "display" => { "stem_it" => SENTENCE_STEM } }, practice["item"])
    assert_equal [ "normalized_text", "1 mela", { "verdict" => "correct" } ], diagnosis.values_at("component", "raw", "expect")
    assert_equal({ "subject" => "math", "skill" => SKILL, "answer" => "1", "display" => { "stem_it" => "diag-text-1 0" } }, diagnosis["item"])
  end

  test "each case is a vector the grader fails today: the verdict the teacher gave is not the one it gives" do
    cases.each do |vector|
      assert_equal "correct", vector["expect"]["verdict"]
      assert_equal "wrong", grade(vector).verdict, vector["id"]
    end
  end

  test "a correction to wrong makes no vector, and neither does another student's correction" do
    decide = lambda do |attempt, verdict, student|
      Decision.create!(kind: "resolve_attempt", subject: @subject, student: student, request_id: SecureRandom.hex(4), teacher_login: "nik", remote_addr: "127.0.0.1",
                       payload_json: JSON.generate(attempt_id: attempt.id, attempt_kind: "practice", practice_serve_id: attempt.practice_serve_id, try_number: 1,
                                                   verdict: verdict, reason_it: "No."))
    end
    decide.call(@plain_try, "wrong", @official)
    decide.call(@near_try, "correct", @trial)
    assert_equal 2, cases.size
    assert_empty Teacher::GradingVectors.new(@trial).cases
  end

  test "a vector already in the file, by id, is left out" do
    Tempfile.create([ "vectors", ".json" ]) do |file|
      file.write(JSON.generate(cases: [ { id: "resolved-practice-#{@resolved_try.id}" } ]))
      file.flush
      assert_equal [ "resolved-diagnosis-#{@diag_resolved.id}" ], cases(file: file.path).map { |c| c["id"] }
    end
  end

  test "the case is made of the shared file's own fields, and none of its ids is taken" do
    shared = JSON.parse(File.read(Rails.root.join("test/fixtures/grading/vectors.json")))["cases"]
    assert_empty cases.map { |c| c["id"] } & shared.map { |c| c["id"] }
    assert_empty cases.flat_map(&:keys).uniq - (shared.flat_map(&:keys).uniq | %w[source])
  end

  test "choice and ordering answers come back to the instance's own ids and structured answers are JSON values" do
    vectors = Teacher::GradingVectors.new(@official)
    canonical = ->(component, raw, map) { vectors.send(:canonical, component, raw, map) }
    assert_equal "o2", canonical.call("choice", "x9", JSON.generate("x9" => "o2"))
    assert_equal %w[e2 e1], canonical.call("ordering", JSON.generate(%w[b a]), JSON.generate("a" => "e1", "b" => "e2"))
    assert_equal({ "l1" => "r2" }, canonical.call("matching", JSON.generate("p" => "q"), JSON.generate("p" => "l1", "q" => "r2")))
    assert_equal({ "n" => 3, "d" => 4 }, canonical.call("fraction", JSON.generate("n" => 3, "d" => 4), nil))
    assert_equal "42", canonical.call("number", "42", nil)
    assert_equal "3/4", canonical.call("fraction", "3/4", nil)
  end

  # ---- the console task ------------------------------------------------------------------------------------------------

  def vectors_task(env = {})
    saved = ENV.to_h.slice("STUDENT")
    Rails.application.load_tasks unless Rake::Task.task_defined?("banco:grading:vectors")
    ENV.delete("STUDENT")
    env.each { |k, v| ENV[k] = v }
    capture_io { Rake::Task["banco:grading:vectors"].reenable; Rake::Task["banco:grading:vectors"].invoke }
  ensure
    saved.key?("STUDENT") ? ENV["STUDENT"] = saved["STUDENT"] : ENV.delete("STUDENT")
  end

  test "banco:grading:vectors prints the cases as JSON and writes nothing" do
    path = Rails.root.join("test/fixtures/grading/vectors.json")
    before = File.read(path)
    counts = [ Decision, PracticeAttempt, Attempt ].map(&:count)
    out, err = vectors_task
    assert_equal [ "resolved-practice-#{@resolved_try.id}", "resolved-diagnosis-#{@diag_resolved.id}" ], JSON.parse(out).map { |c| c["id"] }
    assert_includes err, "2 candidate vector(s)"
    assert_equal before, File.read(path)
    assert_equal counts, [ Decision, PracticeAttempt, Attempt ].map(&:count)
  end

  test "banco:grading:vectors for a student that has none prints an empty list, and an unknown student aborts" do
    out, = vectors_task("STUDENT" => "prova-1")
    assert_equal [], JSON.parse(out)
    assert_raises(SystemExit) { vectors_task("STUDENT" => "nobody-1") }
  end
end
