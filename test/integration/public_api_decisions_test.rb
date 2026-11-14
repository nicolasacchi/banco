require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/public_api_tokens"

# D-327: a teacher token records the teacher's decisions over the API, through the same recorder, gates and flag as the
# console (D-260); without confirm: true it is a dry run. The list is for audit, readable by bot_read too.
class PublicApiDecisionsTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include PublicApiTokens

  setup do
    build_decision_world
    @teacher = issue_token("teacher")
    @bot = issue_token("bot_read")
    @agent = issue_token("agent_claude")
  end

  def decide(kind, token: @teacher, params: nil, confirm: nil, reason: nil, attest: nil, headers: {}, **extra)
    body = { kind: kind }
    body[:params] = params if params
    body[:confirm] = confirm unless confirm.nil?
    body[:reason_it] = reason if reason
    body[:attest_it] = attest if attest
    api_as(token, "/api/v1/decisions", method: :post, body: body.merge(extra), headers: headers)
  end

  # ---- the dry run

  test "without confirm it is a dry run: the payload and no row" do
    assert_no_difference "Decision.count" do
      decide("approve_skill_graph", params: { revision_id: @graph.id })
    end
    assert_response :success
    assert_equal [ false, true, true, [] ], json.values_at("recorded", "dry_run", "allowed", "reasons")
    assert_equal @graph.id, json["payload"]["revision_id"]
    assert_equal [ "api", public_id(@teacher) ], json["payload"].values_at("via", "token")
    assert_nil SubjectStage.approved_graph(@subject)
    decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: false)
    assert_response :success
    assert_equal 0, Decision.count
  end

  test "the dry-run header wins over confirm: true" do
    assert_no_difference "Decision.count" do
      api_as(@teacher, "/api/v1/decisions", method: :post, body: { kind: "approve_skill_graph", params: { revision_id: @graph.id }, confirm: true }, headers: { "X-Banco-Dry-Run" => "1" })
    end
    assert_response :success
    assert_equal false, json["recorded"]
  end

  test "a dry run of a decision the gate refuses says why and writes nothing" do
    approve_graph_row!
    assert_no_difference "Decision.count" do
      decide("approve_skill_graph", params: { revision_id: @graph.id })
    end
    assert_response :unprocessable_entity
    assert_equal "E-DECISION-INVALID", json["code"]
    assert_includes json["reasons"].first, "already approved"
  end

  # ---- confirm

  test "confirm records exactly one decision with via api, the token and the teacher" do
    assert_difference "Decision.count", 1 do
      decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: true, reason: "Approvato dal docente.", remote_addr: "ignored",
                                                        headers: { "User-Agent" => "public-api-test/1", "X-Request-Id" => "req-abc-123" })
    end
    assert_response :created
    d = Decision.order(:id).last
    assert_equal [ "approve_skill_graph", @subject, "nik", "api" ], [ d.kind, d.subject, d.teacher_login, d.groups ]
    assert_equal "127.0.0.1", d.remote_addr
    assert_equal "public-api-test/1", d.user_agent # the caller's own, never a label
    assert_equal "POST /api/v1/decisions", d.request_path
    assert_equal "req-abc-123", d.request_id # the request's own, so a row matches the logs
    assert d.api?
    assert_not d.console?
    payload = JSON.parse(d.payload_json)
    assert_equal [ @graph.id, "api", public_id(@teacher), "Approvato dal docente." ], payload.values_at("revision_id", "via", "token", "api_reason")
    assert_equal "api", d.via
    assert_equal @graph, SubjectStage.approved_graph(@subject)
    assert_equal "api", SubjectStage.approval_origin(@subject, "approve_skill_graph")
    assert_equal [ true, false, d.id ], [ json["recorded"], json["dry_run"], json["decision"]["id"] ]
    assert_equal [ "approve_skill_graph", "math", "api" ], json["decision"].values_at("kind", "subject", "via")
  end

  test "the client address the edge proxy saw is the row's address" do
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    decide_via_proxy = ->(forwarded) {
      api_as(@teacher, "/api/v1/decisions", method: :post, body: { kind: "approve_skill_graph", params: { revision_id: @graph.id }, confirm: true },
                                            headers: { "X-Forwarded-For" => forwarded }, remote_addr: EDGE)
    }
    decide_via_proxy.call("203.0.113.9")
    assert_response :created
    assert_equal "203.0.113.9", Decision.order(:id).last.remote_addr
  ensure
    ENV.delete("BANCO_EDGE_PROXY")
  end

  test "the same decision twice: the second is refused by the gate" do
    decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: true)
    assert_response :created
    assert_no_difference "Decision.count" do
      decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: true)
    end
    assert_response :unprocessable_entity
    assert_equal "E-DECISION-INVALID", json["code"]
  end

  test "the parameters of a kind and its reason go through as on the console" do
    finding = ReviewFinding.create!(item_revision: @short, source: "review", severity: "major", field: "prompt", quote: "q", problem_it: "p", fix_it: "f")
    decide("dispose_finding", params: { finding_id: finding.id, disposition: "dismissed" }, reason: "Il testo è chiaro.", confirm: true)
    assert_response :created, json.inspect
    payload = JSON.parse(Decision.order(:id).last.payload_json)
    assert_equal [ finding.id, "dismissed", "Il testo è chiaro.", "api" ], payload.values_at("finding_id", "disposition", "reason_it", "via")
    decide("dispose_finding", params: { finding_id: finding.id, disposition: "dismissed" }, confirm: true)
    assert_response :unprocessable_entity # a reason is required
    decide("confirm_grade", params: { grade_proposal_id: @proposal.id }, confirm: true)
    assert_response :created, json.inspect
    assert_equal 2, Decision.count
  end

  # ---- refusals

  test "the flag off refuses a dry run and a confirm, and writes nothing" do
    ENV["BANCO_DECISIONS_ENABLED"] = "0"
    [ nil, true ].each do |confirm|
      assert_no_difference "Decision.count" do
        decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: confirm)
      end
      assert_response :forbidden
      assert_equal [ "E-TEACHER-REFUSED", "disabled" ], json.values_at("code", "reason")
    end
  end

  test "a teacher who left the list is refused" do
    ENV["BANCO_TEACHER_USERS"] = "someone-else"
    assert_no_difference "Decision.count" do
      decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: true)
    end
    assert_response :forbidden
    assert_equal "teacher_not_listed", json["reason"]
  end

  test "bot_read and the content agents never decide" do
    assert_no_difference "Decision.count" do
      decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: true, token: @bot)
      assert_equal "read_only_token", json["reason"]
      decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: true, token: @agent)
      assert_equal "token_role", json["reason"]
      decide("approve_skill_graph", params: { revision_id: @graph.id }, token: @bot) # not even a dry run
      assert_response :forbidden
    end
  end

  test "an unknown kind, a missing target and a malformed body" do
    decide("approve_everything", confirm: true)
    assert_response :unprocessable_entity
    assert_equal "E-DECISION-INVALID", json["code"]
    decide("approve_skill_graph", params: { revision_id: 999_999 }, confirm: true)
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    api_as(@teacher, "/api/v1/decisions", method: :post, body: { params: {} })
    assert_equal [ 422, "E-FILES", "kind" ], [ response.status, json["code"], json["field"] ]
    api_as(@teacher, "/api/v1/decisions", method: :post, body: { kind: "approve_skill_graph", params: "math" })
    assert_equal "params", json["field"]
    api_as(@teacher, "/api/v1/decisions", method: :post, body: { kind: "approve_skill_graph", confirm: "yes" })
    assert_equal "confirm", json["field"]
    api_as(@teacher, "/api/v1/decisions", method: :post, body: { kind: "approve_skill_graph", reason_it: 3 })
    assert_equal "reason_it", json["field"]
    on(:api, "/api/v1/decisions", method: :post, headers: { "Authorization" => "Bearer #{@teacher}", "Content-Type" => "application/json" }, params: "not json")
    assert_equal "E-FILES", json["code"]
    assert_equal 0, Decision.count
  end

  test "attest_it is refused for a kind that takes none, and must be words" do
    decide("approve_skill_graph", params: { revision_id: @graph.id }, attest: "Parole.", confirm: true)
    assert_response :unprocessable_entity
    assert_includes json["reasons"].first, "attest_it is accepted only for approve_topic and approve_blueprint"
    decide("approve_blueprint", params: { revision_id: @blueprint.id }, attest: "  ")
    assert_response :unprocessable_entity
    assert_includes json["reasons"].first, "attest_it must hold"
    assert_equal 0, Decision.count
  end

  # ---- the list, for audit

  test "the list shows what was recorded, with its origin, oldest first, from the id given" do
    approve_graph_row!
    decide("approve_skill_graph", params: { revision_id: 999_999 }, confirm: true) # not recorded
    api_as(@bot, "/api/v1/decisions")
    assert_response :success
    assert_equal [ "approve_skill_graph" ], json["decisions"].map { |d| d["kind"] }
    first = json["decisions"].first
    assert_equal [ "math", "web", "nik" ], first.values_at("subject", "via", "teacher")
    assert first["created_at"].present?
    decide("approve_blueprint", params: { revision_id: @blueprint.id }, confirm: true) # refused: the gate wants a lot
    start = Decision.maximum(:id)
    Decision.create!(kind: "record_consent", payload_json: { via: "console" }.to_json, request_id: SecureRandom.uuid, teacher_login: "nik", groups: "console", remote_addr: "console")
    decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: true) # already approved by the row above
    api_as(@teacher, "/api/v1/decisions?since=#{first['id']}")
    assert_equal [ "record_consent" ], json["decisions"].map { |d| d["kind"] }
    assert_equal "console", json["decisions"].first["via"]
    assert_equal start + 1, json["next_since"]
    assert_equal false, json["more"]
  end

  test "an API decision is in the list with via api, the token and the payload" do
    decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: true)
    api_as(@bot, "/api/v1/decisions?since=0")
    row = json["decisions"].sole
    assert_equal [ "approve_skill_graph", "math", "api", public_id(@teacher), "nik" ], row.values_at("kind", "subject", "via", "token", "teacher")
    assert_equal @graph.id, row["payload"]["revision_id"]
  end

  test "the list pages with limit and filters by kind, and refuses a bad number" do
    3.times { |i| Decision.create!(kind: "record_consent", payload_json: "{}", request_id: "r#{i}", teacher_login: "nik", groups: "banco-teacher", remote_addr: "1.1.1.1") }
    approve_graph_row!
    api_as(@bot, "/api/v1/decisions?limit=2")
    assert_equal [ 2, true ], [ json["decisions"].size, json["more"] ]
    api_as(@bot, "/api/v1/decisions?since=#{json['next_since']}&limit=5")
    assert_equal 2, json["decisions"].size
    assert_equal false, json["more"]
    api_as(@bot, "/api/v1/decisions?kind=approve_skill_graph")
    assert_equal [ "approve_skill_graph" ], json["decisions"].map { |d| d["kind"] }
    api_as(@bot, "/api/v1/decisions?since=abc")
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
  end

  test "a reconcile run takes an API decision for a decision with provenance" do
    decide("approve_skill_graph", params: { revision_id: @graph.id }, confirm: true)
    result = DecisionReconciliation.call(since: 1.hour.ago)
    assert_empty(result.items.select { |i| i[:type] == "decision_without_provenance" })
  end
end
