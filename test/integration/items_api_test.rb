require "test_helper"

class ItemsApiTest < ActionDispatch::IntegrationTest
  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "items test")
    @math = Subject.create!(key: "math", name_it: "Matematica", position: 1)
    @other = Subject.create!(key: "italian", name_it: "Italiano", position: 2)
    @a = Item.create!(subject: @math, key: "math-a", kind: "generator")
    @a1 = rev(@a, 1, "failed")
    @a2 = rev(@a, 2, "passed")
    @b = Item.create!(subject: @other, key: "other-b", kind: "static")
    @b1 = rev(@b, 1, "passed")
  end

  def rev(item, seq, status)
    r = ItemRevision.create!(item: item, seq: seq, body_json: "{}")
    ItemValidation.create!(item_revision: r, seq: 1, status: status) if status
    r
  end

  def api(path) = on(:api, path, headers: { "Authorization" => "Bearer #{@token}" })

  test "lists every revision of a subject's items, marking the current one" do
    api("/api/v1/items?subject=math")
    assert_response :ok
    rows = response.parsed_body["rows"]
    assert_equal [ [ "math-a", @a1.id, "failed", false ], [ "math-a", @a2.id, "passed", true ] ],
                 rows.map { |r| r.values_at("item", "revision_id", "status", "current") }
    assert_equal %w[math], rows.map { |r| r["subject"] }.uniq
    assert_equal [ 0, 0 ], rows.last.values_at("reviews", "blind_solves")
  end

  test "current=1 keeps only the latest revision; no subject lists every subject" do
    api("/api/v1/items?subject=math&current=1")
    assert_equal [ @a2.id ], response.parsed_body["rows"].map { |r| r["revision_id"] }
    api("/api/v1/items?current=1")
    assert_equal [ @a2.id, @b1.id ].sort, response.parsed_body["rows"].map { |r| r["revision_id"] }.sort
  end

  test "a clean item that waits for its verifier shows awaiting_verifier in items list and work status (D-157)" do
    r = ItemRevision.create!(item: @b, seq: 2, body_json: "{}")
    ItemValidation.create!(item_revision: r, seq: 1, status: "failed", codes_json: "[\"E-VERIFY-STALE\"]")
    api("/api/v1/items?subject=italian&current=1")
    assert_equal [ "awaiting_verifier" ], response.parsed_body["rows"].map { |x| x["status"] }
    api("/api/v1/work/revisions/#{r.id}")
    assert_equal [ "awaiting_verifier", true, [ "E-VERIFY-STALE" ] ], response.parsed_body.values_at("status", "settled", "codes")
    ItemValidation.create!(item_revision: r, seq: 2, status: "failed", codes_json: "[\"E-VERIFY-STALE\",\"E-READ\"]")
    api("/api/v1/items?subject=italian&current=1")
    assert_equal [ "failed" ], response.parsed_body["rows"].map { |x| x["status"] }
    api("/api/v1/work/revisions/#{r.id}")
    assert_equal "failed", response.parsed_body["status"]
  end

  test "a superseded revision that was awaiting_verifier is listed as superseded (D-206)" do
    old = ItemRevision.create!(item: @b, seq: 2, body_json: "{}")
    ItemValidation.create!(item_revision: old, seq: 1, status: "failed", codes_json: "[\"E-VERIFY-STALE\"]")
    new = ItemRevision.create!(item: @b, seq: 3, body_json: "{}")
    ItemValidation.create!(item_revision: new, seq: 1, status: "failed", codes_json: "[\"E-VERIFY-STALE\"]")
    api("/api/v1/items?subject=italian")
    rows = response.parsed_body["rows"].select { |x| [ old.id, new.id ].include?(x["revision_id"]) }
    assert_equal [ [ old.id, "superseded", false ], [ new.id, "awaiting_verifier", true ] ],
                 rows.map { |x| x.values_at("revision_id", "status", "current") }
    api("/api/v1/work/revisions/#{old.id}")
    assert_equal "awaiting_verifier", response.parsed_body["status"]
  end

  test "an unknown subject is 404 E-NOT-FOUND and a token is required" do
    api("/api/v1/items?subject=nope")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", response.parsed_body["code"]
    on(:api, "/api/v1/items")
    assert_response :unauthorized
  end

  test "a current revision carries what a blueprint pins: skill, component, instances, low-guess instances" do
    body = { "kind" => "diagnosis_item", "skill" => "math.a", "component" => "number", "expected_seconds" => 90 }
    r = ItemRevision.create!(item: @a, seq: 3, body_json: body.to_json)
    ItemValidation.create!(item_revision: r, seq: 1, status: "passed")
    2.times { |i| ItemInstance.create!(item_revision: r, display_json: "{}", answer_json: "{}", fingerprint: "f#{i}") }
    api("/api/v1/items?subject=math&current=1")
    row = response.parsed_body["rows"].first
    assert_equal [ r.id, "math.a", "number", 90, 2 ], row.values_at("revision_id", "skill", "component", "expected_seconds", "instances")
    assert_kind_of Integer, row["low_guess_instances"]
    api("/api/v1/items?subject=math")
    assert_not response.parsed_body["rows"].first.key?("skill"), "older revisions stay light"
  end
end
