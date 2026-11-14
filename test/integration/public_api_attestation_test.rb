require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/topic_world"
require_relative "../support/practice_rows"
require_relative "../support/public_api_tokens"

# D-260 and D-327: attest_it, the words that waive the "review page was opened" requirement of approve_topic, are accepted
# from the console and from the API (a teacher token), nowhere else; every other requirement of the gate holds.
class PublicApiAttestationTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include TopicWorld
  include PracticeRows
  include PublicApiTokens

  WORDS = "Ho letto la lezione fuori dall'app.".freeze

  setup do
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    build_topic_world
    @teacher = issue_token("teacher")
  end

  def approve(**body) = api_as(@teacher, "/api/v1/decisions", method: :post, body: { kind: "approve_topic", params: { revision_id: @topic.id } }.merge(body))

  test "without the words the page-opened requirement refuses over the API too" do
    approve(confirm: true)
    assert_response :unprocessable_entity
    assert(json["reasons"].any? { |r| r.include?("was not opened") }, json.inspect)
    assert_equal 0, Decision.where(kind: "approve_topic").count
  end

  test "with the words the topic is approved, with the words and via api in the payload" do
    assert_difference "Decision.where(kind: 'approve_topic').count", 1 do
      approve(attest_it: WORDS, confirm: true)
    end
    assert_response :created, json.inspect
    payload = JSON.parse(Decision.where(kind: "approve_topic").last.payload_json)
    assert_equal [ true, WORDS, [ "topic_review_page_not_opened" ], "api", public_id(@teacher) ], payload.values_at("attested", "attest_it", "waived", "via", "token")
    assert_equal @topic.id, Course::Decisions.approved_topic_revision_id(TopicWorld::TOPIC_KEY)
  end

  test "a dry run with the words shows the attestation and writes nothing" do
    assert_no_difference "Decision.count" do
      approve(attest_it: WORDS)
    end
    assert_response :success
    assert_equal [ true, false ], [ json["payload"]["attested"], json["recorded"] ]
  end

  test "the web form still refuses attest_it: it is accepted only from the console and the API" do
    origin = Struct.new(:env, :cookies, :remote_addr, :request_id, :user_agent, :path) do
      def get_header(name) = name == "HTTP_REMOTE_USER" ? "nik" : "banco-teacher"
    end.new({ Banco::ListenerTag::TAG_KEY => :web, DecisionRecorder::CSRF_KEY => true }, {}, EDGE, SecureRandom.uuid, "t", "/teacher")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    error = assert_raises(DecisionRecorder::Invalid) { DecisionRecorder.call(request: origin, kind: "approve_topic", params: { revision_id: @topic.id, attest_it: WORDS }) }
    assert_includes error.message, "attest_it is accepted only from the console or the API"
  end
end
