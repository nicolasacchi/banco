require "test_helper"

class ReferencesApiTest < ActionDispatch::IntegrationTest
  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "reference test")
    @ref = ReferenceText.create!(key: "brano-prova", title: "Brano di prova", source_url: "https://example.org/brano",
                                 sha256: Digest::SHA256.hexdigest("Una frase di prova."), body: "Una frase di prova.")
  end

  def api(path) = on(:api, path, headers: { "Authorization" => "Bearer #{@token}" })

  test "list gives key, title, source and word count, never the body" do
    api("/api/v1/references")
    assert_response :ok
    row = response.parsed_body["rows"].find { |r| r["key"] == "brano-prova" }
    assert_equal 4, row["words"]
    assert_equal "https://example.org/brano", row["source_url"]
    assert_not row.key?("body")
  end

  test "show gives the body; an unknown key is 404 E-NOT-FOUND" do
    api("/api/v1/references/brano-prova")
    assert_response :ok
    assert_equal "Una frase di prova.", response.parsed_body["body"]
    api("/api/v1/references/nessuno")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", response.parsed_body["code"]
  end

  test "a token is required and nothing writes a reference text" do
    on(:api, "/api/v1/references")
    assert_response :unauthorized
    on(:api, "/api/v1/references", method: :post, headers: { "Authorization" => "Bearer #{@token}" })
    assert_response :not_found
  end
end
