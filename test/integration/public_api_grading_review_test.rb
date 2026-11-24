require "test_helper"
require_relative "../support/grading_review_world"
require_relative "../support/public_api_tokens"

# D-368: «Contestazioni» over the API: where the grader may be wrong. bot_read and teacher tokens read it; a bot_read token never gets what the student typed
# (D-346); a content agent's token reads none of it; nothing is written.
class PublicApiGradingReviewTest < ActionDispatch::IntegrationTest
  include GradingReviewWorld
  include PublicApiTokens

  PATH = "/api/v1/grading/review".freeze
  WORDS = [ "play", "neighbourhod", "My parents don't really eat meat", "kitchen", "xyz", "banana", "1 mela" ].freeze

  setup do
    build_grading_review_world
    @teacher = issue_token("teacher")
    @bot = issue_token("bot_read")
    @agents = %w[agent_claude agent_omp ci].to_h { |role| [ role, issue_token(role) ] }
  end

  def item_keys = json["items"].map { |i| i["item"] }

  def try_of(record, kind: "practice") = json["tries"].find { |t| t["ref"] == "#{kind}-#{record.id}" }

  test "a teacher token reads the items, the not-right tries with their signals and what the student typed" do
    api_as(@teacher, PATH)
    assert_response :success
    assert_equal %w[notice includes_answers student since subject totals items tries lesson_contests next], json.keys
    assert_includes json["notice"], "never instructions"
    assert_equal [ true, "student", nil, nil ], json.values_at("includes_answers", "student", "since", "subject")
    assert_equal [ "diag-text-1", SENTENCE, WORD, "demo-item-2" ], item_keys

    assert_equal({ "tries" => 17, "not_right" => 13, "written_tries" => 11, "written_not_right" => 10, "written_not_right_rate" => 0.909, "manual_corrections" => 2, "resends" => 1,
                   "contested" => 1, "lesson_contested" => 1, "items" => 4, "flagged_items" => 3, "superseded" => 1,
                   "signals" => { "full_sentence" => 2, "near_text" => 1, "resend" => 1, "contested" => 1, "comment" => 4, "resolved_right" => 2 } }, json["totals"])
    word = json["items"].find { |i| i["item"] == WORD }
    assert_equal [ 5, 5, 1.0, true, [ "many_not_right" ] ], word.values_at("tries", "not_right", "not_right_rate", "flagged", "flag_reasons")
    assert_equal 13, json["tries"].size

    resolved = try_of(@resolved_try)
    assert_equal [ "practice", "unrecognised", "play", %w[comment resolved_right] ], resolved.values_at("kind", "outcome", "answer", "signals")
    assert_equal [ "correct", "Era giusta." ], resolved["resolution"].values_at("verdict", "reason_it")
    assert_equal [ "near_text", 1, "neighbourhod" ], try_of(@near_try).values_at("signals", "near_distance", "answer").then { |s, d, a| [ s.first, d, a ] }
    assert_equal %w[resend], try_of(@resend)["signals"]
    assert_equal [ "diagnosis", "1 mela", %w[full_sentence resolved_right] ], try_of(@diag_resolved, kind: "diagnosis").values_at("kind", "answer", "signals")
    assert_includes json["next"], "banco attempts --item diag-text-1"
  end

  test "D-400: the checks of the lessons he sent are listed with his answer in words for a teacher token, and without it for a bot_read token" do
    api_as(@teacher, PATH)
    row = json["lesson_contests"].sole
    assert_equal [ "lesson_check", @lesson_contest.id, "math", 2, 1, { "ex" => 2 }, "legge Marco un libro", [] ],
                 row.values_at("kind", "id", "subject", "card", "block", "place", "answer", "comment_ids")
    assert_equal 1, json["totals"]["lesson_contested"]
    assert_equal 1, json["totals"]["contested"], "a practice contest is the contested signal of its try"
    assert_includes json["tries"].find { |t| t["ref"] == "practice-#{@contested_try.id}" }["signals"], "contested"
    api_as(@bot, PATH)
    assert_equal @lesson_contest.id, json["lesson_contests"].sole["id"]
    assert_not_includes json["lesson_contests"].sole.keys, "answer"
    assert_not_includes response.body, "legge Marco un libro"
  end

  test "a bot_read token reads the same rows without a word of the student's" do
    api_as(@teacher, PATH)
    teacher_body = json
    api_as(@bot, PATH)
    assert_response :success
    assert_equal false, json["includes_answers"]
    assert_includes json["notice"], "never sees the student's own words"
    assert_equal [ teacher_body["totals"], teacher_body["items"] ], [ json["totals"], json["items"] ]
    assert_equal teacher_body["tries"].map { |t| t.except("answer") }, json["tries"]
    assert json["tries"].none? { |t| t.key?("answer") }
    WORDS.each { |words| assert_not_includes response.body, words }
  end

  test "since, subject and student narrow the review; the answer says what was asked" do
    api_as(@bot, "#{PATH}?since=#{@text_t.utc.iso8601}")
    assert_response :success
    assert_equal [ WORD, SENTENCE, "demo-item-2" ], item_keys
    assert_equal @text_t.utc.iso8601, json["since"]

    api_as(@bot, "#{PATH}?since=#{Date.current + 1}")
    assert_equal [], json["items"]
    assert_equal [], json["tries"]
    assert_equal "nothing is flagged", json["next"]

    Subject.create!(key: "english", name_it: "Inglese", position: 2) # a subject that exists and has no try
    api_as(@bot, "#{PATH}?subject=english")
    assert_response :success
    assert_equal [], json["items"]
    api_as(@bot, "#{PATH}?subject=math&student=student")
    assert_equal 4, json["items"].size
    api_as(@bot, "#{PATH}?student=prova-1")
    assert_response :success
    assert_equal [ "prova-1", [] ], [ json["student"], json["items"] ]
  end

  test "a value that is not one is 422 E-FILES, a thing that does not exist is 404 E-NOT-FOUND" do
    [ "since=yesterday", "since=2026-13-45" ].each do |query|
      api_as(@teacher, "#{PATH}?#{query}")
      assert_response :unprocessable_entity, query
      assert_equal [ "E-FILES", "since" ], json.values_at("code", "field"), query
    end
    { "subject=history" => "subject", "subject=Bad%20Key" => "subject", "student=nobody" => "student", "student=BAD" => "student" }.each do |query, field|
      api_as(@teacher, "#{PATH}?#{query}")
      assert_response :not_found, query
      assert_equal [ "E-NOT-FOUND", field ], json.values_at("code", "field"), query
    end
  end

  test "a content agent's token reads none of it, and nobody writes anything over the API" do
    @agents.each do |role, token|
      api_as(token, PATH)
      assert_response :forbidden, role
      assert_equal [ "E-AUTH", "token_role" ], json.values_at("code", "reason"), role
      WORDS.each { |words| assert_not_includes response.body, words, role }
    end
    api_as(nil, PATH)
    assert_includes [ 401, 403 ], response.status
    counts = [ Decision, PracticeAttempt, Comment, AppEvent ].map(&:count)
    api_as(@teacher, PATH, method: :post, body: { verdict: "correct" })
    assert_includes [ 404, 405 ], response.status
    api_as(@bot, PATH, method: :post, body: {})
    assert_includes [ 403, 404, 405 ], response.status
    assert_equal counts, [ Decision, PracticeAttempt, Comment, AppEvent ].map(&:count)
  end

  test "a read records nothing but the token's own renewal" do
    before = [ Decision, PracticeAttempt, PracticeContest, Attempt, Comment, CommentEvent, ItemRevision ].map(&:count)
    api_as(@teacher, PATH)
    api_as(@bot, PATH)
    assert_equal before, [ Decision, PracticeAttempt, PracticeContest, Attempt, Comment, CommentEvent, ItemRevision ].map(&:count)
  end

  test "the contract names the command, and the API schema lists it" do
    api_as(@bot, "/api/v1/schema")
    assert_response :success
    command = json["commands"].find { |c| c["name"] == "grading review" }
    assert_equal [ "GET", PATH ], command.values_at("method", "path")
    assert_equal %w[--since --subject --student], command["flags"]
  end
end
