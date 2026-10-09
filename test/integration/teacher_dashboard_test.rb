require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/decision_world"
require_relative "../support/topic_world"
require_relative "../support/arbiter_rows"

# D-240: the teacher's home is a dashboard. "Da fare adesso", one row per subject, links that open in a new tab,
# a cheap digest of the ledger and the two small endpoints the open page polls.
class TeacherDashboardTest < ActionDispatch::IntegrationTest
  include MultiUser
  include DecisionWorld
  include TopicWorld
  include ArbiterRows

  setup do
    build_decision_world
  end

  def page(path, headers: TEACHER) = on(:web, path, headers: headers, remote_addr: EDGE)

  def blocker_finding
    revision = @world[:revisions]["normalized_text"]
    ReviewFinding.create!(item_revision: revision, source: "blind_solve", blind_solve: BlindSolve.create!(item_revision: revision, agent_session: @session, answers_json: "[]", results_json: "[]"),
                          severity: "blocker", code: "E-BLIND-SOLVE-MISMATCH", instance: 1, field: "instances/1", quote: "x", problem_it: "Non torna.", fix_it: "Controlla.")
  end

  def decide_row!(kind, payload)
    Decision.create!(kind: kind, subject: @subject, payload_json: payload.to_json, request_id: SecureRandom.uuid, teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE)
  end

  test "the cached digest is shared for a few seconds and fresh=1 reads the current value" do
    silence = Teacher::DashboardDigest
    silence.reset_cache!
    first = silence.cached
    assert_equal first, silence.current
    assert_match(/\A\h{16}\z/, first)
    page("/teacher/dashboard/state?fresh=1")
    assert_response :success
    assert_equal silence.current, JSON.parse(response.body)["digest"]
  end

  test "the digest is stable and changes for a decision, a finding, an assessment, a topic and an attempt, not for the heartbeat" do
    digest = Teacher::DashboardDigest.current
    assert_equal digest, Teacher::DashboardDigest.current
    Teacher::Minutes.record("home", now: 5.minutes.ago)
    AppEvent.create!(kind: Teacher::Minutes::KIND, payload_json: { unit: "home" }.to_json)
    assert_equal digest, Teacher::DashboardDigest.current, "the heartbeat of the teacher's minutes is not a change"

    changes = [
      -> { decide_row!("approve_skill_graph", revision_id: @graph.id) },
      -> { @finding = blocker_finding },
      -> { assess!(@finding, "finding_right") },
      -> { build_topic_world },
      -> { Attempt.create!(student: @student, context: "diagnosis", client_attempt_id: "c-2", item_instance: @short.instances.first, raw: "x", source: "text", answered_at: Time.current) },
      -> { AppEvent.create!(kind: "warmup_completed", student: @student) }
    ]
    changes.each_with_index do |change, i|
      change.call
      now = Teacher::DashboardDigest.current
      assert_not_equal digest, now, "change #{i} did not change the digest"
      digest = now
    end
  end

  test "state and fragment answer the teacher and the guest, refuse the student, and are never cached" do
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    [ TEACHER, GUEST ].each do |headers|
      page("/teacher/dashboard/state", headers: headers)
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_match(/\A[0-9a-f]{16}\z/, response.parsed_body["digest"])
      assert response.parsed_body["at"].present?
      page("/teacher/dashboard/fragment", headers: headers)
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_select "#todo"
      assert_select "li.subject", Subject.count
      assert_no_match(/<html|<body/i, response.body, "the fragment is the body, not a page")
    end
    [ OFFICIAL, TRIAL ].each do |headers|
      page("/teacher/dashboard/state", headers: headers)
      assert_response :forbidden
      page("/teacher/dashboard/fragment", headers: headers)
      assert_response :forbidden
    end
    on(:web, "/teacher/dashboard/state", remote_addr: "127.0.0.1")
    assert_response :forbidden
    on(:api, "/teacher/dashboard/state")
    assert_response :not_found
  end

  test "the page carries the digest of the moment and the polling values" do
    page("/teacher")
    digest = Teacher::DashboardDigest.current
    assert_select "#dashboard[data-controller=dashboard][data-dashboard-digest-value=?]", digest
    assert_select "#dashboard[data-dashboard-state-url-value='/teacher/dashboard/state']"
    assert_select "#dashboard-newtab[checked]"
    assert_select "#dashboard-live[aria-live=polite]"
  end

  test "Da fare adesso: the release line when all is approved, then Niente da fare adesso" do
    approve_graph_row!
    make_blueprint_approvable!
    decide_row!("approve_blueprint", revision_id: @blueprint.id)
    decide_row!("confirm_grade", attempt_id: @attempt.id, grade_proposal_id: @proposal.id, passed: true)
    page("/teacher/dashboard/fragment")
    assert_select "#todo-list li", 1
    assert_select "li[data-todo=release]", "Puoi aprire la diagnosi. Manca ancora: il consenso e la prova dei comandi."
    assert_select "li[data-todo=release] a[href='#release-state']:not([target])"
    assert_select "#todo-empty", 0
    decide_row!("record_consent", {})
    AppEvent.create!(kind: "warmup_completed", student: @student)
    page("/teacher/dashboard/fragment")
    assert_select "li[data-todo=release]", "Puoi aprire la diagnosi."
    decide_row!("release_diagnosis", {})
    page("/teacher/dashboard/fragment")
    assert_select "#todo-list", 0
    assert_select "#todo-empty", "Niente da fare adesso."
  end

  test "the list is ordered: findings, then graph and test, then topics, then corrections; each line has the subject, the count and one link" do
    approve_graph_row!
    make_blueprint_approvable!
    build_topic_world
    record_viewed!
    page("/teacher/dashboard/fragment")
    kinds = css_select("#todo-list li").map { |li| li["data-todo"] }
    assert_equal %w[test_ready topics corrections], kinds
    assert_select "li[data-todo=topics]", /#{Regexp.escape(@subject.name_it)}: Un argomento del corso da approvare\./
    assert_select "li[data-todo=corrections] a[href='/teacher/corrections']", /correzion/

    finding = blocker_finding
    assess_both!(finding, "finding_right")
    page("/teacher/dashboard/fragment")
    assert_equal %w[findings topics corrections], css_select("#todo-list li").map { |li| li["data-todo"] }, "the finding comes first and blocks the test, which has no line of its own"
    assert_select "li[data-todo=findings]", /#{Regexp.escape(@subject.name_it)}: Un rilievo da decidere\./
    assert_select "li[data-todo=findings]", /Di cui 1 con un parere chiaro\./
    assert_select "li[data-todo=findings] a[href=?][target=_blank][rel=noopener]", "/teacher/subjects/#{@subject.key}/test#open-findings", "Un rilievo da decidere."
    assert_select "li[data-todo=findings] a[href=?]", "/teacher/subjects/#{@subject.key}/test#follow-opinions-form", "Segui il parere"
  end

  test "a test that only waits for the teacher but cannot be approved says one short reason in Italian" do
    approve_graph_row!
    @blueprint.pinned_item_revision_ids.each { |id| work_item!(ItemRevision.find(id), session: @session) }
    page("/teacher/dashboard/fragment")
    assert_select "li[data-todo=graph]", 0
    assert_select "li[data-todo=test_blocked]", /Il test non si può ancora approvare\. Apri la schermata dell'abilità/
    assert_select "li[data-todo=test_ready]", 0
    assert_select "li.subject[data-subject=#{@subject.key}] [data-blocked]", /Apri la schermata/
  end

  test "every link from the dashboard to a detail page opens in a new tab, anchors in the page do not" do
    approve_graph_row!
    page("/teacher")
    links = css_select("#dashboard-body a").reject { |a| a["href"].start_with?("#") }
    assert_operator links.size, :>, 5
    links.each do |a|
      assert_equal "_blank", a["target"], a["href"]
      assert_equal "noopener", a["rel"], a["href"]
    end
  end

  test "the subject row shows graph, test, course and the students with the official student's diagnosis" do
    build_topic_world
    page("/teacher")
    assert_select "li.subject[data-subject=#{@subject.key}] [data-cell=graph]", /Grafo/
    assert_select "li.subject[data-subject=#{@subject.key}] [data-cell=test]", /Test/
    assert_select "li.subject[data-subject=#{@subject.key}] [data-cell=course]", /Da approvare: \d+\. Approvati: 0\. Da scrivere: \d+\./
    assert_select "li.subject[data-subject=#{@subject.key}] [data-student-cell=student]", /Ultima attività:/
    assert_select "li.subject[data-subject=#{@subject.key}] [data-student-cell=student] a[target=_blank]"
  end

  test "trial students have a cell with their last activity and the skills they practised" do
    trial = Student.create!(key: "prova-1", kind: "student")
    page("/teacher")
    assert_select "[data-student-cell=prova-1]", /Nessuna attività/
    assert_equal trial.key, css_select("[data-student-cell=prova-1]").first["data-student-cell"]
  end

  test "a guest sees the same dashboard with no form and no button that decides" do
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    approve_graph_row!
    page("/teacher", headers: GUEST)
    assert_response :success
    assert_select "#todo"
    assert_select "li.subject", Subject.count
    assert_select "form", 0
    assert_select "#read-only-notice"
  end

  test "every teacher page has the broadcast controller, notifying only after a success flash" do
    page("/teacher/subjects/#{@subject.key}/graph")
    assert_select "body[data-controller~=broadcast][data-broadcast-notify-value=false]"
  end

  test "the page after a decision carries notify true; after a refusal it does not" do
    on(:web, "/teacher/skill-graph-revisions/#{@graph.id}/approve", method: :post, headers: TEACHER, params: { authenticity_token: csrf_token, back: "/teacher" }, remote_addr: EDGE)
    page("/teacher")
    assert_select ".flash", /Grafo approvato/
    assert_select "body[data-broadcast-notify-value=true]"
    on(:web, "/teacher/blueprint-revisions/#{@blueprint.id}/approve", method: :post, headers: TEACHER, params: { authenticity_token: csrf_token, back: "/teacher" }, remote_addr: EDGE)
    page("/teacher")
    assert_select ".flash.alert"
    assert_select "body[data-broadcast-notify-value=false]"
  end
end
