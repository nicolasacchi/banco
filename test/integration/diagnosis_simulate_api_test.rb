require "test_helper"
require "support/decision_world"

# POST /api/v1/diagnosis/simulate: a dry run of the pure engine over the API.
class DiagnosisSimulateApiTest < ActionDispatch::IntegrationTest
  FIXTURE = Rails.root.join("test/fixtures/blueprints/three-skill.json")

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "simulate test")
    @bundle = JSON.parse(File.read(FIXTURE))
  end

  def auth = { "Authorization" => "Bearer #{@token}" }

  def simulate(body, token: true)
    on(:api, "/api/v1/diagnosis/simulate", method: :post, headers: token ? auth : {}, params: body, as: :json)
  end

  test "all-wrong ends frontier_empty and returns the trace and the final states" do
    simulate({ bundle: @bundle, script: "all-wrong" })
    assert_response :success
    out = response.parsed_body
    assert_equal "frontier_empty", out["end_reason"]
    assert_equal true, out["dry_run"]
    assert_equal "all-wrong", out["script"]
    assert_equal %w[to_recover], out["states"].map { |s| s["state"] }.uniq
    assert_equal 6, out["served"]
    assert_equal "sitting_started", out["trace"].first["kind"]
    assert_equal "run_closed", out["trace"].last["kind"]
    assert_equal Contract.digest, response.headers["X-Banco-Contract"]
  end

  test "all-correct and mixed run through the same engine" do
    simulate({ bundle: @bundle, script: "all-correct" })
    assert_equal "demonstrated", response.parsed_body["states"].find { |s| s["skill"] == "math.linear-equation-integer" }["state"]
    simulate({ bundle: @bundle, script: "mixed" })
    assert_equal "two_of_three", response.parsed_body["states"].find { |s| s["skill"] == "math.linear-equation-integer" }["reason"]
  end

  test "a script given as a document" do
    simulate({ bundle: @bundle, script: { default: { verdict: "dont_know" }, seconds: 15 } })
    assert_response :success
    assert_equal 15 * response.parsed_body["served"], response.parsed_body["counted_seconds"]
  end

  test "a bare blueprint is a flat subject" do
    simulate({ bundle: @bundle["blueprint"], script: "all-wrong" })
    assert_response :success
    assert_equal "frontier_empty", response.parsed_body["end_reason"]
  end

  test "it writes nothing" do
    counts = -> { [ DiagnosisRun, DiagnosisEvent, Attempt, AppEvent ].map(&:count) }
    before = counts.call
    simulate({ bundle: @bundle, script: "all-wrong" })
    assert_equal before, counts.call
  end

  test "no token is 401" do
    simulate({ bundle: @bundle, script: "all-wrong" }, token: false)
    assert_response :unauthorized
  end

  test "the web listener has no such route" do
    on(:web, "/api/v1/diagnosis/simulate", method: :post, params: { bundle: @bundle }, as: :json)
    assert_response :not_found
  end

  test "an unknown script is 422 E-SIMULATE-INPUT" do
    simulate({ bundle: @bundle, script: "all-maybe" })
    assert_response :unprocessable_entity
    assert_equal "E-SIMULATE-INPUT", response.parsed_body["code"]
    assert_equal "script", response.parsed_body["field"]
  end

  test "an unknown verdict in a script is 422 E-SIMULATE-INPUT" do
    simulate({ bundle: @bundle, script: { default: { verdict: "maybe" } } })
    assert_response :unprocessable_entity
    assert_equal "E-SIMULATE-INPUT", response.parsed_body["code"]
  end

  test "a prerequisite cycle is 422 E-GRAPH-CYCLE" do
    @bundle["graph"]["skills"].first["prerequisites"] = [ "math.linear-equation-integer" ]
    simulate({ bundle: @bundle, script: "all-wrong" })
    assert_response :unprocessable_entity
    assert_equal "E-GRAPH-CYCLE", response.parsed_body["code"]
  end

  test "a bundle that is not a blueprint is 422 and names the field" do
    simulate({ bundle: { subject: "math", entries: [] }, script: "all-wrong" })
    assert_response :unprocessable_entity
    assert_equal "E-SIMULATE-INPUT", response.parsed_body["code"]
    assert_includes response.parsed_body["message"], "entries"
  end

  test "a body that is not JSON is 422" do
    on(:api, "/api/v1/diagnosis/simulate", method: :post, headers: auth.merge("Content-Type" => "application/json"), params: "not json")
    assert_response :unprocessable_entity
    assert_equal "E-SIMULATE-INPUT", response.parsed_body["code"]
  end

  test "a subject with no blueprint is 404 E-BLUEPRINT-UNKNOWN" do
    Subject.create!(key: "math", name_it: "Matematica", position: 1)
    simulate({ subject: "math", script: "all-wrong" })
    assert_response :not_found
    assert_equal "E-BLUEPRINT-UNKNOWN", response.parsed_body["code"]
  end

  test "a stale pin is a W-STALE-PIN warning, by subject and by bare blueprint (D-146)" do
    extend DecisionWorld
    build_decision_world
    pinned = ItemRevision.find(@blueprint.pinned_item_revision_ids.first)
    simulate({ subject: @subject.key, script: "all-correct" })
    assert_empty response.parsed_body["warnings"].select { |w| w["code"] == "W-STALE-PIN" }
    newer = ItemRevision.create!(item: pinned.item, seq: pinned.item.revisions.maximum(:seq) + 1, body_json: pinned.body_json)
    ItemValidation.create!(item_revision: newer, seq: 1, status: "passed")
    simulate({ subject: @subject.key, script: "all-correct" })
    warning = response.parsed_body["warnings"].find { |w| w["code"] == "W-STALE-PIN" }
    assert_includes warning["message"], "#{newer.id} replaced it"
    simulate({ bundle: JSON.parse(@blueprint.body_json), script: "all-correct" })
    assert(response.parsed_body["warnings"].any? { |w| w["code"] == "W-STALE-PIN" })
  end
end
