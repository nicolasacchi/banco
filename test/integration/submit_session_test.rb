require "test_helper"
require_relative "../support/validation_fixtures"

# D-152: graph and blueprint submits record the author session when one is sent and
# refuse a session header that is not a valid author session; none stays allowed.
class SubmitSessionTest < ActionDispatch::IntegrationTest
  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "submit session test")
    @subject = Subject.create!(key: "math", name_it: "Matematica", position: 1)
    source = SyllabusSource.create!(key: "prima-test", line_count: 3, sha256: "0" * 64)
    SyllabusLine.create!(syllabus_source: source, number: 1, text: "operazioni con i numeri relativi", origin: "pdf")
    SyllabusLine.create!(syllabus_source: source, number: 2, text: "PAGINA 2", origin: "transcript")
    SyllabusLine.create!(syllabus_source: source, number: 3, text: "una riga non citata", origin: "pdf")
    seconda = SyllabusSource.create!(key: "seconda-test", line_count: 1, sha256: "1" * 64)
    SyllabusLine.create!(syllabus_source: seconda, number: 1, text: "equazioni di primo grado", origin: "pdf")
  end

  def submit(session_header)
    headers = { "Authorization" => "Bearer #{@token}" }
    headers["X-Banco-Session"] = session_header if session_header
    Validation::Rules.with(coverage: { prima_source: "prima-test", ranges: { math: [ 1, 3 ] } }) do
      on(:api, "/api/v1/subjects/math/skill-graph", method: :post, headers: headers,
         params: { graph: ValidationFixtures::GRAPH }, as: :json)
    end
  end

  test "an error string in X-Banco-Session is refused and nothing is stored" do
    submit("E-USAGE give --agent")
    assert_response :unprocessable_entity
    assert_equal "E-SESSION", response.parsed_body["code"]
    assert_equal 0, SkillGraphRevision.count
  end

  test "a reviewer session is refused on a graph submit" do
    reviewer = AgentSession.create!(label: "t", role: "reviewer", agent: "a", model: "gpt-5.2")
    submit(reviewer.id.to_s)
    assert_response :unprocessable_entity
    assert_equal 0, SkillGraphRevision.count
  end

  test "an author session is recorded on the graph revision" do
    author = AgentSession.create!(label: "t", role: "author", agent: "a", model: "claude-opus-5-5")
    submit(author.id.to_s)
    assert_response :created
    assert_equal author.id, SkillGraphRevision.last.author_session_id
  end

  test "no session header still submits, authorship unrecorded" do
    submit(nil)
    assert_response :created
    assert_nil SkillGraphRevision.last.author_session_id
  end
end
