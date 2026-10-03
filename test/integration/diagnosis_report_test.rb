require "test_helper"
require_relative "../support/finished_run"

# The report of the diagnosis (B-09), banco.diagnosis_report/1: read-only, the same
# hash in the API and on the teacher's page, no student text in the API.
class DiagnosisReportTest < ActionDispatch::IntegrationTest
  include FinishedRun

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "report test")
    @rows = build_ui_subject(components: %w[number choice short_answer])
    release_diagnosis!
    @run = play_run(@rows[:student], @rows[:subject])
  end

  def api(path)
    on(:api, path, headers: { "Authorization" => "Bearer #{@token}" })
  end

  test "banco diagnosis report returns the B-09 shape for a finished run" do
    api "/api/v1/diagnosis/report?subject=math"
    assert_response :ok
    record_example "diagnosis report", "completed"
    report = response.parsed_body
    assert_equal "banco.diagnosis_report/1", report["schema"]
    assert_equal "unsupervised", report["sitting_condition"]
    assert_equal "diagnosis/1", report["rules_version"]
    row = report["subjects"].sole
    assert_equal %w[subject name_it status graph_form entry_test run sittings counted_minutes groups skills errors_observed unclassified pending signals checks].sort, row.keys.sort
    assert_equal "completed", row["status"]
    assert_equal "fixed_form", row["graph_form"]
    assert_equal({ "blueprint_revision_id" => @rows[:blueprint].id, "seq" => 1, "approved" => true, "approved_revision_id" => @rows[:blueprint].id, "pending_revision" => false }, row["entry_test"])
    assert_equal @run.id, row["run"]["id"]
    assert_equal "pending_answers", row["run"]["waiting_on"], "the run waits for the teacher's grade of the short answer"
    assert_equal [ "closed" ], row["run"]["grader_versions"].map { |g| g["grader"] }
    assert_equal "unsupervised", row["sittings"].first["condition"]
    assert_equal row["skills"].size, row["groups"].values.sum
    assert_equal %w[math.choice math.number math.short-answer], row["skills"].map { |s| s["skill"] }.sort
    typical = row["errors_observed"].find { |e| e["code"] == "adds_wrong" }
    assert typical, "the typical error of the number item is counted"
    assert_equal "math.number", typical["skill"]
    assert_operator typical["count"], :>=, 1
    assert_not typical.key?("examples"), "the API carries no student text"
    assert_not_includes response.body, "Una risposta breve"
    assert_operator row["signals"]["dont_know_share"], :>, 0
    assert_equal "pending", row["skills"].find { |s| s["skill"] == "math.short-answer" }["state"]
    assert_equal 1, row["groups"]["pending"]
  end

  test "a subject with no run is not_started, a voided run is to_redo, an unknown subject is 404" do
    other = build_ui_subject(key: "history", name: "Storia", components: %w[choice], position: 2)[:subject]
    api "/api/v1/diagnosis/report"
    assert_equal %w[completed not_started], response.parsed_body["subjects"].map { |s| s["status"] }.sort
    history = response.parsed_body["subjects"].find { |s| s["subject"] == "history" }
    assert_equal [], history["skills"]
    assert_nil history["run"]

    Decision.create!(kind: "void_diagnosis_run", subject: @rows[:subject], student: @rows[:student], payload_json: { run_id: @run.id }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "teacher", remote_addr: "127.0.0.1")
    api "/api/v1/diagnosis/report?subject=math"
    assert_equal "to_redo", response.parsed_body["subjects"].sole["status"]
    api "/api/v1/diagnosis/report?subject=nothing"
    assert_response :not_found
    assert_equal "E-NOT-FOUND", response.parsed_body["code"]
    assert other
  end

  test "the report is read-only: it writes no row" do
    before = [ Decision.count, DiagnosisEvent.count, Attempt.count, AppEvent.count ]
    api "/api/v1/diagnosis/report"
    assert_equal before, [ Decision.count, DiagnosisEvent.count, Attempt.count, AppEvent.count ]
  end

  test "the page's version of the report carries the student's example answers" do
    report = Diagnosis::Report.call(subject: @rows[:subject], with_answers: true)
    typical = report[:subjects].sole[:errors_observed].find { |e| e[:code] == "adds_wrong" }
    assert_includes typical[:examples], "99"
  end
end
