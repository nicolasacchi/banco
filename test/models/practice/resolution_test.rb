require "test_helper"
require_relative "../../support/practice_text_world"

# D-352: the teacher marks a practice try right (or otherwise) with resolve_attempt. The loader reads the latest resolution as the try's outcome,
# the serve closes at that try, the tries after it no longer count, and the attempts log shows the resolution.
class PracticeResolutionTest < ActiveSupport::TestCase
  include PracticeTextWorld

  ENVIRONMENT = { "BANCO_TEACHER_USERS" => "nik", "BANCO_DECISIONS_ENABLED" => "1" }.freeze

  setup do
    build_text_world
    @serve = serve!(student: @official, topic: @text_topic, skill: SKILL, item: SENTENCE).serve
    @first = answer!(@serve, "play", student: @official)
    @second = answer!(@serve, "sleep", student: @official)
    @attempts = PracticeAttempt.where(practice_serve: @serve).order(:try_number).to_a
  end

  def resolve(attempt_id, verdict: "correct", confirm: true, reason: "Era giusta.", teacher: "nik", **extra)
    with_env(ENVIRONMENT) do
      DecisionConsole.call(kind: "resolve_attempt", teacher: teacher, os_user: "operator", reason: reason, confirm: confirm,
                           params: { attempt_id: attempt_id, verdict: verdict, **extra })
    end
  end

  def status = Practice::Loader.status_of(PracticeServe.find(@serve.id), now: @clock.now)
  def loaded = Practice::Loader.for(@official, subject: @subject, seeds: false, now: @clock.now)
  def skill_state(input = loaded) = Practice::Fold.call(seeds: input.seeds, tries: input.tries, serves: input.serves, skills: [ SKILL ]).fetch(SKILL)
  def log_rows = Practice::AttemptLog.new(@official).rows(@attempts.map(&:id), Attempts::Filters.new).index_by { |r| r[:try_number] }

  test "before the resolution two wrong tries close the serve wrong" do
    assert_equal [ :closed, :wrong ], [ status.state, status.closed_by ]
    counts = skill_state.counts
    assert_equal [ 2, 0, 2 ], [ counts[:tries], counts[:correct_unaided], counts[:wrong] ]
  end

  test "try 1 resolved right: the skill counts one correct unaided exercise, the serve is closed right, try 2 is ignored" do
    result = resolve("practice-#{@attempts.first.id}")
    assert result.ok, result.errors.inspect
    assert result.recorded

    assert_equal [ :closed, :correct, %i[next back] ], [ status.state, status.closed_by, status.actions ]
    input = loaded
    assert_equal [ [ 1, :correct, :C, false ] ], input.tries.map { |t| [ t.try_number, t.outcome, t.evidence, t.aided ] }
    counts = skill_state(input).counts
    assert_equal [ 1, 1, 0, 0, 0 ], counts.values_at(:tries, :correct_unaided, :correct_aided, :wrong, :unrecognised)
    assert_equal :correct, input.serves.sole.status.closed_by
  end

  test "try 2 resolved right keeps try 1 wrong and the serve's aid: the outcome is correct_aided" do
    assert resolve("practice-#{@attempts.last.id}").ok
    input = loaded
    assert_equal [ [ 1, :unrecognised ], [ 2, :correct_aided ] ], input.tries.map { |t| [ t.try_number, t.outcome ] }
    assert_equal :correct, status.closed_by
  end

  test "the latest resolution of a try counts: right, then wrong again" do
    assert resolve("practice-#{@attempts.first.id}").ok
    assert resolve("practice-#{@attempts.first.id}", verdict: "wrong", reason: "No, era sbagliata.").ok
    assert_equal [ [ 1, :unrecognised ], [ 2, :unrecognised ] ], loaded.tries.map { |t| [ t.try_number, t.outcome ] }
    assert_equal :wrong, status.closed_by
  end

  test "the decision names the student, the subject and the practice try, and no other student has it" do
    assert resolve("practice-#{@attempts.first.id}").ok
    decision = Decision.where(kind: "resolve_attempt").sole
    assert_equal [ @official, @subject ], [ decision.student, decision.subject ]
    payload = JSON.parse(decision.payload_json)
    assert_equal [ @attempts.first.id, "practice", @serve.id, 1, "correct", "Era giusta.", "console" ],
                 payload.values_at("attempt_id", "attempt_kind", "practice_serve_id", "try_number", "verdict", "reason_it", "via")
    assert_empty Practice::Resolutions.for_student(@trial.id)
    assert_equal [ @attempts.first.id ], Practice::Resolutions.for_student(@official.id).keys
  end

  test "the console dry run records nothing and shows the payload; CONFIRM records one decision" do
    dry = resolve(@attempts.first.id.to_s, confirm: false)
    assert dry.ok, dry.errors.inspect
    assert_not dry.recorded
    assert_equal 0, Decision.where(kind: "resolve_attempt").count
    assert_equal [ @attempts.first.id, "practice", "correct" ], dry.payload.values_at("attempt_id", "attempt_kind", "verdict")
    assert_equal :wrong, status.closed_by

    assert_difference "Decision.where(kind: 'resolve_attempt').count", 1 do
      assert resolve(@attempts.first.id.to_s).recorded
    end
    assert_equal :correct, status.closed_by
  end

  test "a bare number that is both a diagnosis answer and a practice try is refused for the console: it must say which" do
    Attempt.stub(:exists?, true) do
      result = resolve(@attempts.first.id)
      assert_not result.ok
      assert_equal :invalid, result.failure
      assert_includes result.errors.first, "practice-#{@attempts.first.id}"
      assert_equal 0, Decision.where(kind: "resolve_attempt").count
    end
  end

  test "the guards: a reason, a verdict a practice try can have, a student's try, a graded try" do
    assert_not resolve("practice-#{@attempts.first.id}", reason: "").ok
    assert_not resolve("practice-#{@attempts.first.id}", verdict: "dont_know").ok
    assert_not resolve("practice-#{@attempts.first.id}", verdict: "nonsense").ok
    assert_not resolve("practice-99999").ok
    assert_not resolve("practice-#{@attempts.first.id}", teacher: "mallory").ok

    preview = practice_student("preview.1", kind: "preview")
    instance = ItemInstance.joins(:item_revision).where(item_revisions: { id: @serve.item_instance.item_revision_id }).where.not(id: @serve.item_instance_id).first
    serve = make_serve(preview, @text_topic, instance, skill_key: SKILL, at: @clock.now)
    attempt = PracticeAttempt.create!(student: preview, practice_serve: serve, try_number: 1, client_attempt_id: "pv-1", raw: "play", source: "text", hints_before: 0,
                                      aided: false, answered_at: @clock.now, created_at: @clock.now)
    PracticeGrading.create!(practice_attempt: attempt, seq: 1, verdict: "wrong", error_codes_json: "[]", method: "exact", grader: "closed", grader_version: "t", source: "sync")
    refused = resolve("practice-#{attempt.id}")
    assert_not refused.ok
    assert_equal 0, Decision.where(kind: "resolve_attempt").count
  end

  test "the attempts log shows the resolved outcome, the resolution, what it was before, and the try that no longer counts" do
    before = log_rows
    assert_equal [ "unrecognised", "unrecognised" ], before.values_at(1, 2).map { |r| r[:outcome] }
    assert before.values.none? { |r| r.key?(:resolution) || r.key?(:counted) }

    assert resolve("practice-#{@attempts.first.id}").ok
    rows = log_rows
    one = rows[1]
    assert_equal [ "correct", "unrecognised" ], one.values_at(:outcome, :outcome_before_resolution)
    assert_equal [ "correct", "Era giusta." ], one[:resolution].values_at(:verdict, :reason_it)
    assert one[:resolution][:at].present? && one[:resolution][:decision_id].present?
    assert_not one.key?(:counted)
    two = rows[2]
    assert_equal "unrecognised", two[:outcome]
    assert_equal false, two[:counted]
  end
end
