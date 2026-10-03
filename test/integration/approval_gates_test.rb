require "test_helper"
require_relative "../support/decision_world"

# The gates of approval (B-07, B-08, C-04) and what an approval pins: approve_blueprint
# needs the whole checklist; a newer draft never un-approves; a run pins the approved
# blueprint; the status says where each subject stands.
class ApprovalGatesTest < ActionDispatch::IntegrationTest
  include DecisionWorld

  setup do
    build_decision_world
    @token = ApiToken.issue!(role: "agent_claude", label: "gates")
  end

  def approve_blueprint(blueprint = @blueprint)
    decide("/teacher/blueprint-revisions/#{blueprint.id}/approve")
  end

  def api_status
    on(:api, "/api/v1/status", headers: { "Authorization" => "Bearer #{@token}" })
    response.parsed_body
  end

  def row(status, key = "math") = status["subjects"].find { |s| s["key"] == key }

  def new_draft
    BlueprintRevision.create!(subject: @subject, skill_graph_revision: @graph, author_session: @blueprint.author_session,
                              seq: @blueprint.seq + 1, body_json: @blueprint.body_json)
  end

  test "the entry test is not approvable until the graph is approved, every pinned item is approvable and was opened, and the test was played" do
    approve_blueprint
    assert_response :unprocessable_entity
    reasons = json["reasons"].join("\n")
    assert_match(/graph revision #{@graph.id} of this test is not approved/, reasons)
    assert_match(/no expert review on this revision/, reasons)
    assert_match(/was not opened in the preview/, reasons)
    assert_match(/not played to the end as the preview student/, reasons)
    assert_equal 0, Decision.where(kind: "approve_blueprint").count

    approve_graph_row!
    ids = @blueprint.pinned_item_revision_ids
    ids.each { |id| ItemReview.create!(item_revision_id: id, agent_session: @session, checklist_json: "[]") && BlindSolve.create!(item_revision_id: id, agent_session: @session, answers_json: "[]", results_json: "[]") }
    approve_blueprint
    assert_match(/was not opened in the preview/, json["reasons"].join)
    assert_no_match(/not approvable/, json["reasons"].join)

    ids.each { |id| AppEvent.create!(kind: "teacher_viewed_item", payload_json: { item_revision_id: id }.to_json) }
    approve_blueprint
    assert_equal [ "the test was not played to the end as the preview student" ], json["reasons"]

    play_preview!
    approve_blueprint
    assert_response :success
    assert_equal 1, Decision.where(kind: "approve_blueprint").count
    assert_predicate SubjectStage.approved_blueprint(@subject), :present?
  end

  test "an open blocker or major finding, or a fix request, keeps the entry test shut" do
    approve_graph_row!
    make_blueprint_approvable!
    finding = ReviewFinding.create!(item_revision: @short, source: "review", severity: "blocker", field: "prompt", quote: "q", problem_it: "p", fix_it: "f")
    approve_blueprint
    assert_response :unprocessable_entity
    assert_match(/without the teacher's disposition/, json["reasons"].join)

    decide("/teacher/findings/#{finding.id}/disposition", { disposition: "fix_requested", reason_it: "Da rifare." })
    approve_blueprint
    assert_match(/asked to fix/, json["reasons"].join)

    decide("/teacher/findings/#{finding.id}/disposition", { disposition: "dismissed", reason_it: "Era un falso allarme." })
    approve_blueprint
    assert_response :success
  end

  test "a preview played on another revision does not count, and a failed validation shuts the gate" do
    approve_graph_row!
    make_blueprint_approvable!
    other = new_draft
    approve_blueprint(other)
    assert_response :unprocessable_entity
    assert_match(/not played to the end/, json["reasons"].join)

    approve_blueprint(@blueprint)
    assert_response :unprocessable_entity
    assert_match(/not the latest entry test/, json["reasons"].join)

    ItemValidation.create!(item_revision: @short, seq: 2, status: "failed")
    make_blueprint_approvable!(other) rescue nil
    approve_blueprint(other)
    assert_response :unprocessable_entity
    assert_match(/validation has not passed/, json["reasons"].join)
  end

  test "the teacher's opening of an item in the preview is the app_event the gate needs, and the student's computer writes none" do
    assert_difference -> { AppEvent.where(kind: "teacher_viewed_item").count }, 1 do
      on(:web, "/teacher/items/#{@short.id}", headers: TEACHER, remote_addr: EDGE)
    end
    assert_response :success
    assert_equal({ "item_revision_id" => @short.id }, JSON.parse(AppEvent.where(kind: "teacher_viewed_item").last.payload_json))
    cookies[:banco_device] = "student"
    assert_no_difference -> { AppEvent.where(kind: "teacher_viewed_item").count } do
      on(:web, "/teacher/items/#{@short.id}", headers: TEACHER, remote_addr: EDGE)
    end
    on(:web, "/teacher/items/#{@short.id}", headers: { "Remote-User" => "student", "Remote-Groups" => "banco-student" }, remote_addr: EDGE)
    assert_response :forbidden
  end

  test "approve_skill_graph takes the latest revision only" do
    old = @graph
    newer = SkillGraphRevision.create!(subject: @subject, seq: old.seq + 1, body_json: old.body_json)
    decide("/teacher/skill-graph-revisions/#{old.id}/approve")
    assert_response :unprocessable_entity
    decide("/teacher/skill-graph-revisions/#{newer.id}/approve")
    assert_response :success
  end

  test "a subject is approved with an approved graph and an approved blueprint; a newer draft never un-approves" do
    approve_graph_row!
    make_blueprint_approvable!
    assert_nil Diagnosis::Conductor.approved_blueprint(@subject)
    approve_blueprint
    assert_response :success
    assert_equal @blueprint, Diagnosis::Conductor.approved_blueprint(@subject)

    draft = new_draft
    assert_equal @blueprint, Diagnosis::Conductor.approved_blueprint(@subject)
    status = api_status
    assert_equal true, row(status)["graph_approved"]
    assert_equal true, row(status)["blueprint_approved"]
    assert_equal true, row(status)["pending_revision"]
    assert_equal "approved", row(status)["stage"]
    assert_equal draft.id, row(status)["blueprint"]["revision_id"]
    assert_equal @blueprint.id, row(status)["blueprint"]["approved_revision_id"]
  end

  test "a student's run pins the latest approved blueprint, never a newer draft; the preview pins the draft" do
    approve_graph_row!
    make_blueprint_approvable!
    assert_nil Diagnosis::Conductor.create_run(@student, @subject, sequence: 5)
    approve_blueprint
    draft = new_draft
    run = Diagnosis::Conductor.create_run(@student, @subject, sequence: 5)
    assert_equal @blueprint, run.blueprint_revision
    preview = Student.find_or_create_by!(key: "preview") { |s| s.kind = "preview" }
    assert_equal draft, Diagnosis::Conductor.fresh_run(preview, @subject).blueprint_revision
    assert_equal @blueprint, run.reload.blueprint_revision
  end

  test "a run serves only pinned items whose validation passed" do
    approve_ui_subject!(@subject, @graph, @blueprint)
    failed = @world[:revisions]["number"]
    ItemValidation.create!(item_revision: failed, seq: 2, status: "failed")
    run = Diagnosis::Conductor.run_for(@student, @subject)
    plan = Diagnosis::PlanLoader.for_run(run)
    served_items = plan.pool.values.map(&:item).uniq
    assert_not_includes served_items, failed.id
    assert_includes served_items, @world[:revisions]["choice"].id
  end

  test "every sitting is recorded as unsupervised" do
    approve_ui_subject!(@subject, @graph, @blueprint)
    run = Diagnosis::Conductor.create_run(@student, @subject, sequence: 5)
    Diagnosis::Conductor.new(run).step!
    started = run.events.where(kind: "sitting_started").first
    assert_equal "unsupervised", JSON.parse(started.payload_json)["condition"]
  end

  test "a kind_override decision changes the kind of a skill in the plan" do
    approve_ui_subject!(@subject, @graph, @blueprint)
    skill = skill_key("math", "number")
    before = Diagnosis::PlanLoader.for_run(Diagnosis::Conductor.run_for(@student, @subject)).skills[skill].kind
    wanted = before.to_s == "learn" ? "recover" : "learn"
    decide("/teacher/subjects/math/kind-override", { skill: skill, override_kind: wanted, reason_it: "Lo ha già studiato." })
    assert_response :success
    after = Diagnosis::PlanLoader.for_run(Diagnosis::Conductor.run_for(@student, @subject)).skills[skill].kind
    assert_equal wanted, after.to_s
    decide("/teacher/subjects/math/kind-override", { skill: "math.nothing", override_kind: "learn", reason_it: "Non esiste." })
    assert_response :unprocessable_entity
  end

  test "the diagnosis is released only with the consent, the warm-up and every subject approved, all together" do
    other = build_ui_subject(key: "italian", name: "Italiano", position: 2, approve: false)
    decide("/teacher/release")
    assert_response :unprocessable_entity
    reasons = json["reasons"]
    assert_includes reasons, "the consent is not recorded"
    assert_includes reasons, "the warm-up is not completed"
    assert_includes reasons, "math: graph and entry test are not both approved"
    assert_includes reasons, "italian: graph and entry test are not both approved"

    decide("/teacher/consent", { acknowledged: true })
    decide("/teacher/consent", { acknowledged: true })
    assert_response :unprocessable_entity
    AppEvent.create!(kind: "warmup_completed", student: @student)
    approve_ui_subject!(@subject, @graph, @blueprint)
    decide("/teacher/release")
    assert_equal [ "italian: graph and entry test are not both approved" ], json["reasons"]
    approve_ui_subject!(other[:subject], SkillGraphRevision.find_by!(subject: other[:subject]), other[:blueprint])
    decide("/teacher/release")
    assert_response :success
    assert_equal %w[math italian], JSON.parse(Decision.where(kind: "release_diagnosis").sole.payload_json)["subjects"]
    assert_predicate Diagnosis::Release, :open?
    decide("/teacher/release")
    assert_response :unprocessable_entity
  end

  test "status says where the subject stands, the consent, the warm-up and the release" do
    status = api_status
    assert_equal false, status["warmup_completed"]
    assert_equal false, status["consent_recorded"]
    assert_equal({ "released" => false }, status["diagnosis"])
    assert_equal "in_review", row(status)["stage"]

    make_blueprint_approvable!
    assert_equal "awaiting_teacher", row(api_status)["stage"]
    decide("/teacher/consent", { acknowledged: true })
    AppEvent.create!(kind: "warmup_completed", student: @student)
    status = api_status
    assert_equal true, status["consent_recorded"]
    assert_equal true, status["warmup_completed"]
  end

  test "confirm_grade with edits records a new grade in the decision and the confirmation reaches the log" do
    decide("/teacher/grade-proposals/#{@proposal.id}/confirm", { scores: { a: 1, b: 1 }, reason_it: "Anche la seconda parte c'è." })
    assert_response :success
    payload = JSON.parse(Decision.where(kind: "confirm_grade").sole.payload_json)
    assert_equal true, payload["edited"]
    assert_equal true, payload["passed"]
    assert_equal({ "a" => 1, "b" => 1 }, payload["scores"])
    assert_equal @attempt.id, payload["attempt_id"]
    assert_predicate @proposal.reload, :confirmed?
    decide("/teacher/grade-proposals/#{@proposal.id}/confirm")
    assert_response :unprocessable_entity
    decide("/teacher/grade-proposals/#{@rejected_id ||= GradeProposal.create!(attempt: @attempt, agent_session: @session, points_json: "[]", total: 0, max_total: 2, threshold: 0.6, meets_threshold: false).id}/confirm", { scores: { a: 5, b: 0 }, reason_it: "x yz" })
    assert_response :unprocessable_entity
  end

  test "resolve, void and close take their ids from the run and carry the student and subject" do
    decide("/teacher/attempts/#{@attempt.id}/resolve", { verdict: "typical_error", error_code: "sign", reason_it: "Errore di segno." })
    assert_response :success
    d = Decision.where(kind: "resolve_attempt").sole
    assert_equal [ @subject.id, @student.id ], [ d.subject_id, d.student_id ]
    decide("/teacher/attempts/#{@attempt.id}/resolve", { verdict: "bogus", reason_it: "x yz" })
    assert_response :unprocessable_entity
    decide("/teacher/runs/#{@run.id}/close", { reason_it: "Basta." })
    assert_response :success
    decide("/teacher/runs/#{@run.id}/void", { reason_it: "Rifare con semi nuovi." })
    assert_response :success
    assert Diagnosis::EventLoader.voided?(@run)
    decide("/teacher/runs/#{@run.id}/void", { reason_it: "Ancora." })
    assert_response :unprocessable_entity
  end

  test "after a void the run is redone with fresh seeds" do
    approve_ui_subject!(@subject, @graph, @blueprint)
    decide("/teacher/runs/#{@run.id}/void", { reason_it: "Rifare." })
    redo_run = Diagnosis::Conductor.run_for(@student, @subject)
    assert_not_equal @run.id, redo_run.id
    assert_not_equal @run.seed_salt, redo_run.seed_salt
    assert_equal 2, redo_run.sequence
  end

  test "reconcile-decisions finds no orphan after a recorded decision and reports the ones it can see" do
    since = Time.current
    decide("/teacher/consent", { acknowledged: true })
    assert_equal 0, DecisionReconciliation.call(since: since).orphans

    Decision.create!(kind: "approve_skill_graph", subject: @subject, payload_json: "{}", request_id: "r-x", teacher_login: "", remote_addr: "127.0.0.1")
    result = DecisionReconciliation.call(since: since)
    assert_equal 1, result.orphans
    assert_equal [ "teacher_login", "group" ], result.items.first[:missing]

    Student # a student run before any release
    DiagnosisRun.create!(student: @student, subject: @subject, blueprint_revision: @blueprint, sequence: 9, seed_salt: "x", rules_version: "v1", engine_version: "e1")
    items = DecisionReconciliation.call(since: since).items
    assert(items.any? { |i| i[:table] == "diagnosis_runs" && i[:reason] == "started before release_diagnosis" })
  end

  test "reconcile since parses days, hours and minutes" do
    now = Time.utc(2026, 10, 3, 12)
    assert_equal Time.utc(2026, 10, 2, 12), DecisionReconciliation.parse_since("1d", now: now)
    assert_equal Time.utc(2026, 10, 3, 6), DecisionReconciliation.parse_since("6h", now: now)
    assert_equal Time.utc(2026, 10, 3, 11, 30), DecisionReconciliation.parse_since("30m", now: now)
    assert_raises(ArgumentError) { DecisionReconciliation.parse_since("soon") }
  end
end
