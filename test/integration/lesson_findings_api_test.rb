require "test_helper"
require_relative "../support/course_rows"

# D-313: the findings of a lesson review are first-class in the agent API: each has an id (L<review>-<n>), the
# list shows them with the lesson, the revision, the card and the latest response, and the author answers them
# with the rules of the item findings (D-220). A response never disposes of a finding; nothing here decides.
class LessonFindingsApiTest < ActionDispatch::IntegrationTest
  include CourseRows

  KEY = "ripasso.math.demo".freeze

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "lesson findings test")
    build_course
    @rev1 = make_lesson(KEY)
    @lesson = @rev1.lesson
    @reviewer = session!(:reviewer, "gpt-5.2")
    @author = session!(:author, "claude-opus-5-5")
    @review = review!(@rev1, [ finding("major", card: 3, block: 2), finding("minor", card: 0), finding("blocker", section: "solutions", exercise: 2) ])
    @major = "L#{@review.id}-1"
    @blocker = "L#{@review.id}-3"
  end

  def session!(role, model = "claude-test") = AgentSession.create!(label: "t", role: role.to_s, agent: "test", model: model)

  def finding(severity, **where)
    { "severity" => severity, "quote" => "bilancia", "problem_it" => "Problema #{severity}.", "fix_it" => "Correggi la frase." }.merge(where.transform_keys(&:to_s))
  end

  def review!(revision, findings, session: @reviewer)
    LessonReview.create!(lesson_revision: revision, agent_session: session, checklist_json: "[]", recomputed_json: "[]", findings_json: JSON.generate(findings))
  end

  def api(path, method: :get, body: nil, as: nil, dry: false)
    headers = { "Authorization" => "Bearer #{@token}" }
    headers["X-Banco-Session"] = as.id.to_s if as
    headers["X-Banco-Dry-Run"] = "1" if dry
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil)
  end

  def json = response.parsed_body

  def respond(id, doc, as: @author, dry: false) = api("/api/v1/findings/#{id}/responses", method: :post, body: { response: doc }, as: as, dry: dry)

  def list(query = "") = api("/api/v1/subjects/math/findings#{"?#{query}" unless query.empty?}").then { json["rows"] }

  def right = { stance: "lesson_right", note_it: "La lezione è giusta. La bilancia è solo un esempio." }

  def decide!(kind, payload)
    Decision.create!(kind: kind, subject: @subject, payload_json: payload.to_json, request_id: SecureRandom.uuid, teacher_login: "nik", remote_addr: "127.0.0.1")
  end

  test "the list names each lesson finding: id, lesson, revision, card, severity and text; minor ones only with all" do
    rows = list("kind=lesson")
    assert_response :success
    assert_equal [ @major, @blocker ], rows.map { |r| r["finding_id"] }
    record_example "findings list", "lesson-rows"
    assert_equal({ "kind" => "lesson", "lesson" => KEY, "review_id" => @review.id, "revision_id" => @rev1.id, "seq" => 1, "current" => true, "pinned" => false,
                   "severity" => "major", "card" => 3, "block" => 2, "quote" => "bilancia", "problem_it" => "Problema major.", "fix_it" => "Correggi la frase." },
                 rows.first.except("finding_id"))
    assert_equal [ "solutions", 2 ], rows.last.values_at("section", "exercise")
    assert_equal [ @major, "L#{@review.id}-2", @blocker ], list("kind=lesson&all=1").map { |r| r["finding_id"] }
    assert_equal 0, list("all=1&kind=lesson").find { |r| r["severity"] == "minor" }["card"]

    # Without kind: the items' rows first (kind item), then the lessons'.
    item = make_revision("lf-item", "math.number")
    review = ItemReview.create!(item_revision: item, agent_session: @reviewer, checklist_json: "[]")
    ReviewFinding.create!(item_revision: item, source: "review", item_review: review, severity: "major", field: "stem", quote: "x", problem_it: "Ambiguo.", fix_it: "Chiarisci.")
    assert_equal %w[item lesson lesson], list.map { |r| r["kind"] }
    assert_equal %w[item], list("kind=item").map { |r| r["kind"] }
    api("/api/v1/subjects/math/findings?kind=page")
    assert_response :not_found
    assert_equal [ "E-NOT-FOUND", "kind" ], json.values_at("code", "field")
  end

  test "lesson keeps one lesson's findings, topic the topic's lesson and the items its latest revision pins" do
    other = make_lesson("ripasso.math.other")
    review!(other, [ finding("major", card: 1) ])
    pinned = make_practice_item("lf-pinned", "math.number")
    loose = make_practice_item("lf-loose", "math.number")
    [ pinned, loose ].each do |rev|
      review = ItemReview.create!(item_revision: rev, agent_session: @reviewer, checklist_json: "[]")
      ReviewFinding.create!(item_revision: rev, source: "review", item_review: review, severity: "major", field: "stem", quote: "x", problem_it: "Ambiguo.", fix_it: "Chiarisci.")
    end
    make_topic(@rev1, { "math.number" => [ pinned ] })

    assert_equal [ @major, @blocker ], list("lesson=#{KEY}").map { |r| r["finding_id"] }
    rows = list("topic=#{KEY}")
    assert_equal [ [ "item", "lf-pinned" ], [ "lesson", KEY ], [ "lesson", KEY ] ], rows.map { |r| [ r["kind"], r["item"] || r["lesson"] ] }
    assert rows.select { |r| r["kind"] == "lesson" }.all? { |r| r["pinned"] }
    assert_equal %w[lesson lesson], list("topic=#{KEY}&kind=lesson").map { |r| r["kind"] }
    assert_empty list("lesson=ripasso.math.other&topic=#{KEY}")
    assert_equal [ "ripasso.math.other" ], list("lesson=ripasso.math.other").map { |r| r["lesson"] }

    api("/api/v1/subjects/math/findings?lesson=ripasso.math.nothing")
    assert_response :not_found
    assert_equal "lesson", json["field"]
    api("/api/v1/subjects/math/findings?topic=ripasso.math.nothing")
    assert_equal [ 404, "topic" ], [ response.status, json["field"] ]
  end

  test "an author answers lesson_right; the answer is stored, listed and disposes of nothing" do
    decisions = Decision.count
    respond(@major, right)
    assert_response :created, json.inspect
    record_example "findings respond", "lesson-created"
    row = LessonFindingResponse.sole
    assert_equal [ @review.id, 1, @author.id, "lesson_right", nil ], [ row.lesson_review_id, row.finding_n, row.agent_session_id, row.stance, row.lesson_revision_id ]
    assert_equal [ @major, "lesson", KEY, nil ], json.values_at("finding_id", "kind", "lesson", "decision")
    assert_equal decisions, Decision.count

    by_id = list("kind=lesson").index_by { |r| r["finding_id"] }
    assert_equal [ "lesson_right", "La lezione è giusta. La bilancia è solo un esempio." ], by_id[@major]["response"].values_at("stance", "note_it")
    assert_equal [ @blocker ], list("kind=lesson&open=1").map { |r| r["finding_id"] }

    # lesson open and lesson status carry the id and the latest response inside each review.
    api("/api/v1/lessons/#{KEY}")
    findings = json["reviews"].first["findings"]
    assert_equal [ @major, "L#{@review.id}-2", @blocker ], findings.map { |f| f["id"] }
    assert_equal "lesson_right", findings.first.dig("response", "stance")
    assert_nil findings.last["response"]
    api("/api/v1/lesson-revisions/#{@rev1.id}")
    assert_equal @major, json["reviews"].first["findings"].first["id"]
  end

  test "fixed needs a later revision of the same lesson; the stances are lesson_right and fixed" do
    note = "Ho riscritto la scheda 3."
    respond(@blocker, { stance: "fixed", note_it: note })
    assert_equal [ 422, "response/revision_id" ], [ response.status, json["field"] ]
    respond(@blocker, { stance: "fixed", revision_id: @rev1.id, note_it: note })
    assert_response :unprocessable_entity
    other = make_lesson("ripasso.math.other")
    respond(@blocker, { stance: "fixed", revision_id: other.id, note_it: note })
    assert_response :unprocessable_entity
    respond(@blocker, { stance: "fixed", revision_id: 999_999, note_it: note })
    assert_response :unprocessable_entity
    respond(@blocker, { stance: "item_right", note_it: note })
    assert_equal "response/stance", json["field"]
    assert_match(/lesson_right or fixed.*item_right is for the findings of an item/, json["message"])
    newer = make_lesson(KEY)
    respond(@blocker, right.merge(revision_id: newer.id))
    assert_equal "response/revision_id", json["field"]
    respond(@blocker, { stance: "fixed", revision_id: newer.id.to_s, note_it: note })
    assert_response :created, json.inspect
    assert_equal [ newer.id, 2 ], json.values_at("revision_id", "seq")
    assert_equal 1, LessonFindingResponse.count
  end

  test "only an author session answers, never the one that raised the finding or a reviewer of the lesson" do
    respond(@major, right, as: @reviewer)
    assert_equal [ 422, "E-SESSION-ROLE" ], [ response.status, json["code"] ]
    respond(@major, right, as: nil)
    assert_equal "E-SESSION", json["code"]
    # An author-role session that filed a review of the lesson is refused, the raising one with its own message.
    raiser = session!(:author)
    raised = review!(make_lesson(KEY), [ finding("major", card: 1) ], session: raiser)
    respond("L#{raised.id}-1", right, as: raiser)
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
    assert_match(/raised finding L#{raised.id}-1/, json["message"])
    respond(@major, right, as: raiser)
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
    assert_match(/already acted as reviewer on #{KEY}/, json["message"])
    assert_equal 0, LessonFindingResponse.count
  end

  test "an unknown id is 404, a dry run stores nothing, and the answer is checked like an item's" do
    respond("L999999-1", right)
    assert_equal [ 404, "E-NOT-FOUND" ], [ response.status, json["code"] ]
    respond("L#{@review.id}-9", right)
    assert_response :not_found
    respond(@major, right, dry: true)
    assert_response :ok
    assert_equal [ true, "passed" ], json.values_at("dry_run", "status")
    respond(@major, { stance: "lesson_right", note_it: "" })
    assert_equal "response/note_it", json["field"]
    respond(@major, { stance: "lesson_right", note_it: "Parola. " * 120 })
    assert_equal "response/note_it", json["field"]
    respond(@major, { stance: "lesson_right", note_it: "La lezione è **giusta** perché " + ("parola " * 60) + "." })
    assert_equal "E-READ", json["code"]
    respond(@major, right.merge(why: "x"))
    assert_equal "response/why", json["field"]
    api("/api/v1/findings/#{@major}/responses", method: :post, body: { answer: right }, as: @author)
    assert_equal "response", json["field"]
    assert_equal 0, LessonFindingResponse.count
  end

  test "open: no decision, no response, and on the current revision or the one the latest topic revision pins" do
    assert_equal [ @major, @blocker ], list("kind=lesson&open=1").map { |r| r["finding_id"] }
    make_lesson(KEY)
    assert_equal [ false, false ], list("kind=lesson").map { |r| r["current"] }
    assert_empty list("kind=lesson&open=1")
    topic = make_topic(@rev1, { "math.number" => [] })
    assert_equal [ @major, @blocker ], list("kind=lesson&open=1").map { |r| r["finding_id"] }

    decide!("approve_topic", { topic_revision_id: topic.id, topic: KEY, seq: topic.seq })
    assert_equal %w[topic_approved topic_approved], list("kind=lesson").map { |r| r["decision"] }
    assert_empty list("kind=lesson&open=1")
    decide!("send_back_lesson", { lesson_revision_id: @rev1.id, lesson: KEY, seq: 1, reason_code: "error", comment_it: "Rivedi." })
    assert_equal %w[sent_back sent_back], list("kind=lesson").map { |r| r["decision"] }
    respond(@major, right)
    assert_equal "sent_back", json["decision"]
  end

  test "a lesson finding id sent to the assess endpoint is a JSON refusal, not an HTML 404" do
    api("/api/v1/findings/#{@major}/assessments", method: :post, body: { assessment: { verdict: "finding_right", note_it: "Si." } }, as: session!(:arbiter))
    assert_response :unprocessable_entity
    assert_equal "E-NOT-FOUND", json["code"]
    assert_match(/lesson finding/, json["message"])
  end

  test "topic with open keeps a pinned item revision that a newer revision of the item supersedes" do
    pinned = make_practice_item("lf-old", "math.number")
    review = ItemReview.create!(item_revision: pinned, agent_session: @reviewer, checklist_json: "[]")
    ReviewFinding.create!(item_revision: pinned, source: "review", item_review: review, severity: "major", field: "stem", quote: "x", problem_it: "Ambiguo.", fix_it: "Chiarisci.")
    make_topic(@rev1, { "math.number" => [ pinned ] })
    ItemRevision.create!(item: pinned.item, seq: 2, body_json: pinned.body_json, file_sessions_json: "{}")

    assert_equal 1, list("topic=#{KEY}&kind=item").size
    assert_equal [ "lf-old" ], list("topic=#{KEY}&kind=item&open=1").map { |r| r["item"] }
    assert_empty list("kind=item&open=1")
  end

  test "the list and the answers carry nothing of the student" do
    student = Student.create!(key: "prova-7", kind: "student")
    topic = make_topic(@rev1, { "math.number" => [] })
    StudentQuestion.create!(student: student, client_question_id: "q-lf-1", topic_revision: topic, lesson_revision: @rev1, section: "idea", text_it: "Domanda riservata dello studente.")
    respond(@major, right)
    [ "/api/v1/subjects/math/findings?all=1", "/api/v1/subjects/math/findings?topic=#{KEY}&all=1", "/api/v1/lessons/#{KEY}" ].each do |path|
      api(path)
      assert_response :success
      assert_no_match(/riservata|prova-7|student/i, response.body, path)
    end
  end
end
