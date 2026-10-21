require "test_helper"
require "rake"
require_relative "../support/finished_run"
require_relative "../support/decision_world"

# D-317: the entry test accepts every non-empty answer. One the grader cannot read is kept as typed with
# the verdict undetermined (evidence :pending), waits like a short answer until the teacher resolves it,
# and is listed for the operator by banco:answers:pending.
class AcceptedAnswersTest < ActionDispatch::IntegrationTest
  include FinishedRun
  include DecisionWorld

  STUDENT = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }.freeze
  UNREADABLE = "n = m = 2".freeze

  def recorder(student, context: "diagnosis") = Diagnosis::AnswerRecorder.new(student: student, context: context)

  def first_step(rows)
    release_diagnosis!
    Diagnosis::Conductor.new(Diagnosis::Conductor.run_for(rows[:student], rows[:subject])).step!
  end

  def record(step, raw, student:, context: "diagnosis")
    recorder(student, context: context).call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: raw, source: "text")
  end

  def pending_task(env = {})
    saved = ENV.to_h.slice("STUDENT", "SUBJECT")
    ENV.delete("STUDENT")
    ENV.delete("SUBJECT")
    env.each { |k, v| ENV[k] = v }
    out, = capture_io { Rake::Task["banco:answers:pending"].reenable; Rake::Task["banco:answers:pending"].invoke }
    out
  ensure
    %w[STUDENT SUBJECT].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  test "an unreadable number is recorded as undetermined and pending, with the neutral line" do
    rows = build_ui_subject(components: %w[number])
    step = first_step(rows)
    outcome = record(step, UNREADABLE, student: rows[:student])
    assert_equal [ "recorded", "Risposta salvata. La guarderà il docente." ], [ outcome.status, outcome.message_it ]
    attempt = Attempt.sole
    assert_equal UNREADABLE, attempt.raw
    grading = attempt.gradings.sole
    assert_equal "undetermined", grading.verdict
    assert_equal [ "invalid_answer", "unreadable_number" ], JSON.parse(grading.error_codes_json)
    assert_equal :pending, Grading::Evidence.for_grading(grading, Grading::Spec.from_instance(attempt.item_instance))
    assert_equal 1, AppEvent.where(kind: "invalid_input").count
  end

  test "the rules table is untouched: undetermined was pending already" do
    assert_equal :pending, Diagnosis::Rules::V1::EVIDENCE.fetch("undetermined")
    assert_equal :none, Diagnosis::Rules::V1::EVIDENCE.fetch("invalid")
  end

  test "the same holds for a trial student" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    trial = Student.create!(key: "prova", kind: "student")
    step = Diagnosis::Conductor.new(Diagnosis::Conductor.run_for(trial, rows[:subject])).step!
    assert_equal "recorded", record(step, UNREADABLE, student: trial).status
    assert_equal "undetermined", Attempt.where(student: trial).sole.gradings.sole.verdict
  end

  test "empty and oversize answers are still refused, and nothing is stored" do
    rows = build_ui_subject(components: %w[number])
    step = first_step(rows)
    assert_equal "invalid", record(step, "   ", student: rows[:student]).status
    assert_equal "invalid", record(step, "9" * 30_000, student: rows[:student]).status
    assert_equal 0, Attempt.count
  end

  test "a dot decimal and a percent sign are read in the sitting, not held" do
    rows = build_ui_subject(components: %w[number])
    step = first_step(rows)
    outcome = record(step, "0.5", student: rows[:student])
    assert_equal [ "recorded", nil ], [ outcome.status, outcome.message_it ]
    assert_not_equal "undetermined", Attempt.sole.gradings.sole.verdict
    assert_equal 0, AppEvent.where(kind: "invalid_input").count
  end

  test "the run holds on the answer like on a short answer, the pages render, and resolve_attempt lets it close" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    run = play_run(rows[:student], rows[:subject], answers: { "number" => UNREADABLE }, clock: Diagnosis::FakeClock.new(Time.utc(2026, 10, 20, 8))) # before now: the decisions come after the answers
    attempts = Attempt.where(student: rows[:student]).order(:id).to_a
    assert_operator attempts.size, :>=, 2
    assert(attempts.all? { |a| a.gradings.last.verdict == "undetermined" })
    attempt = attempts.first
    assert Diagnosis::Conductor.new(run).holding?, "an unreadable answer waits for the teacher, it does not end the run"

    entry = Teacher::Corrections.call(student: rows[:student]).verdicts.find { |v| v.attempt.id == attempt.id }
    assert entry
    assert entry.unreadable
    assert_equal UNREADABLE, entry.given

    teacher = DecisionWorld::TEACHER
    on(:web, "/teacher/corrections", headers: teacher, remote_addr: EDGE)
    assert_response :success
    assert_select "article.verdict[data-attempt='#{attempt.id}'] [data-given]", UNREADABLE
    assert_select "article.verdict[data-attempt='#{attempt.id}'] [data-unreadable]", /Risposta non leggibile dal programma/
    assert_select "article.verdict[data-attempt='#{attempt.id}'] button[name=verdict]", 3
    on(:web, "/teacher/subjects/math/report", headers: teacher, remote_addr: EDGE)
    assert_response :success
    on(:web, "/diagnosis/runs/#{run.id}/results", headers: STUDENT, remote_addr: EDGE)
    assert_response :success

    cookies.delete(DecisionRecorder::DEVICE_COOKIE) # the student's own computer would refuse the teacher
    attempts.each do |a|
      decide("/teacher/attempts/#{a.id}/resolve", { verdict: "wrong", reason_it: "Non rispondeva." })
      assert_response :success
    end
    assert_empty Teacher::Corrections.call(student: rows[:student]).verdicts
    assert_not Diagnosis::Conductor.new(run).holding?
    on(:web, "/teacher/subjects/math/report", headers: teacher, remote_addr: EDGE)
    assert_response :success
  end

  test "the console task lists what waits, with the command to decide it, and writes nothing" do
    rows = build_ui_subject(components: %w[number])
    step = first_step(rows)
    record(step, UNREADABLE, student: rows[:student])
    Rake::Task.clear
    Rails.application.load_tasks
    attempt_id = Attempt.sole.id
    assert_no_difference [ "Decision.count", "Attempt.count", "AttemptGrading.count" ] do
      out = pending_task
      assert_includes out, "1 answer(s) wait"
      assert_includes out, "attempt #{attempt_id}"
      assert_includes out, UNREADABLE
      assert_includes out, "unreadable by the program"
      assert_includes out, %("attempt_id":#{attempt_id})
      assert_includes out, "KIND=resolve_attempt"
    end
    assert_includes pending_task("SUBJECT" => "history"), "nothing waits"
    assert_includes pending_task("SUBJECT" => "math", "STUDENT" => "student"), UNREADABLE
  end

  test "a short answer line prints the grade proposal to confirm, or says none is there yet" do
    entry = Teacher::PendingAnswers::Entry.new(7, 1, "history", "k", "stem", "model", "typed", "short_answer", "short answer", 42)
    assert_includes Teacher::PendingAnswers.lines(entry).last, %(KIND=confirm_grade TEACHER=<login> PARAMS='{"grade_proposal_id":42}')
    assert_includes Teacher::PendingAnswers.lines(entry.with(proposal_id: nil)).last, "no grade proposal yet"
  end

  test "no API route, controller or CLI command names the pending list" do
    assert_not_includes Rails.root.join("contract/commands.json").read, "answers:pending"
    assert_empty Dir[Rails.root.join("app/controllers/api/**/*.rb")].select { |f| File.read(f).match?(/PendingAnswers/) }
    assert_empty Dir[Rails.root.join("cli/**/*.go")].reject { |f| f.end_with?("_test.go") }.select { |f| File.read(f).match?(/PendingAnswers|answers:pending/) }
  end
end
