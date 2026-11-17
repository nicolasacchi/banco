require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"
require_relative "../support/student_ui_rows"

# D-333: the digest (`banco digest`) is the teacher's dashboard, the student's progress and next topics, the open comments, the answers
# that wait and the latest activity in one read. Every part is what its own endpoint answers for the same student: this test reads both
# and compares them. Invented content only.
class DigestApiTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld
  include StudentUiRows

  READ_ROLES = %w[bot_read teacher].freeze
  CONTENT_ROLES = %w[agent_claude agent_omp ci].freeze

  setup do
    build_progress_world
    # A short answer that waits for the teacher, in a subject of its own (the world of DecisionWorld, on the official student).
    geography = build_ui_subject(key: "geography", name: "Geografia", position: 2, approve: false)
    session = AgentSession.create!(label: "rev", role: "reviewer", agent: "omp", model: "gpt-5.2")
    run = DiagnosisRun.create!(student: @official, subject: geography[:subject], blueprint_revision: geography[:blueprint], sequence: 1, seed_salt: "s",
                               rules_version: "v1", engine_version: "e1")
    instance = geography[:revisions]["short_answer"].instances.order(:id).first
    event = DiagnosisEvent.create!(diagnosis_run: run, seq: 1, kind: "item_served", at: Time.current)
    ItemServed.create!(diagnosis_event: event, item_instance: instance, skill_key: skill_key("geography", "short_answer"))
    attempt = Attempt.create!(student: @official, context: "diagnosis", served_event: event, client_attempt_id: "c-1", item_instance: instance,
                              raw: "Una risposta.", source: "text", answered_at: Time.current)
    AttemptGrading.create!(attempt: attempt, seq: 1, verdict: "short_answer", grader: "closed", grader_version: "t", source: "sync")
    GradeProposal.create!(attempt: attempt, agent_session: session, points_json: [ { point_id: "a", score: 1 }, { point_id: "b", score: 0 } ].to_json,
                          total: 1, max_total: 2, threshold: 0.6, meets_threshold: false)
    # Seven open comments (one already read) and one closed: the digest lists the latest five.
    @comments = Array.new(7) { |i| make_comment("Domanda numero #{i + 1}.") }
    CommentEvent.create!(comment: @comments.first, kind: "read", origin: "web", actor: "nik", request_id: SecureRandom.uuid, remote_addr: "1.1.1.1")
    closed = make_comment("Era un errore mio.")
    CommentEvent.create!(comment: closed, kind: "resolved", origin: "web", actor: "nik", request_id: SecureRandom.uuid, remote_addr: "1.1.1.1")
    @tokens = (READ_ROLES + CONTENT_ROLES).to_h { |role| [ role, ApiToken.issue!(role: role, label: "digest #{role}", expires_at: 30.days.from_now, teacher_login: ("nik" if role == "teacher")) ] }
  end

  def make_comment(text, student: @official)
    Comment.create!(student: student, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "not_understood", text_it: text, page_path: "/today", page_kind: "today",
                    subject: @subject, viewport_width: 390, viewport_height: 800, theme: "cream", text_size: "normal")
  end

  def api(path, token: @tokens.fetch("bot_read")) = on(:api, path, headers: token ? { "Authorization" => "Bearer #{token}" } : {})

  def json = response.parsed_body

  # The body of another endpoint, parsed.
  def get_json(path, token: @tokens.fetch("bot_read"))
    api(path, token: token)
    assert_response :success, path
    json
  end

  test "no token is E-AUTH, every role that may read gets the same parts, a content agent's token is refused" do
    api("/api/v1/digest", token: nil)
    assert_response :unauthorized
    assert_equal "E-AUTH", json["code"]
    bodies = @tokens.slice(*READ_ROLES).map do |role, token|
      api("/api/v1/digest", token: token)
      assert_response :success, role
      response.parsed_body.except("generated_at")
    end
    assert_equal 1, bodies.uniq.size
    CONTENT_ROLES.each do |role|
      api("/api/v1/digest", token: @tokens.fetch(role))
      assert_response :forbidden, role
      assert_equal "token_role", json["reason"]
    end
  end

  test "its parts are the JSON of the separate endpoints for the same student" do
    digest = get_json("/api/v1/digest?student=student")
    assert_equal %w[activity answers_pending comments generated_at home next progress], digest.keys.sort
    assert_nothing_raised { Time.iso8601(digest["generated_at"]) }
    assert_equal get_json("/api/v1/teacher/home?student=student"), digest["home"]
    assert_equal get_json("/api/v1/students/student/progress"), digest["progress"]
    assert_equal get_json("/api/v1/students/student/next"), digest["next"]
    assert_equal "math", digest["next"]["subjects"].first["subject"]
    assert_equal JSON.parse(JSON.generate(Activity.recent(limit: 15))), digest["activity"]
    assert_operator digest["activity"].size, :>, 0, "the world holds decisions"
  end

  test "a skill whose exercises the student has all seen carries pool_exhausted_at, in the digest as in the progress endpoint (D-348)" do
    skill_of = ->(digest) { digest["progress"]["subjects"].find { |s| s["key"] == "math" }["skills"].find { |s| s["key"] == SKILL } }
    assert_nil skill_of.(get_json("/api/v1/digest")).fetch("pool_exhausted_at", :missing)
    PracticePoolExhaustion.create!(student: @official, topic_revision: @topic_revision, skill_key: SKILL, created_at: Time.utc(2026, 11, 17, 9, 30))
    digest = get_json("/api/v1/digest")
    assert_equal "2026-11-17T09:30:00Z", skill_of.(digest)["pool_exhausted_at"]
    assert_equal get_json("/api/v1/students/student/progress"), digest["progress"]
  end

  test "student defaults to the official one, and another key is its own digest" do
    assert_equal get_json("/api/v1/digest?student=student").except("generated_at"), get_json("/api/v1/digest").except("generated_at")
    trial = get_json("/api/v1/digest?student=prova-1")
    assert_equal "prova-1", trial["next"]["student"]
    assert_equal "prova-1", trial["home"]["student"]
    assert_equal get_json("/api/v1/students/prova-1/progress"), trial["progress"]
  end

  test "the comments are the open ones as the list gives them: how many, how many are new, the latest five" do
    list = get_json("/api/v1/comments")
    digest = get_json("/api/v1/digest")["comments"]
    assert_equal 7, digest["open"], "the closed one is not open"
    assert_equal list["total"], digest["open"]
    assert_equal 6, digest["unread"], "one of the seven was read"
    assert_equal 5, digest["latest"].size
    assert_equal list["comments"].first(5), digest["latest"]
    assert_equal @comments.last(5).reverse.map(&:id), digest["latest"].map { |c| c["id"] }
    assert_equal list["notice"], digest["notice"]
  end

  test "the pending answers are the list's rows, five at most, with the count" do
    list = get_json("/api/v1/answers/pending?student=student")
    digest = get_json("/api/v1/digest")["answers_pending"]
    assert_equal 1, digest["count"]
    assert_equal list["total"], digest["count"]
    assert_equal list["answers"].first(5), digest["rows"]
    assert_equal "short_answer", digest["rows"].first["kind"]
    assert_equal list["notice"], digest["notice"]
  end

  test "an unknown key, a malformed one and the preview student are E-NOT-FOUND" do
    [ "nobody", "Not Valid", "preview" ].each do |key|
      api("/api/v1/digest?student=#{ERB::Util.url_encode(key)}")
      assert_response :not_found, key
      assert_equal [ "E-NOT-FOUND", "student" ], json.values_at("code", "field")
    end
  end

  test "a read writes nothing" do
    assert_no_difference [ "PracticeEvent.count", "PracticeServe.count", "Decision.count", "AppEvent.count", "CommentEvent.count", "Attempt.count",
                           "ViewLink.count", "ViewLinkRevocation.count" ] do
      api("/api/v1/digest")
      api("/api/v1/digest?student=prova-1", token: @tokens.fetch("teacher"))
    end
  end
end
