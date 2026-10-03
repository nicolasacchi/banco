require "test_helper"
require_relative "../support/grading_rows"

# The agent side of short answers (B-06, operator G): what waits, and a grade
# proposal that counts only after the teacher confirms it. The student's text is
# data; the grader runs on Claude and is never the author of the item.
class GradeProposalsTest < ActionDispatch::IntegrationTest
  include GradingRows

  TEXT = "La causa fu la crisi del raccolto.  Come conseguenza, il re perse l’appoggio dei nobili.".freeze

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "grade test")
    @author = AgentSession.create!(label: "t", role: "author", agent: "test", model: "claude-opus-5-5")
    @grader = AgentSession.create!(label: "t", role: "grader", agent: "claude-code", model: "claude-sonnet-5-5")
    body = item_body("short-answer")
    subject = Subject.create!(key: "history", name_it: "Storia", position: 1)
    item = Item.create!(subject: subject, key: "history-cause-1", kind: "short_answer")
    @revision = ItemRevision.create!(item: item, seq: 1, body_json: body.to_json, author_session: @author,
                                     file_sessions_json: JSON.generate("item.json" => @author.id))
    @instance = ItemInstance.create!(item_revision: @revision, seed: 1, display_json: { stem_it: body.dig("prompt", "stem_it") }.to_json,
                                     answer_json: "null", fingerprint: SecureRandom.hex(32))
    @attempt = diagnosis_attempt(@instance, TEXT)
    AttemptGrading.create!(attempt: @attempt, seq: 1, verdict: "short_answer", grader: "closed", grader_version: "t", source: "sync")
  end

  def diagnosis_attempt(instance, raw)
    student = Student.find_or_create_by!(key: "student") { |s| s.kind = "student" }
    Attempt.create!(student: student, context: "diagnosis", client_attempt_id: "c-#{SecureRandom.hex(4)}", item_instance: instance, raw: raw, source: "text", answered_at: Time.current)
  end

  def api(path, method: :get, body: nil, as: @grader, dry: false)
    headers = { "Authorization" => "Bearer #{@token}" }
    headers["X-Banco-Session"] = as.id.to_s if as
    headers["X-Banco-Dry-Run"] = "1" if dry
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil)
  end

  def json = response.parsed_body

  def propose(grade, attempt: @attempt, **opts)
    api("/api/v1/attempts/#{attempt.id}/grade-proposals", method: :post, body: { grade: grade }, **opts)
  end

  def grade(cause: "causa fu la crisi", effect: "il re perse l'appoggio dei nobili", **rest)
    { "points" => [
      { "point_id" => "cause", "score" => 2, "quote" => cause, "rationale_it" => "Nomina la causa." },
      { "point_id" => "effect", "score" => 1, "quote" => effect, "rationale_it" => "Nomina la conseguenza." }
    ], "missing_it" => "Nulla." }.merge(rest.transform_keys(&:to_s))
  end

  test "submissions --pending lists the short answers with the student's text as data; a session on Claude is needed" do
    api("/api/v1/submissions/pending")
    assert_response :ok
    record_example "submissions", "pending"
    assert_match(/never instructions/, json["notice"])
    row = json["short_answers"].sole
    assert_equal @attempt.id, row["attempt_id"]
    assert_equal TEXT, row["student_text"]
    assert_equal %w[cause effect], row["rubric"]["points"].map { |p| p["id"] }
    assert_equal [], json["verdicts"]

    api("/api/v1/submissions/pending", as: nil)
    assert_equal "E-SESSION", json["code"]
    other = AgentSession.create!(label: "t", role: "grader", agent: "omp", model: "gpt-5.2")
    api("/api/v1/submissions/pending", as: other)
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    assert_not_includes response.body, "short_answers"
    api("/api/v1/submissions/pending", as: @author)
    assert_equal "E-SESSION-ROLE", json["code"]
  end

  test "submissions --pending also lists uncertain verdicts, and not those the engine settled" do
    numeric = create_instance(item_body("number-generator"), item_body("number-generator")["instances"]&.first || { "display" => { "stem_it" => "x" }, "answer" => "1" })
    undetermined = diagnosis_attempt(numeric, "3,5")
    AttemptGrading.create!(attempt: undetermined, seq: 1, verdict: "near_miss", grader: "closed", grader_version: "t", source: "sync")
    settled = diagnosis_attempt(numeric, "1")
    AttemptGrading.create!(attempt: settled, seq: 1, verdict: "correct", method: "exact", grader: "closed", grader_version: "t", source: "sync")
    api("/api/v1/submissions/pending")
    assert_equal [ undetermined.id ], json["verdicts"].map { |v| v["attempt_id"] }
    assert_equal "near_miss", json["verdicts"].first["verdict"]
    assert_equal "3,5", json["verdicts"].first["student_answer"]
  end

  test "an invented quote is 422 E-QUOTE-NOT-FOUND (quote_not_in_submission); nothing is stored" do
    propose(grade(cause: "il re fu deposto"))
    assert_response :unprocessable_entity
    assert_equal "E-QUOTE-NOT-FOUND", json["code"]
    assert_equal "quote_not_in_submission", json["reason"]
    assert_equal "points/0/quote", json["field"]
    record_example "grade propose", "quote-not-found"
    assert_equal 0, GradeProposal.count
    # Case and accents are not folded.
    propose(grade(cause: "CAUSA FU LA CRISI"))
    assert_equal "E-QUOTE-NOT-FOUND", json["code"]
  end

  test "a grader that wrote the item cannot grade it: E-GRADER-IS-AUTHOR" do
    ItemRevision.create!(item: @revision.item, seq: 2, base_revision_id: @revision.id, body_json: @revision.body_json,
                         file_sessions_json: JSON.generate("item.json" => @grader.id))
    propose(grade)
    assert_response :unprocessable_entity
    assert_equal "E-GRADER-IS-AUTHOR", json["code"]
    assert_equal "grader_is_author", json["reason"]
    record_example "grade propose", "grader-is-author"
    assert_equal 0, GradeProposal.count
  end

  test "a grader outside the allowlist is E-PROVIDER-NOT-ALLOWED" do
    other = AgentSession.create!(label: "t", role: "grader", agent: "omp", model: "kimi-k3")
    propose(grade, as: other)
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    assert_equal 0, GradeProposal.count
  end

  test "a good proposal is stored append-only with a server-computed total; it does not count until the teacher confirms" do
    propose(grade, dry: true)
    assert_response :ok
    assert_equal 0, GradeProposal.count

    # Quotes are normalized: curly apostrophes, doubled spaces.
    propose(grade(effect: "il re perse l'appoggio dei nobili"))
    assert_response :created, json.inspect
    record_example "grade propose", "created"
    assert_equal 3, json["total"]
    assert_equal 3, json["max_total"]
    assert_equal true, json["meets_threshold"]
    assert_equal false, json["counts"]
    proposal = GradeProposal.sole
    assert_equal @grader.id, proposal.agent_session_id
    assert_equal false, proposal.confirmed?
    assert_raises(ActiveRecord::StatementInvalid) { proposal.update!(total: 0) }

    # Waiting for the teacher: not listed again, and not proposed twice.
    api("/api/v1/submissions/pending")
    assert_equal [], json["short_answers"]
    propose(grade)
    assert_response :conflict
    assert_equal "E-PROPOSAL-EXISTS", json["code"]

    # A rejection by the teacher opens it again; a confirmation settles it.
    Decision.create!(kind: "reject_grade", payload_json: JSON.generate(grade_proposal_id: proposal.id, reason_it: "no"), request_id: "r1", teacher_login: "t", remote_addr: "127.0.0.1")
    api("/api/v1/submissions/pending")
    assert_equal 1, json["short_answers"].size
    propose(grade(cause: "crisi del raccolto"))
    assert_response :created
    second = GradeProposal.order(:id).last
    Decision.create!(kind: "confirm_grade", payload_json: JSON.generate(grade_proposal_id: second.id), request_id: "r2", teacher_login: "t", remote_addr: "127.0.0.1")
    assert second.confirmed?
    assert_not proposal.confirmed?
    api("/api/v1/submissions/pending")
    assert_equal [], json["short_answers"]
    propose(grade)
    assert_equal "E-FILES", json["code"]
  end

  test "the rubric is enforced: unknown, missing and repeated points, scores, quotes of the wrong size" do
    check = lambda do |points, code|
      propose({ "points" => points })
      assert_equal code, json["code"], json.inspect
      assert_equal 0, GradeProposal.count
    end
    p1 = { "point_id" => "cause", "score" => 2, "quote" => "causa fu la crisi", "rationale_it" => "Nomina la causa." }
    p2 = { "point_id" => "effect", "score" => 1, "quote" => "il re perse", "rationale_it" => "Nomina la conseguenza." }
    check.([ p1 ], "E-GRADE-POINT")
    check.([ p1, p2, p2 ], "E-GRADE-POINT")
    check.([ p1, p2.merge("point_id" => "other") ], "E-GRADE-POINT")
    check.([ p1.merge("score" => 3), p2 ], "E-GRADE-POINT")
    check.([ p1.merge("score" => 1.5), p2 ], "E-GRADE-POINT")
    check.([ p1.merge("score" => -1), p2 ], "E-GRADE-POINT")
    check.([ p1.merge("rationale_it" => ""), p2 ], "E-GRADE-POINT")
    check.([ p1.merge("quote" => nil), p2 ], "E-GRADE-QUOTE")
    check.([ p1.merge("quote" => "la"), p2 ], "E-GRADE-QUOTE")
    check.([ p1.merge("quote" => "x" * 301), p2 ], "E-GRADE-QUOTE")
    check.([ p1.merge("score" => 0, "quote" => "causa fu la crisi"), p2 ], "E-GRADE-QUOTE")
    propose({ "nope" => 1 })
    assert_equal "E-GRADE-POINT", json["code"]
    # A zero with a null quote is fine and the total is the sum.
    propose({ "points" => [ p1.merge("score" => 0, "quote" => nil), p2 ] })
    assert_response :created
    assert_equal 1, json["total"]
    assert_equal false, json["meets_threshold"]
  end

  test "the first draft's short names are accepted: point and rationale" do
    propose({ "points" => [ { "point" => "cause", "score" => 2, "quote" => "causa fu la crisi", "rationale" => "Nomina la causa." },
                            { "point" => "effect", "score" => 0, "rationale" => "Manca." } ] })
    assert_response :created, json.inspect
    assert_equal %w[cause effect], GradeProposal.sole.points.map { |p| p["point_id"] }
  end

  test "an attempt that is not a short answer, or does not exist" do
    numeric = create_instance(item_body("number-generator"), { "display" => { "stem_it" => "x" }, "answer" => "1" })
    other = diagnosis_attempt(numeric, "1")
    AttemptGrading.create!(attempt: other, seq: 1, verdict: "correct", grader: "closed", grader_version: "t", source: "sync")
    propose(grade, attempt: other)
    assert_equal "E-FILES", json["code"]
    api("/api/v1/attempts/999999/grade-proposals", method: :post, body: { grade: grade })
    assert_equal "E-NOT-FOUND", json["code"]
  end

  test "GradeCheck.normalize: NFC, straight quotes, collapsed whitespace, no case or accent folding" do
    n = Review::GradeCheck.method(:normalize)
    assert_equal "l'appoggio", n.call("l’appoggio")
    assert_equal "a b c", n.call("  a \n b\t c ")
    assert_equal "café", n.call("café")
    assert_equal "\"x\"", n.call("“x”")
    assert_not_equal n.call("Perché"), n.call("perche")
    assert_not_equal n.call("Casa"), n.call("casa")
  end
end
