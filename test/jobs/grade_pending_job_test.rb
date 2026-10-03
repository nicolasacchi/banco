require "test_helper"
require_relative "../support/grading_rows"

# A worker failure writes nothing; GradePendingJob retries at 30 s, 2 min, 10 min
# and then leaves the attempt to the teacher (A-01, X-03).
class GradePendingJobTest < ActiveSupport::TestCase
  include GradingRows
  include ActiveJob::TestHelper

  setup do
    body = item_body("number-generator").merge("component" => "expression", "form" => [ "radical_simplified" ])
    @instance = create_instance(body, "display" => {}, "answer" => "2\\sqrt{2}", "errors" => [])
    @attempt = create_attempt(@instance, "\\sqrt{8}", source: "mathlive")
  end

  teardown { Grading::Expression.shutdown }

  def failing_worker
    Object.new.tap { |w| w.define_singleton_method(:request) { |_p| raise Grading::Expression::TimedOut, "slow" } }
  end

  test "the retry schedule is 30 s, 2 min, 10 min" do
    assert_equal [ 30.seconds, 2.minutes, 10.minutes ], Grading::Recorder::RETRY_WAITS
  end

  test "scheduling the first retry waits 30 seconds" do
    freeze_time do
      Grading::Recorder.schedule_retry(@attempt)
      assert_enqueued_with(job: GradePendingJob, args: [ @attempt.id ], at: 30.seconds.from_now)
    end
  end

  test "a successful run appends a retry row" do
    perform_enqueued_jobs { GradePendingJob.perform_later(@attempt.id) }

    rows = @attempt.gradings.reload
    assert_equal [ [ 1, "wrong_form", "retry" ] ], rows.map { |g| [ g.seq, g.verdict, g.source ] }
    assert_equal "0.146.0", rows.first.ce_version
    assert_match(/\+1\.0\.0\z/, rows.first.grader_version)
  end

  test "a failing worker writes nothing and the next try is 2 minutes later, then 10" do
    Grading::Expression.stub(:worker, failing_worker) do
      freeze_time do
        job = GradePendingJob.new(@attempt.id)
        job.perform_now
        assert_enqueued_with(job: GradePendingJob, at: 2.minutes.from_now)
        clear_enqueued_jobs
        job.perform_now
        assert_enqueued_with(job: GradePendingJob, at: 10.minutes.from_now)
      end
    end
    assert_equal 0, @attempt.gradings.count, "no correction is written while the worker is silent"
  end

  test "after the last failure the attempt is verdict_pending for the teacher" do
    Grading::Expression.stub(:worker, failing_worker) do
      job = GradePendingJob.new(@attempt.id)
      3.times { job.perform_now }
    end

    row = @attempt.gradings.reload.sole
    assert_equal "undetermined", row.verdict
    assert_equal [ "grader_unavailable" ], JSON.parse(row.error_codes_json)
    assert_equal "retry", row.source
    assert_equal :pending, Grading.evidence(row, @instance)
  end

  test "an attempt that was graded meanwhile is left alone" do
    Grading::Recorder.append(@attempt, Grading.grade(@instance, @attempt.raw, source: "mathlive"), source: "sync")
    GradePendingJob.perform_now(@attempt.id)
    assert_equal 1, @attempt.gradings.count
  end

  test "a later retry can still settle a given-up attempt" do
    Grading::Recorder.give_up(@attempt)
    assert Grading::Recorder.pending?(@attempt)
    GradePendingJob.perform_now(@attempt.id)
    assert_equal %w[undetermined wrong_form], @attempt.gradings.reload.map(&:verdict)
  end

  test "a retried answer that turns out invalid is settled for the teacher, not dropped" do
    attempt = create_attempt(@instance, "1 2", source: "mathlive") # ambiguous digit space: invalid by nature
    assert Grading::Recorder.pending?(attempt)
    GradePendingJob.perform_now(attempt.id)
    row = attempt.gradings.reload.sole
    assert_equal "undetermined", row.verdict
    assert_equal [ "invalid_answer" ], JSON.parse(row.error_codes_json)
    assert_equal :pending, Grading.evidence(row, @instance)
    assert_not Grading::Recorder.pending?(attempt)
  end

  test "an attempt that no longer exists is ignored" do
    assert_nothing_raised { GradePendingJob.perform_now(0) }
  end
end
