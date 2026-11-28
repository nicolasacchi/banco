require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"

# ValidateItemRevisionJob: a verdict is appended once; trouble with Chrome or the
# grader is an error row (never a pass) and a retry; the last timeout is E-GEN-TIMEOUT.
class ValidateItemRevisionJobTest < ActiveJob::TestCase
  include CourseRows
  F = ValidationFixtures

  setup do
    build_course
    @author = AgentSession.create!(label: "t", role: "author", agent: "test", model: "claude-test")
    submission = Validation::Submission.new(key: "eq-1", base: nil, files: F.files_for(F.static_item), session: @author).prepare!
    @revision, = submission.store!
  end

  def statuses = @revision.reload.validations.order(:seq).pluck(:status)

  # An ItemRunner whose call raises (or answers), standing in for Chrome.
  def with_runner(behaviour, &block)
    fake = Object.new
    fake.define_singleton_method(:call) { behaviour.call }
    Validation::ItemRunner.stub(:new, ->(**) { fake }, &block)
  end

  test "a verdict is one passed row, the instances once, and a second run does nothing" do
    ValidateItemRevisionJob.perform_now(@revision.id)
    assert_equal %w[passed], statuses
    assert_equal 3, @revision.instances.count
    row = @revision.latest_validation
    assert_equal JSON.parse(row.codes_json), []
    assert_equal Validation::Rules.version.to_s, row.rules_version
    assert_equal Validation::Harness.version, row.harness_version
    assert_match(/\A\h{64}\z/, row.instances_sha256)
    ValidateItemRevisionJob.perform_now(@revision.id)
    assert_equal %w[passed], statuses
    assert_equal 3, @revision.instances.count
  end

  test "a failed revision is one failed row with its codes" do
    bad = Validation::Submission.new(key: "eq-2", base: nil, files: F.files_for(F.static_item("prompt" => { "stem_it" => "Scrivi la risposta che cercano." })), session: @author).prepare!.store!.first
    ValidateItemRevisionJob.perform_now(bad.id)
    row = bad.reload.latest_validation
    assert_equal "failed", row.status
    assert_equal [ "E-PHRASE" ], JSON.parse(row.codes_json)
    assert JSON.parse(row.findings_json).first["field"].present?
  end

  test "Chrome that cannot be reached: an error row per attempt, retried, never a pass; the last attempt settles as error" do
    with_runner(-> { raise Validation::ChromeRunner::Unavailable, "no chrome" }) do
      perform_enqueued_jobs do
        ValidateItemRevisionJob.perform_later(@revision.id)
      end
    end
    assert_equal %w[error error error], statuses
    assert_equal [ 1, 2, 3 ], @revision.validations.order(:seq).pluck(:attempt)
    assert_equal "error", @revision.reload.status
    assert_equal 0, @revision.instances.count
    assert_includes JSON.parse(@revision.latest_validation.findings_json).first["message"], "no chrome"
  end

  test "a grader worker that is down is retried the same way" do
    with_runner(-> { raise Validation::Roundtrip::Unavailable, "worker down" }) do
      perform_enqueued_jobs { ValidateItemRevisionJob.perform_later(@revision.id) }
    end
    assert_equal %w[error error error], statuses
  end

  test "a timeout inside the page on the last attempt fails the revision with E-GEN-TIMEOUT, marked as the server's limit" do
    with_runner(-> { raise Validation::ChromeRunner::Timeout, "timed out promise" }) do
      perform_enqueued_jobs(only: ValidateItemRevisionJob) { ValidateItemRevisionJob.perform_now(@revision.id) }
    end
    assert_equal %w[error error failed], statuses.first(3)
    row = @revision.reload.validations.order(:seq).find_by(status: "failed")
    assert_equal [ "E-GEN-TIMEOUT" ], JSON.parse(row.codes_json)
    assert row.timeout_only?
    finding = JSON.parse(row.findings_json).first
    assert_equal true, finding["detail"]["server_limit"]
    assert_includes finding["message"], "the server's time limit, not a problem of the files"
    assert_includes finding["message"], "banco work retry #{@revision.id}"
  end

  test "a timeout-only failure is not final: it is queued again with a wait, three failures in a row at most, and then it stands" do
    with_runner(-> { raise Validation::ChromeRunner::Timeout, "timed out promise" }) do
      perform_enqueued_jobs { ValidateItemRevisionJob.perform_later(@revision.id) }
    end
    assert_equal 3, ItemValidation.timeout_streak(@revision), "the first go and two more, then nothing is queued again"
    assert_equal %w[error error failed] * 3, statuses
    assert_empty enqueued_jobs
    # each go after the first is a new job that names the revision and the latest row of the go before it
    again = performed_jobs.select { |j| j[:job] == ValidateItemRevisionJob && j[:args].size == 2 }
    assert_equal 2, again.map { |j| j[:args] }.uniq.size, "two more goes, each after the latest row of the go before"
    assert_equal [ @revision.id ], again.map { |j| j[:args].first }.uniq
  end

  test "a failure on the server's time limit is drawn again by the job although it says failed, and a content failure is final" do
    Validation::RevisionValidation.new(@revision, attempt: 3).record_timeout(Validation::ChromeRunner::Timeout.new("timed out promise"))
    assert_equal %w[failed], statuses
    ValidateItemRevisionJob.perform_now(@revision.id)
    assert_equal %w[failed passed], statuses
    bad = Validation::Submission.new(key: "eq-2", base: nil, files: F.files_for(F.static_item("prompt" => { "stem_it" => "Scrivi la risposta che cercano." })), session: @author).prepare!.store!.first
    ValidateItemRevisionJob.perform_now(bad.id)
    ValidateItemRevisionJob.perform_now(bad.id)
    assert_equal %w[failed], bad.reload.validations.order(:seq).pluck(:status), "a content failure is final"
  end

  test "a draw asked for after a verdict that has come since does nothing" do
    Validation::RevisionValidation.new(@revision, attempt: 3).record_timeout(Validation::ChromeRunner::Timeout.new("x"))
    ValidateItemRevisionJob.perform_now(@revision.id)
    assert_equal %w[failed passed], statuses
    assert_no_changes -> { ItemValidation.count } do
      ValidateItemRevisionJob.perform_now(@revision.id, 0)
    end
  end

  test "a revision with no verdict that lost its job is stuck after the stale minutes, and a fresh one is not" do
    assert_not ValidateItemRevisionJob.stuck?(@revision), "a revision just submitted is waiting its turn"
    assert ValidateItemRevisionJob.stuck?(@revision, now: 11.minutes.from_now)
    ItemValidation.create!(item_revision: @revision, seq: 1, status: "passed", codes_json: "[]", rules_version: Validation::Rules.version.to_s)
    assert_not ValidateItemRevisionJob.stuck?(@revision, now: 1.day.from_now), "a verdict is not a lost job"
  end

  test "an attempt that succeeds after an error ends as the verdict" do
    calls = 0
    runner = lambda do
      calls += 1
      raise Validation::ChromeRunner::Busy, "busy" if calls == 1

      Validation::ItemRunner::Result.new(status: "passed", findings: Validation::Findings.new, instances: [], instances_sha256: nil, details: {})
    end
    with_runner(runner) { perform_enqueued_jobs { ValidateItemRevisionJob.perform_later(@revision.id) } }
    assert_equal %w[error passed], statuses
    assert_equal "passed", @revision.reload.status
  end

  test "a pass under older rules is validated again under the current rules, appended (D-154)" do
    ItemValidation.create!(item_revision: @revision, seq: 1, status: "passed", codes_json: "[]", rules_version: "0")
    ValidateItemRevisionJob.perform_now(@revision.id)
    assert_equal %w[passed passed], statuses
    assert_equal Validation::Rules.version.to_s, @revision.reload.latest_validation.rules_version
    assert_nil Validation::ItemInfo.outdated_rules_version(@revision)
    ValidateItemRevisionJob.perform_now(@revision.id)
    assert_equal %w[passed passed], statuses
  end

  test "the job runs on the chrome queue" do
    assert_equal "chrome", ValidateItemRevisionJob.new.queue_name
    queues = YAML.load_file(Rails.root.join("config/queue.yml"), aliases: true)["default"]["workers"]
    lanes = queues.select { |w| %w[chrome chrome_shots].include?(w["queues"]) }
    assert_equal Validation::ChromeRunner::SLOTS, lanes.sum { |w| w["threads"] }, "as many threads as Chrome has slots: three runs at a time, one of them the shots' (D-408)"
  end

  test "an unknown revision is ignored" do
    assert_nothing_raised { ValidateItemRevisionJob.perform_now(0) }
  end
end
