require "test_helper"
require_relative "../support/public_api_tokens"

# D-332: view links over the API. A bot_read or teacher token creates the temporary URL (the one POST a bot_read token may
# send), lists and revokes its own links; the content agents' tokens do none of it. The URL carries the raw token, which is
# stored nowhere: only its sha256.
class ViewLinksApiTest < ActionDispatch::IntegrationTest
  include PublicApiTokens

  EDGE = ListenerHelpers::EDGE_IP
  VIEW_URL = "https://api.banco.test".freeze
  PREFIX = "#{VIEW_URL}/v?view_token=".freeze

  setup do
    @saved_env = ENV.to_h.slice("BANCO_VIEW_URL", "BANCO_VIEW_LINKS_ENABLED", "BANCO_EDGE_PROXY")
    ENV["BANCO_VIEW_URL"] = VIEW_URL
    ENV["BANCO_VIEW_LINKS_ENABLED"] = "1"
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    @bot = issue_token("bot_read")
    @teacher = issue_token("teacher")
    @agent = issue_token("agent_claude")
  end

  teardown do
    %w[BANCO_VIEW_URL BANCO_VIEW_LINKS_ENABLED BANCO_EDGE_PROXY].each { |k| @saved_env.key?(k) ? ENV[k] = @saved_env[k] : ENV.delete(k) }
  end

  def create_link(token, body = nil, **options) = api_as(token, "/api/v1/view-links", method: :post, body: body, **options)

  def registry(token) = ApiToken.find_by!(public_id: public_id(token))

  def link_ids = ViewLink.order(:id).pluck(:id)

  def counts = [ ViewLink.count, ViewLinkRedemption.count, ViewLinkRevocation.count ]

  # ---- create

  test "a bot_read token creates a link: 201, the url with the raw token, only the sha256 stored" do
    create_link(@bot, { path: "/teacher/subjects/math/course", minutes: 30 })
    assert_response :created, json.inspect
    assert_operator json["url"], :start_with?, PREFIX
    raw = json["url"].delete_prefix(PREFIX)
    link = ViewLink.find(json["id"])
    assert_equal Digest::SHA256.hexdigest(raw), link.token_digest
    assert_equal registry(@bot), link.api_token
    assert_equal "/teacher/subjects/math/course", json["path"]
    assert_equal link.path, json["path"]
    assert_equal 30, json["minutes"]
    assert_equal link.expires_at.utc.iso8601, json["expires_at"]
    assert_in_delta 30.minutes.from_now.to_f, link.expires_at.to_f, 5
    assert ViewLink.connection.select_rows("SELECT * FROM view_links").flatten.none? { |v| v.to_s.include?(raw) }, "the raw token is in no column"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "a teacher token creates a link, and the defaults are /teacher for 60 minutes" do
    create_link(@teacher)
    assert_response :created, json.inspect
    assert_operator json["url"], :start_with?, PREFIX
    assert_equal [ "/teacher", 60 ], json.values_at("path", "minutes")
    assert_equal registry(@teacher), ViewLink.find(json["id"]).api_token
    create_link(@teacher, { path: nil, minutes: nil })
    assert_response :created
    assert_equal [ "/teacher", 60 ], json.values_at("path", "minutes")
  end

  test "the url redeems: the token in the answer is the one the ledger knows" do
    create_link(@bot)
    link = ViewLinks.redeem(json["url"].delete_prefix(PREFIX))
    assert_equal json["id"], link&.id
  end

  test "creation through the edge proxy works for the public roles and is refused for a content agent" do
    create_link(@bot, nil, remote_addr: EDGE)
    assert_response :created, json.inspect
    create_link(@teacher, nil, remote_addr: EDGE)
    assert_response :created, json.inspect
    create_link(@agent, nil, remote_addr: EDGE)
    assert_response :forbidden
    assert_equal [ "E-AUTH", "not_public_role" ], json.values_at("code", "reason")
    assert_equal 2, ViewLink.count
  end

  test "the content agents' tokens refuse every view link command with 403 token_role" do
    [ [ :post, "/api/v1/view-links", {} ], [ :get, "/api/v1/view-links", nil ], [ :post, "/api/v1/view-links/1/revoke", {} ],
      [ :post, "/api/v1/view-links/revoke-all", {} ] ].each do |method, path, body|
      api_as(@agent, path, method: method, body: body)
      assert_response :forbidden, path
      assert_equal [ "E-AUTH", "token_role" ], json.values_at("code", "reason"), path
    end
    assert_equal [ 0, 0, 0 ], counts
  end

  test "no token or a wrong one is 401 and creates nothing" do
    create_link(nil)
    assert_response :unauthorized
    create_link("bnc_abcdefgh_#{'a' * 43}")
    assert_response :unauthorized
    assert_equal 0, ViewLink.count
  end

  test "a bot_read token is still refused on every other POST" do
    [ [ "/api/v1/decisions", { kind: "approve_skill_graph", params: { subject: "math" }, confirm: true } ],
      [ "/api/v1/comments/1/reply", { text_it: "Ciao", confirm: true } ],
      [ "/api/v1/sessions", { role: "author", agent: "a", model: "m" } ] ].each do |path, body|
      api_as(@bot, path, method: :post, body: body)
      assert_response :forbidden, path
      assert_equal [ "E-AUTH", "read_only_token" ], json.values_at("code", "reason"), path
    end
    assert_equal 0, ViewLink.count
  end

  test "a teacher who left the teacher list cannot create a link" do
    ENV["BANCO_TEACHER_USERS"] = "someone-else"
    create_link(@teacher)
    assert_response :forbidden
    assert_equal "teacher_not_listed", json["reason"]
    assert_equal 0, ViewLink.count
  end

  test "with the feature off creation answers E-VIEW-DISABLED 503 and creates nothing" do
    ENV["BANCO_VIEW_LINKS_ENABLED"] = nil
    create_link(@bot)
    assert_response :service_unavailable
    assert_equal [ "E-VIEW-DISABLED", "view_links" ], json.values_at("code", "field")
    ENV["BANCO_VIEW_LINKS_ENABLED"] = "1"
    ENV.delete("BANCO_VIEW_URL")
    create_link(@teacher)
    assert_response :service_unavailable
    assert_equal "E-VIEW-DISABLED", json["code"]
    assert_equal 0, ViewLink.count
  end

  test "a path that is not a teacher page is E-VIEW-PATH 422 with the field path" do
    [ "/today", "/teacher/preview", "/teacher/preview/x", "//evil", "/teacher/../x", "/teacher/" + "a" * 300, "https://evil.test/teacher", 7 ].each do |path|
      create_link(@bot, { path: path })
      assert_response :unprocessable_entity, path.inspect
      assert_equal [ "E-VIEW-PATH", "path" ], json.values_at("code", "field"), path.inspect
      assert json["message"].present? && json["next"].present?
    end
    assert_equal 0, ViewLink.count
  end

  test "minutes outside 5..1440 or not a whole number is E-VIEW-PATH 422 with the field minutes" do
    [ 4, 1441, "x", 0, -1, 1.5, true ].each do |minutes|
      create_link(@bot, { minutes: minutes })
      assert_response :unprocessable_entity, minutes.inspect
      assert_equal [ "E-VIEW-PATH", "minutes" ], json.values_at("code", "field"), minutes.inspect
    end
    [ 5, 1440 ].each do |minutes|
      create_link(@bot, { minutes: minutes })
      assert_response :created, minutes.inspect
    end
  end

  test "a body that is not a JSON object is refused" do
    api_as(@bot, "/api/v1/view-links", method: :post, headers: { "Content-Type" => "application/json" }, body: nil)
    assert_response :created, "an empty body takes the defaults"
    post "/api/v1/view-links", params: "[1]", headers: { "Authorization" => "Bearer #{@bot}", "Content-Type" => "application/json" },
         env: { "banco.test_listener" => "api", "REMOTE_ADDR" => "127.0.0.1" }
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    assert_equal 1, ViewLink.count
  end

  test "the 21st active link of a token is E-VIEW-LIMIT 429; another token and a revocation are not affected" do
    ViewLinks::LIMIT.times do
      create_link(@bot, { minutes: 5 })
      assert_response :created
    end
    create_link(@bot)
    assert_response :too_many_requests
    assert_equal [ "E-VIEW-LIMIT", "view_links" ], json.values_at("code", "field")
    assert_equal ViewLinks::LIMIT, ViewLink.count

    create_link(@teacher)
    assert_response :created

    api_as(@bot, "/api/v1/view-links/#{link_ids.first}/revoke", method: :post)
    assert_response :success
    create_link(@bot)
    assert_response :created
    create_link(@bot)
    assert_response :too_many_requests
  end

  # ---- list

  test "list shows only the token's own links with their state and redemption counts, never a url" do
    create_link(@bot, { path: "/teacher/a" })
    first = json["id"]
    first_raw = json["url"].delete_prefix(PREFIX)
    create_link(@bot, { path: "/teacher/b" })
    second = json["id"]
    create_link(@teacher)
    others = json["id"]
    2.times { ViewLinks.redeem(first_raw) }
    api_as(@bot, "/api/v1/view-links/#{second}/revoke", method: :post)

    api_as(@bot, "/api/v1/view-links")
    assert_response :success
    links = json["links"]
    assert_equal [ second, first ], links.map { |l| l["id"] }, "newest first, this token's only"
    refute_includes links.map { |l| l["id"] }, others
    assert_equal %w[active created_at expires_at id path redemptions revoked], links.first.keys.sort
    assert_equal [ [ "/teacher/b", false, true, 0 ], [ "/teacher/a", true, false, 2 ] ], links.map { |l| l.values_at("path", "active", "revoked", "redemptions") }
    refute_includes response.body, first_raw
    refute_includes response.body, "view_token"

    api_as(@teacher, "/api/v1/view-links")
    assert_equal [ others ], json["links"].map { |l| l["id"] }
  end

  test "an expired link is listed as not active" do
    create_link(@bot, { minutes: 5 })
    travel 6.minutes
    api_as(@bot, "/api/v1/view-links")
    assert_response :success
    assert_equal [ false, false ], json["links"].first.values_at("active", "revoked")
  end

  test "list is empty for a token with no links and the feature off still lists" do
    api_as(@bot, "/api/v1/view-links")
    assert_response :success
    assert_equal({ "links" => [] }, json)
    create_link(@bot)
    ENV["BANCO_VIEW_LINKS_ENABLED"] = nil
    api_as(@bot, "/api/v1/view-links")
    assert_response :success
    assert_equal [ false, false ], json["links"].first.values_at("active", "revoked")
  end

  # ---- revoke

  test "revoke appends one row, is idempotent, and the link stops redeeming" do
    create_link(@bot)
    id = json["id"]
    raw = json["url"].delete_prefix(PREFIX)
    api_as(@bot, "/api/v1/view-links/#{id}/revoke", method: :post)
    assert_response :success, json.inspect
    assert_equal [ id, true ], json.values_at("id", "revoked")
    revoked_at = json["revoked_at"]
    assert_equal ViewLinkRevocation.last.created_at.utc.iso8601, revoked_at
    assert_equal registry(@bot), ViewLinkRevocation.last.api_token

    travel 1.minute
    api_as(@bot, "/api/v1/view-links/#{id}/revoke", method: :post)
    assert_response :success
    assert_equal revoked_at, json["revoked_at"]
    assert_equal 1, ViewLinkRevocation.count
    assert_nil ViewLinks.redeem(raw)
  end

  test "a link of another token, or an unknown id, is 404 E-NOT-FOUND and nothing is revoked" do
    create_link(@teacher)
    id = json["id"]
    api_as(@bot, "/api/v1/view-links/#{id}/revoke", method: :post)
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    api_as(@bot, "/api/v1/view-links/999999/revoke", method: :post)
    assert_response :not_found
    assert_equal 0, ViewLinkRevocation.count
    assert_predicate ViewLink.find(id), :active?
  end

  # ---- revoke-all (D-333)

  def revoke_all(token, **options) = api_as(token, "/api/v1/view-links/revoke-all", method: :post, **options)

  test "revoke-all ends every open link of this token only: not the revoked, not the expired, not another token's" do
    create_link(@bot, { minutes: 120 })
    first = json["id"]
    create_link(@bot, { minutes: 120 })
    second = json["id"]
    raw_second = json["url"].delete_prefix(PREFIX)
    create_link(@bot, { minutes: 5 })
    expired = json["id"]
    create_link(@bot, { minutes: 120 })
    last = json["id"]
    create_link(@teacher, { minutes: 120 })
    others = json["id"]
    api_as(@bot, "/api/v1/view-links/#{second}/revoke", method: :post)
    revoked_before = ViewLinkRevocation.find_by!(view_link_id: second)
    travel 10.minutes # the 5-minute link has expired

    revoke_all(@bot)
    assert_response :success, json.inspect
    assert_equal({ "revoked" => [ first, last ], "count" => 2 }, json)
    assert_equal "no-store", response.headers["Cache-Control"]
    [ first, last ].each { |id| assert_equal registry(@bot), ViewLinkRevocation.find_by!(view_link_id: id).api_token }
    assert_equal revoked_before.attributes, ViewLinkRevocation.find_by!(view_link_id: second).attributes, "an earlier revocation is not touched"
    assert_nil ViewLinkRevocation.find_by(view_link_id: expired), "an expired link needs none"
    assert_nil ViewLinkRevocation.find_by(view_link_id: others), "another token's link is not touched"
    assert_predicate ViewLink.find(others), :active?
    assert_equal 3, ViewLinkRevocation.count
    [ first, last ].each { |id| assert_not ViewLink.find(id).active? }
    assert_nil ViewLinks.redeem(raw_second)

    revoke_all(@bot) # idempotent: nothing is open any more
    assert_response :success
    assert_equal({ "revoked" => [], "count" => 0 }, json)
    assert_equal 3, ViewLinkRevocation.count

    api_as(@bot, "/api/v1/view-links")
    assert_equal [ false ], json["links"].map { |l| l["active"] }.uniq, "the list shows every link of the token as not active"
  end

  test "revoke-all with no link at all answers an empty list and writes nothing" do
    [ @bot, @teacher ].each do |token|
      revoke_all(token)
      assert_response :success
      assert_equal({ "revoked" => [], "count" => 0 }, json)
    end
    assert_equal [ 0, 0, 0 ], counts
  end

  test "revoke-all frees the limit, works through the edge for the public roles and with the feature off" do
    ViewLinks::LIMIT.times { create_link(@bot, { minutes: 5 }) }
    create_link(@bot)
    assert_response :too_many_requests
    ENV["BANCO_VIEW_LINKS_ENABLED"] = nil # a link that the flag stopped is still ended for good
    revoke_all(@bot, remote_addr: EDGE)
    assert_response :success, json.inspect
    assert_equal ViewLinks::LIMIT, json["count"]
    ENV["BANCO_VIEW_LINKS_ENABLED"] = "1"
    assert_equal 0, ViewLink.all.count(&:active?)
    create_link(@bot)
    assert_response :created

    create_link(@teacher)
    revoke_all(@teacher, remote_addr: EDGE)
    assert_equal 1, json["count"]
    revoke_all(@agent, remote_addr: EDGE)
    assert_response :forbidden
    assert_equal [ "E-AUTH", "not_public_role" ], json.values_at("code", "reason")
  end

  test "revoke-all needs a token, a listed teacher and a reader role" do
    create_link(@teacher)
    revoke_all(nil)
    assert_response :unauthorized
    revoke_all(@agent)
    assert_response :forbidden
    assert_equal "token_role", json["reason"]
    ENV["BANCO_TEACHER_USERS"] = "someone-else"
    revoke_all(@teacher)
    assert_response :forbidden
    assert_equal "teacher_not_listed", json["reason"]
    assert_equal 0, ViewLinkRevocation.count
  end
end
