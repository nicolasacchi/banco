require "test_helper"
require_relative "../support/decision_world"

# The teacher's read-only pages (C-04): home, graph, entry test (overview and one screen per
# skill), evening corrections, report; and what their forms post.
class TeacherPagesTest < ActionDispatch::IntegrationTest
  include DecisionWorld

  setup do
    build_decision_world
    @prima = SyllabusSource.create!(key: "prima-2025-26", line_count: 3, sha256: "0" * 64)
    [ [ 1, "Equazioni di primo grado." ], [ 2, "Frazioni." ], [ 91, "Cellule." ] ].each do |n, text|
      SyllabusLine.create!(syllabus_source: @prima, number: n, text: text, origin: "pdf")
    end
  end

  def page(path, headers: TEACHER) = on(:web, path, headers: headers, remote_addr: EDGE)

  test "every teacher page answers the teacher and nobody else" do
    paths = [ "/teacher", "/teacher/subjects/math/graph", "/teacher/subjects/math/test", "/teacher/subjects/math/test/skills/math.number",
              "/teacher/subjects/math/report", "/teacher/corrections", "/teacher/items/#{@short.id}/play" ]
    paths.each do |path|
      page(path)
      assert_response :success, path
      page(path, headers: { "Remote-User" => "student", "Remote-Groups" => "banco-student" })
      assert_response :forbidden, path
      on(:web, path, remote_addr: "127.0.0.1")
      assert_response :forbidden, path
      on(:api, path)
      assert_response :not_found, path
    end
    page("/teacher/subjects/nothing/graph")
    assert_response :not_found
    page("/teacher/subjects/math/test/skills/math.nothing")
    assert_response :not_found
  end

  test "home lists the subject with its stage, what waits and the measured minutes" do
    Teacher::Minutes.record("math:graph", now: 5.minutes.ago)
    page "/teacher"
    assert_select "li.subject[data-subject=math][data-stage]"
    assert_select "li[data-waiting=graph_to_approve]", /grafo aspetta/i
    assert_select "#waiting-summary li", /Una materia aspetta/
    assert_select "#waiting-summary li", /1 minuto/
    assert_select "a[href='/teacher/subjects/math/graph']"
    assert_select "a[href='/teacher/subjects/math/test']"
    assert_select "a[href='/teacher/subjects/math/report']"
    assert_select "#waiting-summary a[href='/teacher/corrections']"
  end

  test "the graph screen shows scope labels, edges, cited programme lines, flags and the diff" do
    graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    body = JSON.parse(graph.body_json)
    body["skills"][0].merge!("scope" => "in_progress", "prerequisites" => [], "refs" => [ { "source" => "prima-2025-26", "line" => 1, "role" => "taught_in", "fragment" => "equazioni" } ])
    body["skills"][1].merge!("scope" => "not_in_prima", "prerequisites" => [ body["skills"][0]["key"] ],
                             "refs" => [ { "source" => "prima-2025-26", "line" => 91, "role" => "taught_in", "fragment" => "cellule" } ])
    body["skills"][2].merge!("scope" => "middle_school", "scope_reason_it" => "Appresa alla scuola media.")
    body["excluded"] = [ { "line" => 2, "reason_it" => "Non serve." } ]
    revision = SkillGraphRevision.create!(subject: @subject, seq: 2, body_json: body.to_json, author_session: graph.author_session)
    approve_graph_row!(@subject, graph)

    page "/teacher/subjects/math/graph"
    assert_select "article.skill[data-scope=in_progress] strong", /☆/
    assert_select "article.skill[data-scope=not_in_prima] strong", /Non in prima/
    assert_select "article.skill[data-scope=middle_school]", /Appresa alla scuola media/
    assert_select "article.skill[data-scope=not_in_prima] .edges", /Richiede: #{Regexp.escape(body['skills'][0]['key'])}/
    assert_select "li[data-ref='prima-2025-26:1'] q", "Equazioni di primo grado."
    assert_select "article.skill [data-flag=q3_lines_91_100]"
    assert_select "article.skill[data-skill='#{body['skills'][3]['key']}'] [data-inferred]"
    assert_select "#graph-excluded li", /Frazioni/
    assert_select "#graph-diff li[data-change=changed]"
    assert_select "#graph-diff", /Cambiata/
    assert_select "form[action='/teacher/skill-graph-revisions/#{revision.id}/approve']"
    assert_select "#graph-approve button[disabled]", 0 if ENV["BANCO_DECISIONS_ENABLED"] == "1"
  end

  test "the test overview keeps approve disabled with the reasons until the gates pass, then enables it" do
    page "/teacher/subjects/math/test"
    assert_select "#test-approve[data-approvable=false] button[disabled]"
    assert_select "#test-approve .reasons li", /Prima approva il grafo/
    assert_select "#test-approve .reasons li", /Il controllo meccanico|Manca la revisione|Apri la schermata|Gioca il test/
    assert_select "#test-traces tr[data-script=all_correct], #test-traces tr[data-script=all-correct]"

    approve_graph_row!
    make_blueprint_approvable!
    page "/teacher/subjects/math/test"
    assert_select "#test-approve[data-approvable=true] button:not([disabled])", /Approva il test/
    assert_select "form[action='/teacher/blueprint-revisions/#{@blueprint.id}/approve']"
  end

  test "the skill screen opens each item for the gate, shows samples, keys, errors and the forms" do
    page "/teacher/subjects/math/test/skills/math.number"
    assert_response :success
    number = @world[:revisions]["number"]
    assert_select "article.item-card[data-revision='#{number.id}']"
    assert_select "article.item-card .sample", 4
    assert_select "[data-key]", /\d/
    assert_select "ul.errors li strong", "adds_wrong"
    assert_select "a[data-play='#{number.id}']"
    assert_select "form[action='/teacher/item-revisions/#{number.id}/send-back'] select[name=reason_code] option", Teacher::SendBacks::CODES.size
    assert_includes Approval::BlueprintGate.viewed_ids, number.id
    page "/teacher/subjects/math/test/skills/math.number"
    assert_equal 1, AppEvent.where(kind: "teacher_viewed_item").count { |e| JSON.parse(e.payload_json)["item_revision_id"] == number.id }
  end

  test "the student's computer opens the skill screen but writes nothing" do
    cookies[DecisionRecorder::DEVICE_COOKIE] = "x"
    before = AppEvent.count
    page "/teacher/subjects/math/test/skills/math.number"
    assert_response :success
    assert_equal before, AppEvent.count
  end

  test "findings show with their disposition and a fix request says a new revision is expected" do
    number = @world[:revisions]["number"]
    finding = ReviewFinding.create!(item_revision: number, source: "review", severity: "major", field: "stem", quote: "x", problem_it: "Ambiguo.", fix_it: "Chiarisci.")
    page "/teacher/subjects/math/test/skills/math.number"
    assert_select "[data-finding='#{finding.id}'] form[action='/teacher/findings/#{finding.id}/disposition'] button[value=dismissed]"
    Decision.create!(kind: "dispose_finding", subject: @subject, payload_json: { finding_id: finding.id, disposition: "fix_requested", reason_it: "Sì." }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE)
    page "/teacher/subjects/math/test/skills/math.number"
    assert_select "[data-finding='#{finding.id}'][data-disposition=fix_requested] .decided", /nuova/
  end

  test "Rimanda records a decision the agent reads in work open, and the revision is no longer approvable" do
    number = @world[:revisions]["number"]
    token = ApiToken.issue!(role: "agent_claude", label: "t")
    decide("/teacher/item-revisions/#{number.id}/send-back", { reason_code: "wrong_key", comment_it: "La chiave del secondo caso è 7." })
    assert_response :success
    decision = Decision.where(kind: "send_back_item").sole
    assert_equal "wrong_key", JSON.parse(decision.payload_json)["reason_code"]

    on(:api, "/api/v1/work/items/#{number.item.key}", headers: { "Authorization" => "Bearer #{token}" })
    comments = response.parsed_body["teacher_comments"]
    assert_equal [ [ number.id, "wrong_key", "La chiave del secondo caso è 7." ] ], comments.map { |c| c.values_at("revision_id", "reason_code", "comment_it") }
    assert_includes Review::Gate.check(number).reasons, "the teacher sent this revision back: a new revision is needed"

    decide("/teacher/item-revisions/#{number.id}/send-back", { reason_code: "nope", comment_it: "x y z" })
    assert_response :unprocessable_entity
    decide("/teacher/item-revisions/#{number.id}/send-back", { reason_code: "other", comment_it: "" })
    assert_response :unprocessable_entity
  end

  test "a form post redirects back with a sentence in Italian, a refusal says why in Italian" do
    graph = @graph
    token = csrf_token
    on(:web, "/teacher/skill-graph-revisions/#{graph.id}/approve", method: :post, headers: TEACHER, params: { authenticity_token: token, back: "/teacher/subjects/math/graph" }, remote_addr: EDGE)
    assert_redirected_to "/teacher/subjects/math/graph"
    page "/teacher/subjects/math/graph"
    assert_select ".flash", /Grafo approvato/

    on(:web, "/teacher/blueprint-revisions/#{@blueprint.id}/approve", method: :post, headers: TEACHER,
       params: { authenticity_token: csrf_token, back: "https://evil.example/x" }, remote_addr: EDGE)
    assert_redirected_to "/teacher"
    page "/teacher"
    assert_select ".flash.alert", /Gioca il test fino in fondo|Il controllo meccanico|Apri la schermata/
  end

  test "the evening screen marks the grader's quotes in the student's text and lists uncertain verdicts" do
    attempt = @attempt
    attempt_instance = attempt.item_instance
    @proposal = GradeProposal.create!(attempt: attempt, agent_session: @session, total: 1, max_total: 2, threshold: 0.6, meets_threshold: false,
                                      points_json: JSON.generate([ { point_id: "a", score: 1, quote: "Una risposta", rationale_it: "Dice una cosa." }, { point_id: "b", score: 0, quote: nil, rationale_it: "Non c'è." } ]))
    page "/teacher/corrections"
    assert_select "article.short[data-attempt='#{attempt.id}'] [data-student-text] mark", "Una risposta"
    assert_select "article.short form[action='/teacher/grade-proposals/#{@proposal.id}/confirm']"
    assert_select "article.short form[action='/teacher/grade-proposals/#{@proposal.id}/reject']"
    assert_select "article.short details input[name='scores[a]']"
    assert attempt_instance
  end

  test "segments mark quotes after normalization and merge overlaps" do
    segments = Teacher::Corrections.segments("Il re  perse l’appoggio dei nobili.", [ "re perse", "perse l'appoggio", nil, "assente" ])
    assert_equal [ [ "Il ", false ], [ "re perse l'appoggio", true ], [ " dei nobili.", false ] ], segments
    assert_equal [ [ "ciao", false ] ], Teacher::Corrections.segments("ciao", [])
  end

  test "the report page carries the sitting condition, the versions and the signals" do
    page "/teacher/subjects/math/report"
    assert_select "#report-condition strong", /senza sorveglianza/
    assert_select "#report-state", /Test d'ingresso usato/
  end

  test "the heartbeat records one minute at most per minute and never from the student's computer" do
    token = csrf_token
    on(:web, "/teacher/activity", method: :post, headers: TEACHER.merge("Accept" => "application/json", "X-CSRF-Token" => token), params: { unit: "math:graph" }, remote_addr: EDGE)
    assert_equal true, response.parsed_body["recorded"]
    on(:web, "/teacher/activity", method: :post, headers: TEACHER.merge("Accept" => "application/json", "X-CSRF-Token" => token), params: { unit: "math:graph" }, remote_addr: EDGE)
    assert_equal false, response.parsed_body["recorded"]
    assert_equal({ "math:graph" => 1 }, Teacher::Minutes.summary[:by_unit])
    assert_equal false, Teacher::Minutes.record("nonsense:unit")
    assert_equal true, Teacher::Minutes.record("evening", now: Time.current + 2.minutes)
    assert_equal 2, Teacher::Minutes.summary[:total]
  end
end
