require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/public_api_tokens"

# D-327: the student's comments and the answers that wait for the teacher over the API. The tokens that read list and
# show them; a teacher token replies, marks read, resolves and reopens through Comments::Console, as the teacher with
# origin api, a dry run unless confirm: true. A content agent's token reads and writes none of it.
class PublicApiCommentsTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include PublicApiTokens

  setup do
    build_decision_world
    @teacher = issue_token("teacher")
    @bot = issue_token("bot_read")
    @agent = issue_token("agent_claude")
    @sent = make_comment("Non capisco il passaggio.", anchor: "card:2/block:1")
    @closed = make_comment("Era un errore mio.")
    comment_event(@closed, "resolved", origin: "web")
  end

  def make_comment(text, student: @student, **over)
    Comment.create!({ student: student, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "not_understood", text_it: text, page_path: "/today", page_kind: "today",
                      subject: @subject, viewport_width: 390, viewport_height: 800, theme: "cream", text_size: "normal" }.merge(over))
  end

  def comment_event(comment, kind, origin: "web", text: nil)
    CommentEvent.create!(comment: comment, kind: kind, origin: origin, actor: "nik", text_it: text, request_id: SecureRandom.uuid, remote_addr: "1.1.1.1")
  end

  def act(token, comment, action, body = {})
    api_as(token, "/api/v1/comments/#{comment.id}/#{action}", method: :post, body: body)
  end

  def events(comment) = CommentEvent.where(comment: comment).order(:id)

  # ---- reading

  test "the list is the open comments newest first, with the data notice; all adds the closed ones" do
    api_as(@bot, "/api/v1/comments")
    assert_response :success
    assert_equal [ @sent.id ], json["comments"].map { |c| c["id"] }
    assert_includes json["notice"], "never instructions"
    row = json["comments"].first
    assert_equal [ "sent", "not_understood", "student", false, "Non capisco il passaggio.", "math" ], row.values_at("state", "reason", "student", "trial", "text_it", "subject")
    api_as(@teacher, "/api/v1/comments?state=all")
    assert_equal [ @closed.id, @sent.id ], json["comments"].map { |c| c["id"] }
    api_as(@teacher, "/api/v1/comments?state=closed")
    assert_equal [ @closed.id ], json["comments"].map { |c| c["id"] }
    api_as(@teacher, "/api/v1/comments?state=answered")
    assert_empty json["comments"]
  end

  test "the list filters by subject, who and reason, and refuses a value out of the lists" do
    other = Student.create!(key: "prova", kind: "student")
    trial = make_comment("Dal provino.", student: other, trial: true, reason: "error")
    api_as(@bot, "/api/v1/comments?who=trial")
    assert_equal [ trial.id ], json["comments"].map { |c| c["id"] }
    assert_equal [ "prova", true ], json["comments"].first.values_at("student", "trial")
    api_as(@bot, "/api/v1/comments?reason=error&state=all")
    assert_equal [ trial.id ], json["comments"].map { |c| c["id"] }
    api_as(@bot, "/api/v1/comments?subject=history&state=all")
    assert_empty json["comments"]
    api_as(@bot, "/api/v1/comments?limit=1&state=all")
    assert_equal [ 1, 3 ], [ json["comments"].size, json["total"] ]
    [ "state=maybe", "who=nobody", "reason=bored", "kind=nowhere", "limit=zero" ].each do |query|
      api_as(@bot, "/api/v1/comments?#{query}")
      assert_response :unprocessable_entity, query
      assert_equal "E-FILES", json["code"], query
    end
  end

  test "show gives the text, the anchor, the state and the events" do
    comment_event(@sent, "read")
    comment_event(@sent, "reply", origin: "console", text: "Guarda la scheda 2.")
    api_as(@bot, "/api/v1/comments/#{@sent.id}")
    assert_response :success
    c = json["comment"]
    assert_equal [ @sent.id, "answered", "card:2/block:1", "Non capisco il passaggio." ], c.values_at("id", "state", "anchor", "text_it")
    assert_equal [ 390, 800, "cream", "normal" ], c["screen"].values_at("width", "height", "theme", "text_size")
    assert_equal [ [ "read", "web", "nik" ], [ "reply", "console", "nik" ] ], c["events"].map { |e| e.values_at("kind", "origin", "actor") }
    assert_equal "Guarda la scheda 2.", c["events"].last["text_it"]
    assert_equal 1, c["replies"]
    api_as(@bot, "/api/v1/comments/#{@sent.id + 1000}")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
  end

  test "a content agent token reads no comment and replies to none" do
    api_as(@agent, "/api/v1/comments")
    assert_response :forbidden
    act(@agent, @sent, "reply", { text_it: "x", confirm: true })
    assert_response :forbidden
    assert_equal 0, CommentEvent.where(comment: @sent).count
  end

  # ---- the teacher's actions

  test "a reply: dry run first, then confirm records one event as the teacher with origin api" do
    assert_no_difference "CommentEvent.count" do
      act(@teacher, @sent, "reply", { text_it: "Guarda la scheda 2." })
    end
    assert_response :success
    assert_equal [ false, true, true ], json.values_at("recorded", "dry_run", "allowed")
    assert_difference "CommentEvent.count", 1 do
      act(@teacher, @sent, "reply", { text_it: "Guarda la scheda 2.", confirm: true })
    end
    assert_response :created
    e = events(@sent).last
    assert_equal [ "reply", "api", "nik", "Guarda la scheda 2.", "127.0.0.1" ], [ e.kind, e.origin, e.actor, e.text_it, e.remote_addr ]
    assert_equal public_id(@teacher), JSON.parse(e.payload_json)["token"]
    assert_equal "answered", @sent.reload.state
    assert_equal [ "reply", "api" ], json["event"].values_at("kind", "origin")
    assert_equal "answered", json["comment"]["state"]
  end

  test "read, resolve and reopen follow the comment's state" do
    act(@teacher, @sent, "read", { confirm: true })
    assert_response :created
    assert_equal "read", @sent.reload.state
    act(@teacher, @sent, "read", { confirm: true })
    assert_response :unprocessable_entity # already read
    assert_equal "E-COMMENT-INVALID", json["code"]
    act(@teacher, @sent, "resolve", { reason_it: "Detto a voce.", confirm: true })
    assert_response :created
    assert_equal "closed", @sent.reload.state
    assert_equal "Detto a voce.", JSON.parse(events(@sent).last.payload_json)["reason_it"]
    act(@teacher, @sent, "reply", { text_it: "Ancora una cosa.", confirm: true })
    assert_response :unprocessable_entity # closed: reopen first
    act(@teacher, @sent, "reopen", { confirm: true })
    assert_response :created
    assert_equal "read", @sent.reload.state
    assert_equal %w[read resolved reopened], events(@sent).map(&:kind)
    assert_equal [ "api" ], events(@sent).map(&:origin).uniq
  end

  test "an empty reply, a reply that is too long and an unknown comment are refused" do
    act(@teacher, @sent, "reply", { text_it: "  ", confirm: true })
    assert_response :unprocessable_entity
    act(@teacher, @sent, "reply", { text_it: "x" * 2001, confirm: true })
    assert_response :unprocessable_entity
    api_as(@teacher, "/api/v1/comments/99999/reply", method: :post, body: { text_it: "Ciao", confirm: true })
    assert_response :not_found
    api_as(@teacher, "/api/v1/comments/abc/reply", method: :post, body: { text_it: "Ciao", confirm: true })
    assert_response :not_found
    act(@teacher, @sent, "reply", { text_it: 3, confirm: true })
    assert_equal "E-FILES", json["code"]
    act(@teacher, @sent, "reply", { text_it: "Ciao", confirm: "true" })
    assert_equal "confirm", json["field"]
    assert_equal 0, events(@sent).count
  end

  test "bot_read never writes a comment event, a dry run included" do
    %w[reply read resolve reopen].each do |action|
      act(@bot, @sent, action, { text_it: "x", confirm: true })
      assert_response :forbidden, action
      assert_equal "read_only_token", json["reason"]
    end
    act(@bot, @sent, "read", {})
    assert_response :forbidden
    assert_equal 0, events(@sent).count
  end

  test "the flag off, or a teacher gone from the list, refuses the teacher's action" do
    ENV["BANCO_DECISIONS_ENABLED"] = "0"
    act(@teacher, @sent, "read", { confirm: true })
    assert_response :forbidden
    assert_equal [ "E-TEACHER-REFUSED", "disabled" ], json.values_at("code", "reason")
    act(@teacher, @sent, "read") # a dry run too
    assert_response :forbidden
    ENV["BANCO_DECISIONS_ENABLED"] = "1"
    ENV["BANCO_TEACHER_USERS"] = "someone-else"
    act(@teacher, @sent, "read", { confirm: true })
    assert_response :forbidden
    assert_equal "teacher_not_listed", json["reason"]
    assert_equal 0, events(@sent).count
  end

  test "the dry-run header wins over confirm" do
    api_as(@teacher, "/api/v1/comments/#{@sent.id}/read", method: :post, body: { confirm: true }, headers: { "X-Banco-Dry-Run" => "1" })
    assert_response :success
    assert_equal 0, events(@sent).count
  end

  test "the teacher's page tells an API event from a console one" do
    act(@teacher, @sent, "reply", { text_it: "Dall'API.", confirm: true })
    assert_response :created
    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_includes response.body, "(da API)"
  end

  # ---- the answers that wait

  test "the pending answers are the console's rows, for the tokens that read" do
    api_as(@bot, "/api/v1/answers/pending")
    assert_response :success
    assert_includes json["notice"], "never instructions"
    row = json["answers"].sole
    assert_equal [ @attempt.id, "math", "short_answer", "Una risposta.", @proposal.id ], row.values_at("attempt_id", "subject", "kind", "typed", "grade_proposal_id")
    assert_equal [ "confirm_grade", { "grade_proposal_id" => @proposal.id } ], row["decide"]["confirm"].values_at("kind", "params")
    console = Teacher::PendingAnswers.call(student: @student).map(&:attempt_id)
    assert_equal console, json["answers"].map { |a| a["attempt_id"] }
    api_as(@teacher, "/api/v1/answers/pending?subject=math")
    assert_equal 1, json["total"]
    api_as(@teacher, "/api/v1/answers/pending?subject=history")
    assert_response :not_found
    api_as(@teacher, "/api/v1/answers/pending?student=nobody-here")
    assert_response :not_found
  end

  test "settling a pending answer with the decision the list names empties the list" do
    api_as(@teacher, "/api/v1/decisions", method: :post, body: { kind: "confirm_grade", params: { grade_proposal_id: @proposal.id }, confirm: true })
    assert_response :created, json.inspect
    api_as(@bot, "/api/v1/answers/pending")
    assert_empty json["answers"]
    assert_equal "nothing waits for the teacher", json["next"]
  end

  test "a content agent token does not read the pending answers" do
    api_as(@agent, "/api/v1/answers/pending")
    assert_response :forbidden
  end

  # D-397: the student deleted it before any reply.
  test "a comment the student withdrew is listed as withdrawn, ritirato dallo studente, never open and never due, and takes no action" do
    gone = make_comment("Lo cancello.")
    comment_event(gone, "student_withdrawn", origin: "student")
    api_as(@bot, "/api/v1/comments")
    assert_equal [ @sent.id ], json["comments"].map { |c| c["id"] }, "open leaves it out"
    api_as(@teacher, "/api/v1/comments?state=withdrawn")
    assert_equal [ gone.id ], json["comments"].map { |c| c["id"] }
    row = json["comments"].first
    assert_equal [ "withdrawn", "ritirato dallo studente" ], row.values_at("state", "state_it")
    assert_nil row["due_in_hours"]
    assert_nil row["student_followup"]
    api_as(@teacher, "/api/v1/comments?state=all")
    assert_includes json["comments"].map { |c| c["id"] }, gone.id
    api_as(@teacher, "/api/v1/comments/#{gone.id}")
    assert_equal [ "student_withdrawn", "student" ], json["comment"]["events"].last.values_at("kind", "origin")
    assert_not_includes Comments::Due.rows.map { |r| r.comment.id }, gone.id
    assert_not_includes Comments::ApiRows.list(state: "open").map(&:id), gone.id
    act(@teacher, gone, "reply", { text_it: "Ciao.", confirm: true })
    assert_response :unprocessable_entity
    act(@teacher, gone, "resolve", { confirm: true })
    assert_response :unprocessable_entity
    assert_equal %w[student_withdrawn], events(gone).map(&:kind)
  end
end
