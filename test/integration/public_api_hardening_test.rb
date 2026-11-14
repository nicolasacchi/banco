require "test_helper"
require "minitest/mock"
require_relative "../support/decision_world"
require_relative "../support/public_api_tokens"

# D-327, the security review before opening api.banco.scc.im: a request through the edge proxy is the Internet's and only the
# public roles may use it; the public roles always expire; each public host belongs to one listener; an API decision approves a
# revision the bot named, from a list of kinds that leaves out the consent and the release of the entry test; the answers are
# never cached and the digest goes to a good token only.
class PublicApiHardeningTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include PublicApiTokens

  setup do
    build_decision_world
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    @tokens = ApiToken::ROLES.to_h { |role| [ role, issue_token(role) ] }
  end

  # ---- through the edge proxy only the public roles

  test "a content agent token is refused with 403 not_public_role when the request came through the edge proxy" do
    sessions = AgentSession.count
    %w[agent_claude agent_omp ci].each do |role|
      api_as(@tokens[role], "/api/v1/status", remote_addr: EDGE)
      assert_response :forbidden, role
      assert_equal [ "E-AUTH", "not_public_role" ], json.values_at("code", "reason"), role
      api_as(@tokens[role], "/api/v1/sessions", method: :post, body: { role: "author", agent: "a", model: "m" }, remote_addr: EDGE)
      assert_equal "not_public_role", json["reason"], role
    end
    assert_equal sessions, AgentSession.count
  end

  test "the public roles read through the edge proxy, and the content agents keep the loopback listener" do
    %w[bot_read teacher].each do |role|
      api_as(@tokens[role], "/api/v1/status", remote_addr: EDGE)
      assert_response :success, role
    end
    %w[agent_claude agent_omp ci].each do |role|
      api_as(@tokens[role], "/api/v1/status", remote_addr: "127.0.0.1")
      assert_response :success, role
    end
  end

  test "a wrong token through the edge is still 401, not a hint about the role" do
    api_as("bnc_aaaaaaaa_#{'x' * 43}", "/api/v1/status", remote_addr: EDGE)
    assert_response :unauthorized
  end

  # ---- the public roles always expire

  # The model's validation only: a CHECK added to api_tokens in the migration did not appear in the rebuilt table, so none is claimed:
  # the rule is the model's and the rake task's; every token is issued through ApiToken.issue!.
  test "a bot_read or teacher token without an expiry is refused by the model" do
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.issue!(role: "bot_read", label: "x") }
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.issue!(role: "teacher", label: "x", teacher_login: "nik") }
    assert_nothing_raised { ApiToken.issue!(role: "agent_claude", label: "x") } # a content token of before D-327 has none
  end

  # ---- decisions: an explicit revision and a list of kinds

  def decide(kind, params: {}, confirm: nil, **extra)
    body = { kind: kind, params: params }.merge(extra)
    body[:confirm] = confirm unless confirm.nil?
    api_as(@tokens["teacher"], "/api/v1/decisions", method: :post, body: body)
  end

  test "approving a revision needs revision_id: a subject alone is not the latest revision filled in" do
    [ [ "approve_skill_graph", { subject: "math" } ], [ "approve_blueprint", { subject: "math" } ], [ "confirm_test_reviewed", { subject: "math" } ] ].each do |kind, params|
      assert_no_difference "Decision.count" do
        decide(kind, params: params, confirm: true)
      end
      assert_response :unprocessable_entity, kind
      assert_equal "E-DECISION-INVALID", json["code"]
      assert_includes json["reasons"].first, "revision_id is required over the API", kind
    end
    decide("approve_skill_graph", params: { subject: "math", revision_id: @graph.id }, confirm: true)
    assert_response :created, json.inspect
    assert_equal @graph.id, json["payload"]["revision_id"]
  end

  test "the console still fills in the latest revision of a subject" do
    result = DecisionConsole.call(kind: "approve_skill_graph", teacher: "nik", subject: "math", confirm: false)
    assert result.ok, result.errors.inspect
    assert_equal @graph.id, result.payload["revision_id"]
  end

  test "record_consent and release_diagnosis are not decisions of the API, a dry run included" do
    assert_equal %w[record_consent release_diagnosis], (DecisionRecorder::KINDS - DecisionRecorder::Api::KINDS).sort
    assert_empty DecisionRecorder::Api::KINDS - DecisionRecorder::KINDS
    %w[record_consent release_diagnosis].each do |kind|
      [ nil, true ].each do |confirm|
        assert_no_difference "Decision.count" do
          decide(kind, params: { acknowledged: true, statement_it: "Acconsento." }, confirm: confirm)
        end
        assert_response :forbidden, kind
        assert_equal [ "E-TEACHER-REFUSED", "kind_not_allowed" ], json.values_at("code", "reason"), kind
      end
    end
  end

  test "the browser's and the console's records of those kinds are unchanged" do
    result = DecisionConsole.call(kind: "record_consent", teacher: "nik", params: { acknowledged: true, statement_it: "Acconsento." }, confirm: false)
    assert result.ok, result.errors.inspect
  end

  test "attest_it over the API is refused for a kind that takes none (the operator accepted it for approve_topic and approve_blueprint: public_api_attestation_test)" do
    decide("approve_skill_graph", params: { revision_id: @graph.id }, attest_it: "Parole.", confirm: true)
    assert_response :unprocessable_entity
    assert_includes json["reasons"].first, "attest_it is accepted only for approve_topic and approve_blueprint"
    assert_equal 0, Decision.count
  end

  # ---- no cache, the digest to a good token only

  test "every answer of the API is no-store, and the contract digest goes to a good token only" do
    api_as(@tokens["bot_read"], "/api/v1/status")
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal Contract.digest, response.headers["X-Banco-Contract"]
    api_as(nil, "/api/v1/status")
    assert_response :unauthorized
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["X-Banco-Contract"]
    api_as(@tokens["bot_read"], "/api/v1/comments/1/reply", method: :post, body: { confirm: true })
    assert_response :forbidden
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  # ---- the health check for readers and for the edge

  test "health from a reader or through the edge skips the browser probes and redacts what failed" do
    seen = []
    health = ->(chrome:, **) { seen << chrome; { ok: false, problems: [ "db" ], db: "error: SQLite3::Exception: /data/db/x leaked", chrome: "skipped", pages: { status: "error: secret path" } } }
    Health.stub(:check, health) do
      api_as(@tokens["bot_read"], "/api/v1/health")
      assert_response :success
      assert_equal "error", json["db"]
      assert_equal({ "status" => "error" }, json["pages"])
      assert_not_includes response.body, "leaked"
      api_as(@tokens["agent_claude"], "/api/v1/health", remote_addr: EDGE)
      api_as(@tokens["teacher"], "/api/v1/health?chrome=1")
      assert_equal [ false, false ], seen # the content token through the edge was refused before the probe
      api_as(@tokens["agent_claude"], "/api/v1/health")
      assert_includes response.body, "SQLite3::Exception" # the local agent sees the whole report
      assert_equal [ false, false, true ], seen
    end
  end

  test "Health.redact keeps the facts and drops the messages" do
    report = { ok: false, db: "error: X: boom", queue: "ok", harness: "unreachable: Ferrum::Error: http://h:3200", validation_queue: { error: "Y: bad" }, list: [ "error: Z" ] }
    assert_equal({ ok: false, db: "error", queue: "ok", harness: "unreachable", validation_queue: { error: "error" }, list: [ "error" ] }, Health.redact(report))
  end
end
