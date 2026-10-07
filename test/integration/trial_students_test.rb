require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/decision_world"
require_relative "../support/finished_run"

# D-217: trial students play the same pages and engine on their own log, without consent or release,
# on the approved test or else the newest validated one; they never mark the computer as the
# student's, and nothing they do touches the official student, the release or the approval gate.
class TrialStudentsTest < ActionDispatch::IntegrationTest
  include MultiUser
  include DecisionWorld
  include FinishedRun

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  setup do
    ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
    @token = ApiToken.issue!(role: "agent_claude", label: "trial test")
  end

  # A page as the browser asks for it; a post as the page's script does, with the page's CSRF token.
  def as(headers, path, method: :get, body: nil)
    return on(:web, path, headers: headers, remote_addr: EDGE) if method == :get

    page = headers.equal?(TEACHER) ? "/teacher" : "/diagnosis"
    on(:web, page, headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: method, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body&.to_json, remote_addr: EDGE)
  end

  def trial = Student.find_by!(key: "prova-1")
  def official = Student.find_by!(key: "student")

  test "before any approval a trial student sees the validated test and starts it without release or consent" do
    build_ui_subject(approve: false)
    assert_not Diagnosis::Release.open?
    as(TRIAL, "/diagnosis")
    assert_response :success
    assert_select "#trial-notice", /Account di prova: i risultati non contano/
    assert_select "li.subject[data-subject=math]"
    assert_select "li.subject[data-subject=math] form"
    as(TRIAL, "/diagnosis/subjects/math", method: :post)
    assert_response :see_other
    run = DiagnosisRun.find_by!(student: trial)
    assert_equal BlueprintRevision.last.id, run.blueprint_revision_id
    as(TRIAL, "/diagnosis/runs/#{run.id}/step", method: :post)
    assert_response :success
    assert_equal "item", response.parsed_body["type"]
    served = response.parsed_body["served_event_id"]
    as(TRIAL, "/diagnosis/answers", method: :post, body: { served_event_id: served, client_attempt_id: SecureRandom.uuid, raw: "3", source: "text" })
    assert_response :success
    assert_equal 1, Attempt.where(student: trial).count
    as(TRIAL, "/diagnosis/warmup")
    assert_response :success
  end

  test "the official student still sees a closed diagnosis, on the same data" do
    build_ui_subject(approve: false)
    as(OFFICIAL, "/diagnosis")
    assert_select "p.notice", "La diagnosi non è ancora aperta."
    assert_select "#trial-notice", 0
    as(OFFICIAL, "/diagnosis/subjects/math", method: :post)
    assert_response :forbidden
  end

  test "an approved test wins over a newer draft for a trial student" do
    rows = build_ui_subject
    newer = BlueprintRevision.create!(subject: rows[:subject], skill_graph_revision: rows[:blueprint].skill_graph_revision, seq: 2, body_json: rows[:blueprint].body_json)
    assert_equal newer, Diagnosis::Conductor.latest_blueprint(rows[:subject])
    as(TRIAL, "/diagnosis/subjects/math", method: :post)
    assert_response :see_other
    assert_equal rows[:blueprint].id, DiagnosisRun.find_by!(student: trial).blueprint_revision_id
  end

  test "a blueprint whose items did not pass validation is not offered to a trial student" do
    rows = build_ui_subject(approve: false)
    rows[:blueprint].pinned_item_revision_ids.each { |id| ItemValidation.create!(item_revision_id: id, seq: 2, status: "failed") }
    as(TRIAL, "/diagnosis")
    assert_select "li.subject", 0
    as(TRIAL, "/diagnosis/subjects/math", method: :post)
    assert_response :forbidden
    assert_nil Diagnosis::Conductor.latest_validated_blueprint(rows[:subject])
  end

  test "the student pages set the device cookie for the official student and never for a trial student" do
    build_ui_subject
    release_diagnosis!
    as(TRIAL, "/diagnosis")
    as(TRIAL, "/diagnosis/subjects/math", method: :post)
    as(TRIAL, "/diagnosis/warmup")
    assert_nil response.cookies[DecisionRecorder::DEVICE_COOKIE]
    assert_not_includes response.headers["Set-Cookie"].to_s, DecisionRecorder::DEVICE_COOKIE
    as(OFFICIAL, "/diagnosis")
    assert_includes response.headers["Set-Cookie"].to_s, DecisionRecorder::DEVICE_COOKIE
  end

  test "trial runs never count as the played preview and never touch the official student" do
    rows = build_ui_subject(approve: false)
    as(TRIAL, "/diagnosis")
    run = play_run(trial, rows[:subject])
    assert Diagnosis::Conductor.new(run).closed? || Diagnosis::Conductor.new(run).holding?
    assert_not Approval::BlueprintGate.previewed?(rows[:blueprint])
    assert_equal 0, DiagnosisRun.where(student: official).count
    release_diagnosis!
    as(OFFICIAL, "/diagnosis")
    assert_select "li.subject", 0, "the subject is not approved: the official student sees nothing of the trial"
    approve_ui_subject!(rows[:subject], rows[:blueprint].skill_graph_revision, rows[:blueprint])
    as(OFFICIAL, "/diagnosis")
    assert_select "li.subject[data-subject=math] .subject-state", "Da fare"
    row = Diagnosis::Availability.for(official).sole
    assert_equal "not_started", row.status
    assert_nil row.run_id
    report = Diagnosis::Report.call(subject: rows[:subject])[:subjects].sole
    assert_nil report[:run]
    assert_equal 0, DiagnosisRun.where(student: official).count
  end

  test "the report and the corrections show the official student by default and a trial student on request" do
    rows = build_ui_subject(components: %w[number short_answer])
    release_diagnosis!
    official_run = play_run(Student.find_by!(key: "student"), rows[:subject])
    as(TRIAL, "/diagnosis")
    trial_run = play_run(trial, rows[:subject], answers: { "number" => "7", "short_answer" => "Un testo di prova." })
    assert_not_equal official_run.id, trial_run.id

    as(TEACHER, "/teacher/subjects/math/report")
    assert_response :success
    assert_select "#student-picker strong", "Ufficiale"
    assert_select "#student-picker a[data-student=prova-1][href=?]", "/teacher/subjects/math/report?student=prova-1", text: "Prova: trial-x"
    assert_equal official_run.id, Diagnosis::Report.call(subject: rows[:subject])[:subjects].sole[:run][:id]
    as(TEACHER, "/teacher/subjects/math/report?student=prova-1")
    assert_response :success
    assert_select "#student-picker strong", "Prova: trial-x"
    assert_equal trial_run.id, Diagnosis::Report.call(subject: rows[:subject], student: trial)[:subjects].sole[:run][:id]

    as(TEACHER, "/teacher/corrections")
    assert_select "#corrections-summary", /Risposte brevi da guardare: 1\./
    as(TEACHER, "/teacher/corrections?student=prova-1")
    assert_select "#corrections-summary", /Risposte brevi da guardare: 1\./
    assert_equal 1, Teacher::Corrections.call(student: trial).short_answers.size
    assert_equal [ trial.id ], Teacher::Corrections.call(student: trial).short_answers.map { |a| a.attempt.student_id }
    assert_equal [ official.id ], Teacher::Corrections.call.short_answers.map { |a| a.attempt.student_id }

    as(TEACHER, "/teacher")
    assert_select "#waiting-summary a[href='/teacher/corrections']"
    as(TEACHER, "/teacher?student=prova-1")
    assert_select "#waiting-summary a[href=?]", "/teacher/corrections?student=prova-1"
    assert_select "a[href=?]", "/teacher/subjects/math/report?student=prova-1"
  end

  test "the student parameter is checked against the existing rows" do
    build_ui_subject
    as(TRIAL, "/diagnosis")
    [ "nobody", "Bad Key", "preview", "../x" ].each do |key|
      %w[/teacher /teacher/corrections /teacher/subjects/math/report].each do |path|
        as(TEACHER, "#{path}?#{{ student: key }.to_query}")
        assert_response :not_found, "#{path} #{key}"
      end
    end
    as(TEACHER, "/teacher/corrections?student=student")
    assert_response :success
    as(GUEST, "/teacher/corrections?student=prova-1")
    assert_response :success
  end

  test "the teacher decides on a trial run and the decision names the trial student" do
    rows = build_ui_subject(components: %w[number short_answer])
    release_diagnosis!
    as(TRIAL, "/diagnosis")
    run = play_run(trial, rows[:subject], answers: { "number" => "7", "short_answer" => "Un testo." })
    attempt = Attempt.where(student: trial).joins(:item_instance).where(item_instances: { item_revision_id: rows[:revisions]["number"].id }).first
    decide("/teacher/runs/#{run.id}/extend", { reason_it: "Prova della proroga." })
    assert_response :success
    assert_equal trial.id, Decision.where(kind: "extend_diagnosis_run").last.student_id
    decide("/teacher/attempts/#{attempt.id}/resolve", { verdict: "wrong", reason_it: "Sbagliata." })
    assert_response :success
    assert_equal trial.id, Decision.where(kind: "resolve_attempt").last.student_id
    decide("/teacher/runs/#{run.id}/close", { reason_it: "Basta." })
    assert_response :success
    assert_equal trial.id, Decision.where(kind: "close_diagnosis_run").last.student_id
  end

  test "release and consent keep meaning the official student" do
    build_ui_subject
    as(TRIAL, "/diagnosis")
    as(OFFICIAL, "/diagnosis")
    AppEvent.create!(kind: "warmup_completed", student: official)
    cookies.delete(DecisionRecorder::DEVICE_COOKIE) # the official student's own computer would refuse the teacher
    decide("/teacher/consent", { acknowledged: true })
    decide("/teacher/release", {})
    assert_response :success
    assert_equal official.id, Decision.where(kind: "release_diagnosis").last.student_id
  end

  test "the reconciliation of the official log ignores trial runs" do
    rows = build_ui_subject(approve: false)
    as(TRIAL, "/diagnosis")
    Diagnosis::Conductor.run_for(trial, rows[:subject])
    assert_empty DecisionReconciliation.new(1.day.ago).send(:run_orphans)
  end

  test "the API report takes an optional student key, official by default" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    official_run = play_run(Student.find_by!(key: "student"), rows[:subject])
    as(TRIAL, "/diagnosis")
    trial_run = play_run(trial, rows[:subject])
    api = ->(path) { on(:api, path, headers: { "Authorization" => "Bearer #{@token}" }) }
    api.call("/api/v1/diagnosis/report?subject=math")
    assert_equal official_run.id, response.parsed_body["subjects"].sole.dig("run", "id")
    api.call("/api/v1/diagnosis/report?subject=math&student=prova-1")
    assert_response :ok
    assert_equal trial_run.id, response.parsed_body["subjects"].sole.dig("run", "id")
    api.call("/api/v1/diagnosis/report?student=nobody")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", response.parsed_body["code"]
    api.call("/api/v1/diagnosis/report?student=Bad%20Key")
    assert_response :not_found
  end
end
