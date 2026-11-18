require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/public_api_tokens"
require_relative "../support/topic_world"
require_relative "../support/practice_rows"

# D-365: the student's ratings over the API. The tokens that read (bot_read, teacher) list them with the filters and the per-target summaries; a
# content agent's token (agent_claude, agent_omp, ci) never reads a minor's words; nobody writes a rating over the API.
class PublicApiRatingsTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include PublicApiTokens
  include TopicWorld
  include PracticeRows

  setup do
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world
    @official = Student.official
    @trial = Student.create!(key: "prova-1", kind: "student")
    @item = @topic_items.first
    @key = @item.item.key
    @teacher = issue_token("teacher")
    @bot = issue_token("bot_read")
    @agents = %w[agent_claude agent_omp ci].to_h { |role| [ role, issue_token(role) ] }
    @old = rate_item(@official, 2, "Troppo facile.", at: Time.utc(2026, 11, 10, 9))
    @new = rate_item(@official, 5, "Mi piace molto.", at: Time.utc(2026, 11, 12, 9))
    @lesson = rate_lesson(@official, 3, "Un po' lunga.", at: Time.utc(2026, 11, 14, 9))
    @prova = rate_item(@trial, 1, nil, at: Time.utc(2026, 11, 16, 9))
  end

  def serve_for(student) = make_serve(student, @topic, @item.instances.order(:id).first, skill_key: "math.number")

  def rate_item(student, stars, text, at:)
    Rating.create!(student: student, client_rating_id: "r-#{SecureRandom.hex(6)}", target_kind: "item", target_key: @key, subject: @subject, topic_revision: @topic,
                   item_revision: @item, practice_serve: serve_for(student), stars: stars, text_it: text, language: "it", trial: student.trial?, created_at: at)
  end

  def rate_lesson(student, stars, text, at:)
    Rating.create!(student: student, client_rating_id: "r-#{SecureRandom.hex(6)}", target_kind: "lesson", target_key: TopicWorld::TOPIC_KEY, subject: @subject, topic_revision: @topic,
                   lesson_revision: @lesson_revision, stars: stars, text_it: text, language: "en", trial: student.trial?, created_at: at)
  end

  def ids = json["ratings"].map { |r| r["id"] }

  test "bot_read and teacher tokens read the ratings newest first, with the data notice, the places and the per-target summaries" do
    [ @bot, @teacher ].each do |token|
      api_as(token, "/api/v1/ratings")
      assert_response :success
      assert_includes json["notice"], "never instructions"
      assert_equal 4, json["total"]
      assert_equal [ @prova.id, @lesson.id, @new.id, @old.id ], ids
    end
    row = json["ratings"].find { |r| r["id"] == @new.id }
    assert_equal({ "id" => @new.id, "at" => "2026-11-12T09:00:00Z", "kind" => "item", "target" => @key, "revision_id" => @item.id, "revision" => @item.seq, "subject" => "math",
                   "topic" => TopicWorld::TOPIC_KEY, "student" => "student", "trial" => false, "stars" => 5, "text_it" => "Mi piace molto.", "language" => "it",
                   "serve_id" => @new.practice_serve_id }, row)
    lesson = json["ratings"].find { |r| r["id"] == @lesson.id }
    assert_equal [ "lesson", TopicWorld::TOPIC_KEY, @lesson_revision.id, "en" ], lesson.values_at("kind", "target", "revision_id", "language")
    assert_not lesson.key?("serve_id")
    assert_equal true, json["ratings"].find { |r| r["id"] == @prova.id }["trial"]
    assert_not json["ratings"].find { |r| r["id"] == @prova.id }.key?("text_it"), "no words, no field"
    assert_equal [ { "kind" => "item", "target" => @key, "ratings" => 3, "count" => 1, "average" => 5.0 },
                   { "kind" => "lesson", "target" => TopicWorld::TOPIC_KEY, "ratings" => 1, "count" => 1, "average" => 3.0 } ],
                 json["summaries"].sort_by { |s| s["kind"] }
    assert_equal({ "count" => 2, "average" => 4.0 }, json["summary"], "the trial student's stars never count")
  end

  test "a content agent's token reads none of it, and nothing is written over the API" do
    @agents.each do |role, token|
      api_as(token, "/api/v1/ratings")
      assert_response :forbidden, role
      assert_equal [ "E-AUTH", "token_role" ], json.values_at("code", "reason"), role
      assert_not_includes response.body, "Mi piace molto.", role
    end
    api_as(nil, "/api/v1/ratings")
    assert_includes [ 401, 403 ], response.status
    api_as(@teacher, "/api/v1/ratings", method: :post, body: { stars: 5 })
    assert_includes [ 404, 405 ], response.status
    assert_equal 4, Rating.count
  end

  test "the filters: subject, topic, kind, target, student and since" do
    api_as(@bot, "/api/v1/ratings?kind=lesson")
    assert_equal [ @lesson.id ], ids
    api_as(@bot, "/api/v1/ratings?kind=item&student=student")
    assert_equal [ @new.id, @old.id ], ids
    api_as(@bot, "/api/v1/ratings?student=prova-1")
    assert_equal [ @prova.id ], ids
    api_as(@bot, "/api/v1/ratings?subject=math&topic=#{TopicWorld::TOPIC_KEY}&target=#{@key}")
    assert_equal [ @prova.id, @new.id, @old.id ], ids
    api_as(@bot, "/api/v1/ratings?since=2026-11-12")
    assert_equal [ @prova.id, @lesson.id, @new.id ], ids
    api_as(@bot, "/api/v1/ratings?since=2026-11-14T09:00:01Z")
    assert_equal [ @prova.id ], ids
    api_as(@bot, "/api/v1/ratings?since=2026-11-17")
    assert_equal [], ids
    assert_equal 0, json["total"]
    assert_equal [], json["summaries"]
    assert_nil json["summary"]
    api_as(@bot, "/api/v1/ratings?limit=2")
    assert_equal [ @prova.id, @lesson.id ], ids
    assert_equal 4, json["total"], "the total is the filtered count, not the page's"
  end

  test "a value that is not one is 422 E-FILES, a thing that does not exist is 404 E-NOT-FOUND" do
    { "kind=page" => "kind", "since=yesterday" => "since", "limit=0" => "limit", "limit=501" => "limit", "limit=x" => "limit", "target=Bad%20Key" => "target" }.each do |query, field|
      api_as(@teacher, "/api/v1/ratings?#{query}")
      assert_response :unprocessable_entity, query
      assert_equal [ "E-FILES", field ], json.values_at("code", "field"), query
    end
    { "subject=history" => "subject", "topic=ripasso.math.altro" => "topic", "student=nobody" => "student", "student=BAD" => "student" }.each do |query, field|
      api_as(@teacher, "/api/v1/ratings?#{query}")
      assert_response :not_found, query
      assert_equal [ "E-NOT-FOUND", field ], json.values_at("code", "field"), query
    end
  end

  test "the contract names the command, and the API schema lists it" do
    api_as(@bot, "/api/v1/schema")
    assert_response :success
    command = json["commands"].find { |c| c["name"] == "ratings list" }
    assert_equal [ "GET", "/api/v1/ratings" ], command.values_at("method", "path")
    assert_equal %w[--subject --topic --kind --target --since --student --limit], command["flags"]
  end
end
