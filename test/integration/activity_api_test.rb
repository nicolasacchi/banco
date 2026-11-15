require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/public_api_tokens"

# D-334: GET /api/v1/activity, who did what, with two teachers on the same students: nik in the browser and at the
# console, silvia@scc.im with her bot's teacher token over the API, and a bot_read token that creates a view link.
# Every action goes through its real door; the feed only reads. GET /api/v1/decisions and GET /api/v1/comments/:id name
# the actor too.
class ActivityApiTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include PublicApiTokens

  VIEW_URL = "https://api.banco.test".freeze
  SILVIA = "silvia@scc.im".freeze
  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  setup do
    @saved_view_env = ENV.to_h.slice("BANCO_VIEW_URL", "BANCO_VIEW_LINKS_ENABLED")
    ENV["BANCO_VIEW_URL"] = VIEW_URL
    ENV["BANCO_VIEW_LINKS_ENABLED"] = "1"
    ENV["BANCO_TEACHER_USERS"] = "nik,#{SILVIA}"
    build_decision_world
    @nik_token = ApiToken.issue!(role: "teacher", label: "teacher-nik-bot", expires_at: 30.days.from_now, teacher_login: "nik")
    @silvia = ApiToken.issue!(role: "teacher", label: "teacher-silvia-bot-2026-11-15", expires_at: 30.days.from_now, teacher_login: SILVIA)
    @reader = ApiToken.issue!(role: "bot_read", label: "reader-bot", expires_at: 30.days.from_now)
    @agent = issue_token("agent_claude")
    @comment = Comment.create!(student: @student, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "not_understood", text_it: "PAROLA-SEGRETA-DELLO-STUDENTE",
                               page_path: "/today", page_kind: "today", subject: @subject, viewport_width: 390, viewport_height: 800, theme: "cream", text_size: "normal")
    play_day
  end

  teardown do
    %w[BANCO_VIEW_URL BANCO_VIEW_LINKS_ENABLED].each { |k| @saved_view_env.key?(k) ? ENV[k] = @saved_view_env[k] : ENV.delete(k) }
  end

  # One minute between the actions, so the order of the ledgers is the order of the time.
  def step = travel(1.minute)

  def browser(path, body)
    on(:web, path, method: :post, headers: TEACHER.merge(JSON_HEADERS, "X-CSRF-Token" => csrf_token), params: body.to_json, remote_addr: EDGE)
  end

  # 1 nik decides in the browser, 2 silvia's bot decides over the API, 3 nik decides at the console, 4 nik replies in the browser,
  # 5 silvia's bot replies over the API, 6 the bot_read token creates a view link.
  def play_day
    step
    decide("/teacher/subjects/math/formula-sheet", { enabled: false })
    assert_response :success, response.body
    @after_web_decision = Time.current + 30.seconds # the clock is frozen by travel: the next action is a minute on
    step
    api_as(@silvia, "/api/v1/decisions", method: :post, body: { kind: "set_formula_sheet", params: { subject: "math", enabled: false }, confirm: true })
    assert_response :created, response.body
    step
    result = DecisionConsole.call(kind: "kind_override", teacher: "nik", subject: "math", params: { skill: "math.number", override_kind: "learn" },
                                  reason: "Non l'ha studiato.", confirm: true, os_user: "operatore")
    assert result.recorded, result.errors.inspect
    step
    browser("/teacher/comments/#{@comment.id}/reply", { text_it: "RISPOSTA-SEGRETA-DI-NIK" })
    assert_response :redirect, response.body
    step
    api_as(@silvia, "/api/v1/comments/#{@comment.id}/reply", method: :post, body: { text_it: "RISPOSTA-SEGRETA-DEL-BOT", confirm: true })
    assert_response :created, response.body
    step
    api_as(@reader, "/api/v1/view-links", method: :post, body: {})
    assert_response :created, response.body
    @link_id = json["id"]
  end

  def feed(query = "", token: @reader)
    api_as(token, "/api/v1/activity#{query}")
    assert_response :success, response.body
    json
  end

  def short(rows) = rows.map { |r| [ r["kind"], r.dig("actor", "login"), r.dig("actor", "via"), r.dig("actor", "token", "label") ] }

  test "the feed lists the six actions newest first with who, how and with which token" do
    body = feed
    assert_equal [
      [ "view_link_created", "bot_read:reader-bot", "api", "reader-bot" ],
      [ "comment_reply", SILVIA, "api", "teacher-silvia-bot-2026-11-15" ],
      [ "comment_reply", "nik", "web", nil ],
      [ "decision", "nik", "console", nil ],
      [ "decision", SILVIA, "api", "teacher-silvia-bot-2026-11-15" ],
      [ "decision", "nik", "web", nil ]
    ], short(body["rows"])
    assert_equal [ "bot_read:reader-bot", "nik", SILVIA ], body["actors"]
    assert_equal body["rows"].map { |r| r["at"] }.sort.reverse, body["rows"].map { |r| r["at"] }
    assert_equal ApiToken.find_by!(label: "teacher-silvia-bot-2026-11-15").public_id, body["rows"][1].dig("actor", "token", "public_id")
  end

  test "each row says what it is about, in Italian, and carries none of the student's or the teachers' words" do
    rows = feed["rows"]
    assert_equal({ "view_link_id" => @link_id }, rows[0]["ref"])
    assert_equal({ "comment_id" => @comment.id, "subject" => "math" }, rows[1]["ref"])
    assert_equal "Risposta al commento #{@comment.id} (Matematica)", rows[2]["summary_it"]
    assert_equal [ "decision_kind", "decision_id", "subject" ].sort, rows[3]["ref"].keys.sort
    assert_equal "kind_override", rows[3]["ref"]["decision_kind"]
    assert_equal "Spento il formulario (Matematica)", rows[5]["summary_it"]
    assert_equal "Creato il link di sola lettura #{@link_id} (/teacher, 60 minuti)", rows[0]["summary_it"]
    text = response.body
    %w[PAROLA-SEGRETA-DELLO-STUDENTE RISPOSTA-SEGRETA-DI-NIK RISPOSTA-SEGRETA-DEL-BOT].each { |secret| assert_not_includes text, secret }
  end

  test "actor filters on the login of the rows" do
    assert_equal [ [ "comment_reply", SILVIA, "api", "teacher-silvia-bot-2026-11-15" ], [ "decision", SILVIA, "api", "teacher-silvia-bot-2026-11-15" ] ], short(feed("?actor=#{CGI.escape(SILVIA)}")["rows"])
    assert_equal [ SILVIA ], json["actors"]
    assert_equal [ [ "comment_reply", "nik", "web", nil ], [ "decision", "nik", "console", nil ], [ "decision", "nik", "web", nil ] ], short(feed("?actor=nik")["rows"])
    assert_equal [ "view_link_created" ], feed("?actor=#{CGI.escape('bot_read:reader-bot')}")["rows"].map { |r| r["kind"] }
    assert_equal({ "rows" => [], "actors" => [] }, feed("?actor=nessuno"))
  end

  test "since keeps the rows from that moment on, as a moment or as a date" do
    rows = feed("?since=#{CGI.escape(@after_web_decision.utc.iso8601(6))}")["rows"]
    assert_equal 5, rows.size
    assert_not_includes short(rows), [ "decision", "nik", "web", nil ]
    assert_equal 6, feed("?since=#{Date.current.yesterday.iso8601}")["rows"].size
    assert_empty feed("?since=#{CGI.escape((Time.current + 1.hour).utc.iso8601)}")["rows"]
  end

  test "limit bounds the rows and a bad limit or since is a 422 E-FILES" do
    assert_equal %w[view_link_created comment_reply], feed("?limit=2")["rows"].map { |r| r["kind"] }
    assert_equal 6, feed("?limit=500")["rows"].size
    %w[0 -3 abc 1.5].each do |bad|
      api_as(@reader, "/api/v1/activity?limit=#{bad}")
      assert_response :unprocessable_entity, bad
      assert_equal [ "E-FILES", "limit" ], json.values_at("code", "field")
    end
    api_as(@reader, "/api/v1/activity?since=yesterday")
    assert_response :unprocessable_entity
    assert_equal [ "E-FILES", "since" ], json.values_at("code", "field")
  end

  test "a teacher token reads it too; a content token is 403 token_role and so is no token at all (401)" do
    feed("", token: @silvia)
    assert_equal 6, json["rows"].size
    api_as(@agent, "/api/v1/activity")
    assert_response :forbidden
    assert_equal [ "E-AUTH", "token_role" ], json.values_at("code", "reason")
    api_as(nil, "/api/v1/activity")
    assert_response :unauthorized
  end

  test "reading the feed records nothing and the API listener is the only door" do
    counts = -> { [ Decision.count, CommentEvent.count, ViewLink.count, ViewLinkRevocation.count, AppEvent.count ] }
    before = counts.call
    feed("?actor=nik")
    feed
    assert_equal before, counts.call
    on(:web, "/api/v1/activity", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
  end

  test "GET /api/v1/decisions names who recorded each row: login, via, and for the API the token and its label" do
    api_as(@reader, "/api/v1/decisions")
    assert_response :success
    rows = json["decisions"].map { |d| d.values_at("kind", "teacher", "via", "token_label") }
    assert_equal [ [ "set_formula_sheet", "nik", "web", nil ], [ "set_formula_sheet", SILVIA, "api", "teacher-silvia-bot-2026-11-15" ], [ "kind_override", "nik", "console", nil ] ], rows
    api_row = json["decisions"][1]
    assert_equal ApiToken.find_by!(label: "teacher-silvia-bot-2026-11-15").public_id, api_row["token"]
    assert_nil json["decisions"][0]["token"]
  end

  test "GET /api/v1/comments/:id names who did each event: actor, origin, and for the API the token and its label" do
    api_as(@reader, "/api/v1/comments/#{@comment.id}")
    assert_response :success
    events = json["comment"]["events"]
    assert_equal [ [ "reply", "nik", "web", nil ], [ "reply", SILVIA, "api", "teacher-silvia-bot-2026-11-15" ] ], events.map { |e| e.values_at("kind", "actor", "origin", "token_label") }
    assert_equal ApiToken.find_by!(label: "teacher-silvia-bot-2026-11-15").public_id, events[1]["token"]
    assert_nil events[0]["token"]
  end
end
