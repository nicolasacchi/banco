require "test_helper"
require "rake"
require_relative "../support/course_rows"
require_relative "../support/public_api_tokens"

# D-327: the public API's token roles. bot_read only reads, teacher reads and decides (and answers comments) but never
# writes content, the content agents never read the teacher's views; a token expires and a revoked or expired one is
# refused like a wrong one; a teacher who leaves BANCO_TEACHER_USERS cuts the teacher token.
class PublicApiRolesTest < ActionDispatch::IntegrationTest
  include CourseRows
  include PublicApiTokens

  setup do
    build_course
    @revision = make_revision("pa-1", "math.number")
    @bot = issue_token("bot_read")
    @teacher = issue_token("teacher")
    @agent = issue_token("agent_claude")
  end

  def ledger_counts = ApiToken.connection.tables.sum { |t| t == "api_tokens" || t.start_with?("api_token") ? 0 : ApiToken.connection.select_value("SELECT COUNT(*) FROM #{t}") }

  # ---- bot_read reads and never writes

  test "a bot_read token reads the status, the schema and the contract header" do
    api_as(@bot, "/api/v1/status")
    assert_response :success
    api_as(@bot, "/api/v1/schema")
    assert_response :success
    assert_equal Contract.digest, response.headers["X-Banco-Contract"]
  end

  test "a bot_read token refuses every write with 403 E-AUTH read_only_token and stores nothing" do
    before = ledger_counts
    [ [ "/api/v1/decisions", { kind: "approve_skill_graph", params: { subject: "math" }, confirm: true } ],
      [ "/api/v1/comments/1/reply", { text_it: "Ciao", confirm: true } ],
      [ "/api/v1/comments/1/resolve", { confirm: true } ],
      [ "/api/v1/work/submit", { item: "x", base: nil, files: {} } ],
      [ "/api/v1/sessions", { role: "author", agent: "a", model: "m" } ],
      [ "/api/v1/diagnosis/simulate", {} ] ].each do |path, body|
      api_as(@bot, path, method: :post, body: body)
      assert_response :forbidden, path
      assert_equal [ "E-AUTH", "read_only_token" ], json.values_at("code", "reason"), path
    end
    assert_equal before, ledger_counts
  end

  test "a bot_read token reads what needs a session for the other tokens, without one" do
    api_as(@bot, "/api/v1/revisions/#{@revision.id}/review")
    assert_response :success, json.inspect
    api_as(@bot, "/api/v1/revisions/#{@revision.id}/solve")
    assert_response :success, json.inspect
    api_as(@bot, "/api/v1/work/items/pa-1?role=verifier")
    assert_response :success, json.inspect
    assert_equal "verifier", json["role"]
    api_as(@bot, "/api/v1/submissions/pending")
    assert_response :success, json.inspect
    # the same reads need a session for a content agent
    api_as(@agent, "/api/v1/revisions/#{@revision.id}/solve")
    assert_response :unprocessable_entity
    assert_equal "E-SESSION", json["code"]
    api_as(@agent, "/api/v1/submissions/pending")
    assert_equal "E-SESSION", json["code"]
  end

  test "a teacher token reads the same as a bot_read token" do
    %W[/api/v1/status /api/v1/revisions/#{@revision.id}/review /api/v1/submissions/pending].each do |path|
      api_as(@teacher, path)
      assert_response :success, "#{path}: #{json.inspect}"
    end
  end

  # ---- the content agents' tokens are not the teacher's

  test "a content agent token cannot decide, read decisions, comments or the pending answers" do
    api_as(@agent, "/api/v1/decisions", method: :post, body: { kind: "approve_skill_graph", params: { subject: "math" }, confirm: true })
    assert_response :forbidden
    assert_equal [ "E-AUTH", "token_role" ], json.values_at("code", "reason")
    [ "/api/v1/decisions", "/api/v1/comments", "/api/v1/comments/1", "/api/v1/answers/pending" ].each do |path|
      api_as(@agent, path)
      assert_response :forbidden, path
      assert_equal "token_role", json["reason"], path
    end
    %w[reply resolve reopen read].each do |action|
      api_as(@agent, "/api/v1/comments/1/#{action}", method: :post, body: { confirm: true })
      assert_response :forbidden, action
      assert_equal "token_role", json["reason"], action
    end
    assert_equal 0, Decision.count
  end

  test "a ci token is a content-agent token too" do
    api_as(issue_token("ci"), "/api/v1/answers/pending")
    assert_response :forbidden
  end

  test "a teacher token never writes content" do
    api_as(@teacher, "/api/v1/work/submit", method: :post, body: { item: "x", base: nil, files: {} })
    assert_response :forbidden
    assert_equal [ "E-AUTH", "teacher_token_no_content" ], json.values_at("code", "reason")
    api_as(@teacher, "/api/v1/sessions", method: :post, body: { role: "author", agent: "a", model: "m" })
    assert_equal "teacher_token_no_content", json["reason"]
    api_as(@teacher, "/api/v1/findings/1/responses", method: :post, body: { response: {} })
    assert_equal "teacher_token_no_content", json["reason"]
    assert_equal 0, AgentSession.count
  end

  # ---- expiry and revocation

  test "an expired token is refused like a wrong one, a token about to expire is not" do
    expired = issue_token("bot_read", expires_at: 1.second.ago)
    api_as(expired, "/api/v1/status")
    assert_response :unauthorized
    assert_equal "E-AUTH", json["code"]
    api_as(@bot.sub(/.\z/) { |c| c == "a" ? "b" : "a" }, "/api/v1/status")
    assert_response :unauthorized
    api_as(issue_token("bot_read", expires_at: 1.hour.from_now), "/api/v1/status")
    assert_response :success
    api_as(issue_token("agent_claude", expires_at: 1.second.ago), "/api/v1/status")
    assert_response :unauthorized
  end

  test "a token with no expiry (a content agent's, before D-327) still works" do
    api_as(issue_token("agent_omp", expires_at: nil), "/api/v1/status")
    assert_response :success
  end

  test "the clock decides at use time" do
    token = issue_token("bot_read", expires_at: 2.hours.from_now)
    travel_to 3.hours.from_now do
      api_as(token, "/api/v1/status")
      assert_response :unauthorized
    end
  end

  test "a revoked token is refused" do
    ApiTokenRevocation.create!(api_token: ApiToken.find_by!(public_id: public_id(@teacher)), reason: "test")
    api_as(@teacher, "/api/v1/status")
    assert_response :unauthorized
    api_as(@teacher, "/api/v1/decisions", method: :post, body: { kind: "approve_skill_graph", params: { subject: "math" }, confirm: true })
    assert_response :unauthorized
    assert_equal 0, Decision.count
  end

  test "an absent or malformed Authorization header is 401 on every new route" do
    [ [ :get, "/api/v1/decisions" ], [ :post, "/api/v1/decisions" ], [ :get, "/api/v1/comments" ], [ :get, "/api/v1/answers/pending" ] ].each do |method, path|
      api_as(nil, path, method: method)
      assert_response :unauthorized, path
      api_as("not-a-token", path, method: method)
      assert_response :unauthorized, path
    end
  end

  # ---- the teacher list

  test "a teacher token whose teacher left BANCO_TEACHER_USERS is refused, reads included" do
    ENV["BANCO_TEACHER_USERS"] = "someone-else"
    api_as(@teacher, "/api/v1/status")
    assert_response :forbidden
    assert_equal [ "E-AUTH", "teacher_not_listed" ], json.values_at("code", "reason")
    api_as(@teacher, "/api/v1/decisions", method: :post, body: { kind: "approve_skill_graph", params: { subject: "math" }, confirm: true })
    assert_equal "teacher_not_listed", json["reason"]
    assert_equal 0, Decision.count
    api_as(@bot, "/api/v1/status") # a bot_read token has no teacher
    assert_response :success
  end

  # ---- the registry

  test "a teacher token needs a login and no other role takes one" do
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.issue!(role: "teacher", label: "x") }
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.issue!(role: "bot_read", label: "x", teacher_login: "nik") }
    # the database says the same
    assert_raises(ActiveRecord::StatementInvalid) do
      ApiToken.connection.execute("INSERT INTO api_tokens (public_id, secret_sha256, role, label, created_at) VALUES ('abcdwxyz', '#{'a' * 64}', 'teacher', 'x', CURRENT_TIMESTAMP)")
    end
  end

  test "the roles keep the session roles of the old ones and give none to the new ones" do
    assert_equal %w[author verifier reviewer solver grader arbiter], ApiToken.session_roles("agent_claude")
    assert_empty ApiToken.session_roles("bot_read")
    assert_empty ApiToken.session_roles("teacher")
    assert_equal %w[agent_claude agent_omp ci bot_read teacher], ApiToken::ROLES
  end

  def run_task(name, env)
    Rails.application.load_tasks unless Rake::Task.task_defined?(name)
    task = Rake::Task[name]
    task.reenable
    with_env(env) { capture_io { task.invoke } }.first
  end

  test "banco:token:issue gives 90 days by default, EXPIRES_DAYS changes it and a teacher login is stored" do
    out = run_task("banco:token:issue", "ROLE" => "bot_read", "LABEL" => "bot", "EXPIRES_DAYS" => nil, "TEACHER" => nil)
    row = ApiToken.find_by!(public_id: public_id(out.strip))
    assert_equal "bot_read", row.role
    assert_in_delta 90.days.from_now.to_f, row.expires_at.to_f, 60
    assert_nil row.teacher_login
    out = run_task("banco:token:issue", "ROLE" => "teacher", "TEACHER" => "nik", "EXPIRES_DAYS" => "7", "LABEL" => nil)
    row = ApiToken.find_by!(public_id: public_id(out.strip))
    assert_equal [ "teacher", "nik" ], [ row.role, row.teacher_login ]
    assert_in_delta 7.days.from_now.to_f, row.expires_at.to_f, 60
    out = run_task("banco:token:issue", "ROLE" => "agent_claude", "EXPIRES_DAYS" => "0", "TEACHER" => nil, "LABEL" => nil)
    assert_nil ApiToken.find_by!(public_id: public_id(out.strip)).expires_at
  end

  test "banco:token:issue refuses a teacher token without a listed teacher, a bad expiry and a bot that never expires" do
    {
      { "ROLE" => "teacher", "TEACHER" => nil } => "TEACHER=",
      { "ROLE" => "teacher", "TEACHER" => "mallory" } => "not in BANCO_TEACHER_USERS",
      { "ROLE" => "bot_read", "TEACHER" => "nik" } => "role teacher only",
      { "ROLE" => "bot_read", "EXPIRES_DAYS" => "0", "TEACHER" => nil } => "must expire",
      { "ROLE" => "bot_read", "EXPIRES_DAYS" => "soon", "TEACHER" => nil } => "whole number"
    }.each do |env, message|
      Rails.application.load_tasks unless Rake::Task.task_defined?("banco:token:issue")
      task = Rake::Task["banco:token:issue"]
      task.reenable
      assert_no_difference "ApiToken.count" do
        _, err = with_env({ "EXPIRES_DAYS" => nil }.merge(env)) { capture_io { assert_raises(SystemExit) { task.invoke } } }
        assert_includes err, message, env.inspect
      end
    end
  end

  test "banco:token:list shows the public id, role, teacher, expiry and state, never a secret" do
    revoked = issue_token("bot_read")
    ApiTokenRevocation.create!(api_token: ApiToken.find_by!(public_id: public_id(revoked)), reason: "test")
    issue_token("bot_read", expires_at: 1.minute.ago)
    out = run_task("banco:token:list", {})
    [ @bot, @teacher, @agent, revoked ].each do |token|
      assert_includes out, public_id(token)
      assert_not_includes out, Banco::TokenAuth::FORMAT.match(token)[2]
    end
    assert_match(/#{public_id(@teacher)}\s+teacher\s+.*nik\s+\d{4}-\d\d-\d\d \d\d:\d\d\s+active/, out)
    assert_match(/#{public_id(revoked)}.*revoked/, out)
    assert_match(/bot_read.*expired/, out)
  end
end
