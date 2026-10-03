require "test_helper"
require_relative "../support/grading_rows"

# Grading::Expression: the persistent Node worker, and the rules that keep grading
# outside any database transaction (X-01).
class ExpressionGraderTest < ActiveSupport::TestCase
  include GradingRows

  def spec(item) = Grading::Spec.from_hash({ "component" => "expression" }.merge(item))

  teardown { Grading::Expression.shutdown }

  test "the worker answers a check and reports both versions" do
    result = Grading.grade_spec(spec("answer" => "2\\sqrt{2}", "form" => [ "radical_simplified" ]), "\\sqrt{8}")
    assert_equal "wrong_form", result.verdict
    assert_equal [ "radicand_not_reduced" ], result.form_violations
    assert_equal "exact", result.grading_method
    assert_equal "expression", result.grader
    assert_equal "0.146.0", result.ce_version
    assert_match(/\A[0-9a-f]{7,12}\+1\.0\.0\z|\Aunknown\+1\.0\.0\z/, result.grader_version)
    assert_equal "\\sqrt{8}", result.normalized
  end

  test "the same worker serves many requests" do
    worker = Grading::Expression.worker
    3.times { Grading.grade_spec(spec("answer" => "x+1"), "1+x") }
    assert_same worker, Grading::Expression.worker
    assert_predicate worker, :alive?
  end

  test "booting the application starts no worker" do
    out, status = Open3.capture2e({ "RAILS_ENV" => "test" }, Rails.root.join("bin/rails").to_s, "runner",
                                  "print Grading::Expression.instance_variable_get(:@workers).size",
                                  chdir: Rails.root.to_s)
    assert status.success?, out
    assert_equal "0", out.strip.lines.last
  end

  test "a worker restarts when it dies" do
    first = Grading::Expression.worker
    Grading.grade_spec(spec("answer" => "1"), "1")
    old_pid = first.pid
    Process.kill("KILL", old_pid)
    first.instance_variable_get(:@wait).join(5)

    result = Grading.grade_spec(spec("answer" => "1"), "1")
    assert_equal "correct", result.verdict
    assert_not_equal old_pid, first.pid
  end

  test "a worker that does not answer in time raises Unavailable and is replaced" do
    worker = Grading::Expression.worker
    Grading.grade_spec(spec("answer" => "1"), "1")
    stuck_pid = worker.pid
    Process.kill("STOP", stuck_pid)
    begin
      assert_raises(Grading::Expression::TimedOut) { Grading.grade_spec(spec("answer" => "1"), "1") }
    ensure
      Process.kill("CONT", stuck_pid) rescue nil # it was killed by the timeout already
    end
    assert_equal "correct", Grading.grade_spec(spec("answer" => "1"), "1").verdict
    assert_not_equal stuck_pid, worker.pid
  end

  test "a missing node binary is Unavailable, not a crash" do
    broken = Grading::Expression::Worker.new(node: "/nonexistent/node")
    assert_raises(Grading::Expression::Unavailable) { broken.request("op" => "ping") }
  end

  test "a forked process gets a different worker" do
    parent = Grading::Expression.worker
    Grading.grade_spec(spec("answer" => "1"), "1")
    parent_node = parent.pid
    reader, writer = IO.pipe

    child = fork do
      reader.close
      worker = Grading::Expression.worker
      result = Grading.grade_spec(spec("answer" => "1"), "1")
      writer.puts({ pid: worker.pid, verdict: result.verdict, same_object: worker.equal?(parent) }.to_json)
      Grading::Expression.shutdown
      writer.close
      exit!(0)
    end
    writer.close
    report = JSON.parse(reader.read)
    Process.wait(child)

    assert_equal "correct", report["verdict"]
    assert_not report["same_object"]
    assert_not_equal parent_node, report["pid"]
    assert_predicate parent, :alive?, "the child must not have killed the parent's worker"
    assert_equal "correct", Grading.grade_spec(spec("answer" => "1"), "1").verdict
  end

  test "no database transaction is open while the worker is asked" do
    seen = []
    probe = Object.new
    probe.define_singleton_method(:request) do |_payload|
      tx = ActiveRecord::Base.connection.current_transaction
      seen << [ tx.joinable?, ActiveRecord::Base.connection.open_transactions ]
      { "verdict" => "correct", "method" => "exact", "checker_version" => "1.0.0", "ce_version" => "0.146.0" }
    end
    baseline = ActiveRecord::Base.connection.open_transactions

    Grading::Expression.stub(:worker, probe) { Grading.grade_spec(spec("answer" => "1"), "1") }

    assert_equal [ [ false, baseline ] ], seen, "grading ran inside a joinable transaction"
  end

  test "grading inside a transaction is refused before the worker is touched" do
    asked = false
    probe = Object.new
    probe.define_singleton_method(:request) { |_p| asked = true }

    Grading::Expression.stub(:worker, probe) do
      ActiveRecord::Base.transaction do
        assert_raises(Grading::TransactionOpen) { Grading.grade_spec(spec("answer" => "1"), "1") }
      end
    end
    assert_not asked
  end

  test "closed components are refused inside a transaction too" do
    ActiveRecord::Base.transaction do
      assert_raises(Grading::TransactionOpen) do
        Grading.grade_spec(Grading::Spec.from_hash("component" => "number", "answer" => 1), "1")
      end
    end
  end

  test "an expression item whose key cannot be read is undetermined, not the student's mistake" do
    result = Grading.grade_spec(spec("answer" => "\\frac{"), "1")
    assert_equal "undetermined", result.verdict
    assert_equal "item_broken", result.reason
  end

  test "problems lists the faults of an item's own key" do
    ok = Grading::Expression.problems(spec("answer" => "x+1", "errors" => [ { "code" => "e", "value" => "x+2" } ]))
    assert_empty ok
    collides = Grading::Expression.problems(spec("answer" => "x+1", "errors" => [ { "code" => "e", "value" => "1+x" } ]))
    assert_includes collides, "error_equals_expected:e"
  end

  test "a stored expression instance is graded from the rows" do
    body = item_body("number-generator").merge("component" => "expression", "form" => [ "radical_simplified" ])
    instance = create_instance(body, "display" => {}, "answer" => "2\\sqrt{2}", "errors" => [])
    assert_equal "wrong_form", Grading.grade(instance, "\\sqrt{8}", source: "mathlive").verdict
  end

  test "the stored question-to-answer path: a Spanish accent slip is never correct" do
    body = item_body("normalized-text-static").merge("accent_policy" => "flag", "paradigm_forms" => [ "está", "estás" ])
    instance = create_instance(body, "display" => {}, "answer" => "está", "errors" => [])
    result = Grading.grade(instance, "esta")
    assert_not_equal "correct", result.verdict
    assert_equal [ "es_accents" ], result.error_codes
  end
end
