require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/arbiter_rows"

# D-220: the author answers blocker and major findings; the teacher alone decides.
class FindingsApiTest < ActionDispatch::IntegrationTest
  include CourseRows
  include ArbiterRows

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

  test "open=1 leaves out findings on superseded revisions; the full list keeps them as current: false" do
    later_revision
    api("/api/v1/subjects/math/findings")
    assert_equal [ false, false ], json["rows"].map { |r| r["current"] }
    api("/api/v1/subjects/math/findings?open=1")
    assert_empty json["rows"]
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

  # D-222: the third reviewer.
  def assess(finding, doc, as:, headers: {})
    api("/api/v1/findings/#{finding.id}/assessments", method: :post, body: { assessment: doc }, as: as, headers: headers)
  end

  def judgement(verdict = "author_right") = { verdict: verdict, note_it: "Ho confrontato la chiave con il calcolo a mano." }

  test "an arbiter assesses a finding; the opinion is stored and decides nothing" do
    first = arbiter_session
    assess(@blind_finding, judgement, as: first)
    assert_response :created, json.inspect
    record_example "findings assess", "created"
    row = FindingAssessment.sole
    assert_equal [ @blind_finding.id, first.id, "author_right" ], [ row.review_finding_id, row.agent_session_id, row.verdict ]
    assert_equal "first", json["opinion"].to_s
    assert_equal 0, Decision.count
    assert_nil @blind_finding.reload.disposition
    assess(@minor, judgement("finding_right"), as: first)
    assert_response :created
  end

  test "an arbiter on another model than the two allowed, or an author, is refused" do
    assess(@blind_finding, judgement, as: arbiter_session("claude-sonnet-4-5"))
    assert_response :unprocessable_entity
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    assess(@blind_finding, judgement, as: @author)
    assert_response :unprocessable_entity
    assert_equal "E-SESSION-ROLE", json["code"]
    assess(@blind_finding, judgement, as: nil)
    assert_response :unprocessable_entity
    assert_equal "E-SESSION", json["code"]
    assert_equal 0, FindingAssessment.count
  end

  test "an arbiter never runs on the model of the session that raised the finding; the author's model does not matter" do
    raiser = arbiter_session(ArbiterRows::FIRST_MODEL, role: "reviewer")
    review = ItemReview.create!(item_revision: @rev1, agent_session: raiser, checklist_json: "[]")
    raised = ReviewFinding.create!(item_revision: @rev1, source: "review", item_review: review, severity: "major", field: "stem", quote: "x", problem_it: "Altro.", fix_it: "Ok.")
    assess(raised, judgement, as: arbiter_session(ArbiterRows::FIRST_MODEL))
    assert_response :unprocessable_entity
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    assert_match(/raised the finding/, json["message"])
    assess(raised, judgement, as: arbiter_session(ArbiterRows::SECOND_MODEL))
    assert_response :created, json.inspect
    # An author of the item on the very model of the arbiter: no rule about it.
    author_model = arbiter_session(ArbiterRows::SECOND_MODEL, role: "author")
    ItemRevision.create!(item: @item, seq: @item.revisions.maximum(:seq) + 1, body_json: @rev1.body_json, file_sessions_json: "{}", author_session_id: author_model.id)
    assess(@blind_finding, judgement, as: arbiter_session(ArbiterRows::SECOND_MODEL))
    assert_response :created, json.inspect
  end

  test "an arbiter session that holds another role on the item is refused, many findings in one session are fine" do
    both = arbiter_session
    ItemReview.create!(item_revision: @rev1, agent_session: both, checklist_json: "[]")
    assess(@blind_finding, judgement, as: both)
    assert_response :unprocessable_entity
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
    fine = arbiter_session
    assess(@blind_finding, judgement, as: fine)
    assess(@review_finding, judgement, as: fine)
    assert_response :created
    # And once it has assessed, the same session cannot take a role it now excludes.
    assert_includes ItemSessions.new(@item).conflicts(fine.id, "reviewer"), "arbiter"
  end

  test "the verdict, the note and the members are checked; a dry run stores nothing" do
    me = arbiter_session
    assess(@blind_finding, { verdict: "maybe", note_it: "Va bene." }, as: me)
    assert_response :unprocessable_entity
    assert_equal "assessment/verdict", json["field"]
    assess(@blind_finding, { verdict: "unclear", note_it: "" }, as: me)
    assert_response :unprocessable_entity
    assess(@blind_finding, { verdict: "unclear", note_it: "Parola. " * 80 }, as: me)
    assert_response :unprocessable_entity
    assert_equal "assessment/note_it", json["field"]
    assess(@blind_finding, { verdict: "unclear", note_it: "La chiave è **giusta** perché " + ("parola " * 60) + "." }, as: me)
    assert_response :unprocessable_entity
    assert_equal "E-READ", json["code"]
    assess(@blind_finding, judgement.merge(disposition: "dismissed"), as: me)
    assert_response :unprocessable_entity
    api("/api/v1/findings/#{@blind_finding.id}/assessments", method: :post, body: { nope: 1 }, as: me)
    assert_response :unprocessable_entity
    assess(ReviewFinding.new(id: 99_999), judgement, as: me)
    assert_response :not_found
    assess(@blind_finding, judgement, as: me, headers: { "X-Banco-Dry-Run" => "1" })
    assert_response :success
    assert_equal true, json["dry_run"]
    assert_equal 0, FindingAssessment.count
  end

  test "an arbiter sees the other opinions of a finding only after assessing it; the list has minor findings with all=1" do
    one = arbiter_session(ArbiterRows::FIRST_MODEL)
    two = arbiter_session(ArbiterRows::SECOND_MODEL)
    assess(@blind_finding, judgement("finding_right"), as: one)
    row = ->(as) { api("/api/v1/subjects/math/findings", as: as); json["rows"].find { |r| r["finding_id"] == @blind_finding.id } }
    assert_equal "waiting", row.call(one)["opinion"]["state"]
    assert_nil row.call(two)["opinion"], "the second opinion is written blind"
    assert_nil row.call(arbiter_session(ArbiterRows::SECOND_MODEL))["opinion"]
    assert_equal "waiting", row.call(@author)["opinion"]["state"], "the author reads what there is"
    api("/api/v1/subjects/math/findings")
    assert_equal "waiting", json["rows"].find { |r| r["finding_id"] == @blind_finding.id }["opinion"]["state"]
    assess(@blind_finding, judgement("finding_right"), as: two)
    assert_response :created
    seen = row.call(two)["opinion"]
    assert_equal [ "clear", "finding_right" ], seen.values_at("state", "verdict")
    assert_equal [ ArbiterRows::FIRST_MODEL, ArbiterRows::SECOND_MODEL ], [ seen["first"]["model"], seen["second"]["model"] ]
    api("/api/v1/subjects/math/findings", as: one)
    assert_equal [ @review_finding.id, @blind_finding.id ], json["rows"].map { |r| r["finding_id"] }
    api("/api/v1/subjects/math/findings?all=1", as: one)
    assert_equal [ @review_finding.id, @blind_finding.id, @minor.id ], json["rows"].map { |r| r["finding_id"] }
  end

  test "the assessment route exists on the API listener only" do
    on(:web, "/api/v1/findings/#{@blind_finding.id}/assessments", method: :post, remote_addr: ListenerHelpers::EDGE_IP)
    assert_response :not_found
  end
end
