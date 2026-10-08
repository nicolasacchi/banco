require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"

# D-220: the author answers blocker and major findings; the teacher alone decides.
class FindingsApiTest < ActionDispatch::IntegrationTest
  include CourseRows

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "findings test")
    build_course
    @rev1 = make_revision("fa-1", "math.number")
    @item = @rev1.item
    @reviewer = session!(:reviewer)
    @solver = session!(:solver)
    @author = session!(:author)
    review = ItemReview.create!(item_revision: @rev1, agent_session: @reviewer, checklist_json: "[]")
    @review_finding = ReviewFinding.create!(item_revision: @rev1, source: "review", item_review: review, severity: "major", field: "stem", quote: "x",
                                            problem_it: "Ambiguo.", fix_it: "Chiarisci.")
    solve = BlindSolve.create!(item_revision: @rev1, agent_session: @solver, answers_json: "[]", results_json: "[]")
    @blind_finding = ReviewFinding.create!(item_revision: @rev1, source: "blind_solve", blind_solve: solve, severity: "blocker", instance: 2, field: "instances/2",
                                           quote: "q", problem_it: "Diversa.", fix_it: "Controlla.")
    @minor = ReviewFinding.create!(item_revision: @rev1, source: "review", item_review: review, severity: "minor", field: "stem", quote: "x", problem_it: "Lieve.", fix_it: "Ok.")
  end

  def session!(role) = AgentSession.create!(label: "t", role: role.to_s, agent: "test", model: "claude-test")

  def api(path, method: :get, body: nil, as: nil, headers: {})
    headers = { "Authorization" => "Bearer #{@token}" }.merge(headers)
    headers["X-Banco-Session"] = as.id.to_s if as
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil)
  end

  def json = response.parsed_body

  def respond(finding, doc, as: @author, headers: {})
    api("/api/v1/findings/#{finding.id}/responses", method: :post, body: { response: doc }, as: as, headers: headers)
  end

  def later_revision(item = @item)
    ItemRevision.create!(item: item, seq: item.revisions.maximum(:seq) + 1, body_json: @rev1.body_json, file_sessions_json: "{}")
  end

  test "the listing has blocker and major findings with disposition and the latest response" do
    api("/api/v1/subjects/math/findings")
    assert_response :success
    assert_equal [ @review_finding.id, @blind_finding.id ], json["rows"].map { |r| r["finding_id"] }
    record_example "findings list", "rows"
    assert_equal [ true, true ], json["rows"].map { |r| r["current"] }
    respond(@blind_finding, { stance: "item_right", note_it: "La chiave è giusta." })
    assert_response :created
    Decision.create!(kind: "dispose_finding", subject: @subject, payload_json: { finding_id: @review_finding.id, disposition: "dismissed", reason_it: "Sì." }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "nik", groups: "banco-teacher", remote_addr: "127.0.0.1")
    api("/api/v1/subjects/math/findings")
    by_id = json["rows"].index_by { |r| r["finding_id"] }
    assert_equal "dismissed", by_id[@review_finding.id]["disposition"]
    assert_equal [ "item_right", "La chiave è giusta." ], by_id[@blind_finding.id]["response"].values_at("stance", "note_it")
    api("/api/v1/subjects/math/findings?open=1")
    assert_empty json["rows"]
    api("/api/v1/subjects/nothing/findings")
    assert_response :not_found
  end

  test "an author answers item_right; the answer is stored and disposes of nothing" do
    respond(@blind_finding, { stance: "item_right", note_it: "Si scrive ce n'è: la regola dice così." })
    assert_response :created, json.inspect
    record_example "findings respond", "created"
    row = FindingResponse.sole
    assert_equal [ @blind_finding.id, @author.id, "item_right", nil ], [ row.review_finding_id, row.agent_session_id, row.stance, row.item_revision_id ]
    assert_nil json["disposition"]
    assert_equal 0, Decision.where(kind: "dispose_finding").count
    assert_nil @blind_finding.reload.disposition
  end

  test "fixed needs a later revision of the same item" do
    respond(@blind_finding, { stance: "fixed", note_it: "Ho cambiato la consegna." })
    assert_response :unprocessable_entity
    assert_equal "response/revision_id", json["field"]
    respond(@blind_finding, { stance: "fixed", revision_id: @rev1.id, note_it: "Ho cambiato la consegna." })
    assert_response :unprocessable_entity
    other = make_revision("fa-2", "math.number")
    respond(@blind_finding, { stance: "fixed", revision_id: other.id, note_it: "Ho cambiato la consegna." })
    assert_response :unprocessable_entity
    respond(@blind_finding, { stance: "fixed", revision_id: 999_999, note_it: "Ho cambiato la consegna." })
    assert_response :unprocessable_entity
    newer = later_revision
    respond(@blind_finding, { stance: "fixed", revision_id: newer.id.to_s, note_it: "Ho cambiato la consegna." })
    assert_response :created, json.inspect
    assert_equal [ newer.id, newer.seq ], json.values_at("revision_id", "seq")
    assert_equal 1, FindingResponse.count
    respond(@blind_finding, { stance: "item_right", revision_id: newer.id, note_it: "La chiave è giusta." })
    assert_response :unprocessable_entity
  end

  test "only an author session answers, and never the session that raised the finding" do
    respond(@review_finding, { stance: "item_right", note_it: "La chiave è giusta." }, as: @reviewer)
    assert_response :unprocessable_entity
    assert_equal "E-SESSION-ROLE", json["code"]
    respond(@review_finding, { stance: "item_right", note_it: "La chiave è giusta." }, as: nil)
    assert_response :unprocessable_entity
    assert_equal "E-SESSION", json["code"]
    # An author-role session that also holds the reviewer role on the item is refused, as is the raising session.
    other_review = ItemReview.create!(item_revision: @rev1, agent_session: @author, checklist_json: "[]")
    assert other_review
    respond(@review_finding, { stance: "item_right", note_it: "La chiave è giusta." })
    assert_response :unprocessable_entity
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
    assert_equal 0, FindingResponse.count
  end

  test "the raising session itself is refused even as an author-role row" do
    raised = ReviewFinding.create!(item_revision: @rev1, source: "review", item_review: ItemReview.create!(item_revision: @rev1, agent_session: @author, checklist_json: "[]"),
                                   severity: "major", field: "f", quote: "x", problem_it: "p", fix_it: "f")
    respond(raised, { stance: "item_right", note_it: "La chiave è giusta." })
    assert_response :unprocessable_entity
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
    assert_match(/raised finding/, json["message"])
  end

  test "the note is required, at most 700 characters and readable; unknown members and stances are refused" do
    respond(@blind_finding, { stance: "item_right", note_it: "" })
    assert_response :unprocessable_entity
    respond(@blind_finding, { stance: "item_right", note_it: "Parola. " * 120 })
    assert_response :unprocessable_entity
    assert_equal "response/note_it", json["field"]
    respond(@blind_finding, { stance: "item_right", note_it: "La chiave è **giusta** perché " + ("parola " * 60) + "." })
    assert_response :unprocessable_entity
    assert_equal "E-READ", json["code"]
    respond(@blind_finding, { stance: "maybe", note_it: "La chiave è giusta." })
    assert_response :unprocessable_entity
    respond(@blind_finding, { stance: "item_right", note_it: "La chiave è giusta.", disposition: "dismissed" })
    assert_response :unprocessable_entity
    api("/api/v1/findings/#{@blind_finding.id}/responses", method: :post, body: { nope: 1 }, as: @author)
    assert_response :unprocessable_entity
    respond(ReviewFinding.new(id: 99_999), { stance: "item_right", note_it: "La chiave è giusta." })
    assert_response :not_found
    assert_equal 0, FindingResponse.count
  end

  test "a dry run stores nothing; the latest response shows in work open" do
    respond(@blind_finding, { stance: "item_right", note_it: "La chiave è giusta." }, headers: { "X-Banco-Dry-Run" => "1" })
    assert_response :success
    assert_equal true, json["dry_run"]
    assert_equal 0, FindingResponse.count
    respond(@blind_finding, { stance: "item_right", note_it: "La chiave è giusta." })
    newer = later_revision
    respond(@blind_finding, { stance: "fixed", revision_id: newer.id, note_it: "Ho cambiato la consegna." })
    api("/api/v1/work/revisions/#{@rev1.id}")
    row = json["review_findings"].find { |f| f["id"] == @blind_finding.id }
    assert_equal [ "fixed", newer.id ], row["response"].values_at("stance", "revision_id")
    assert_nil json["review_findings"].find { |f| f["id"] == @minor.id }["response"]
  end

  test "the route exists on the API listener only" do
    on(:web, "/api/v1/findings/#{@blind_finding.id}/responses", method: :post, remote_addr: ListenerHelpers::EDGE_IP)
    assert_response :not_found
  end
end
