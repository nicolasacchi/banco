require "test_helper"

class BriefsApiTest < ActionDispatch::IntegrationTest
  setup { @token = ApiToken.issue!(role: "agent_claude", label: "briefs test") }

  def auth(token = @token) = { "Authorization" => "Bearer #{token}" }

  test "a brief is served with name, version, sha256 and body" do
    on(:api, "/api/v1/briefs/diagnosis-item", headers: auth)
    assert_response :success
    body = response.parsed_body
    assert_equal "diagnosis-item", body["name"]
    assert_equal 1, body["version"]
    assert_match(/\A\h{64}\z/, body["sha256"])
    assert_includes body["body"], "# Brief: diagnosis items"
    assert_equal Digest::SHA256.file(Rails.root.join("briefs/diagnosis-item.md")).hexdigest, body["sha256"]
    assert_equal Contract.digest, response.headers["X-Banco-Contract"]
  end

  test "every brief of the repository is served" do
    Brief.names.each do |name|
      on(:api, "/api/v1/briefs/#{name}", headers: auth)
      assert_response :success, name
    end
  end

  test "no token is 401 and a revoked token is 401" do
    on(:api, "/api/v1/briefs/diagnosis-item")
    assert_response :unauthorized
    ApiTokenRevocation.create!(api_token: ApiToken.find_by!(public_id: @token[/bnc_(\w{8})_/, 1]))
    on(:api, "/api/v1/briefs/diagnosis-item", headers: auth)
    assert_response :unauthorized
    assert_equal "E-AUTH", response.parsed_body["code"]
  end

  test "an unknown brief is 404 E-BRIEF-UNKNOWN naming the available ones" do
    on(:api, "/api/v1/briefs/nope", headers: auth)
    assert_response :not_found
    assert_equal "E-BRIEF-UNKNOWN", response.parsed_body["code"]
    assert_includes response.parsed_body["next"], "diagnosis-item"
  end

  test "a name that is not a plain brief name never reaches the file system" do
    [ "..%2Fconfig%2Fdatabase", "diagnosis-item.md", "DIAGNOSIS", "%2Fetc%2Fpasswd" ].each do |name|
      on(:api, "/api/v1/briefs/#{name}", headers: auth)
      assert_response :not_found, name
    end
    assert_nil Brief.find("../config/database")
    assert_nil Brief.find("diagnosis-item/../x")
  end

  test "briefs are not served on the web or harness listeners" do
    %i[web harness].each do |listener|
      on(listener, "/api/v1/briefs/diagnosis-item", headers: auth)
      assert_response :not_found, listener
    end
  end

  test "the contract lists brief show with its path and no decision command" do
    cmd = Contract.parsed["commands"].find { |c| c["name"] == "brief show" }
    assert_equal [ "GET", "/api/v1/briefs/:name", [ "name" ] ], [ cmd["method"], cmd["path"], cmd["args"] ]
    assert_includes cmd["error_codes"], "E-BRIEF-UNKNOWN"
  end
end
