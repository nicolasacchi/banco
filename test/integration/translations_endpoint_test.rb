require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# POST /translations (D-402): the student opened the Italian translation of a card, a block, an exercise or a list page. One app event
# `translation_opened`, informational (no counter, not an aid); the preview answers and writes nothing; the teacher and a guest get 403.
class TranslationsEndpointTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  TOPIC_KEY = "lezione.english.can-and-should".freeze

  setup { build_student_world }

  def events = AppEvent.where(kind: "translation_opened")

  # A post as the page's script does it: the page's CSRF token, a JSON body.
  def post_translation(headers, body, path: "/translations", raw: nil)
    on(:web, "/today", headers: headers, remote_addr: EDGE) unless headers == GUEST
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: raw || body.to_json, remote_addr: EDGE)
  end

  test "an opened card is one event, with the context the browser sent, and the answer is 204 with no body" do
    post_translation(OFFICIAL, { surface: "lesson", scope: "card", topic: TOPIC_KEY, card: 2 })
    assert_response :no_content
    assert_empty response.body
    event = events.sole
    assert_equal Student.find_by!(key: "student").id, event.student_id
    assert_equal({ "surface" => "lesson", "scope" => "card", "topic" => TOPIC_KEY, "card" => 2 }, JSON.parse(event.payload_json))
  end

  test "every scope and surface the browser has is accepted: block, item with a serve, and a page" do
    [ { surface: "lesson", scope: "block", topic: TOPIC_KEY, card: 1, block: 3 }, { surface: "practice", scope: "item", topic: TOPIC_KEY, serve_id: 41 },
      { surface: "topics", scope: "page" } ].each do |body|
      post_translation(OFFICIAL, body)
      assert_response :no_content, body.inspect
    end
    assert_equal %w[block item page], events.order(:id).map { |e| JSON.parse(e.payload_json)["scope"] }
    assert_equal 41, JSON.parse(events.where("payload_json LIKE '%serve_id%'").sole.payload_json)["serve_id"]
  end

  test "a trial student writes too, to his own row" do
    post_translation(TRIAL, { surface: "practice", scope: "item", serve_id: 7 })
    assert_response :no_content
    assert_equal Student.find_by!(key: "prova-1").id, events.sole.student_id
  end

  test "the body is validated: a bad surface, scope, topic or number is 422 and no row" do
    [ { surface: "chat", scope: "card" }, { surface: "lesson", scope: "paragraph" }, { surface: "lesson" }, { scope: "card" },
      { surface: "lesson", scope: "card", topic: "not a topic key" }, { surface: "lesson", scope: "card", topic: [ TOPIC_KEY ] },
      { surface: "lesson", scope: "card", card: 0 }, { surface: "lesson", scope: "card", card: "2" }, { surface: "lesson", scope: "card", card: 3_000_000_000 },
      { surface: "practice", scope: "item", serve_id: -1 }, { surface: "lesson", scope: "card", note: "free text" } ].each do |body|
      post_translation(OFFICIAL, body)
      assert_response :unprocessable_entity, body.inspect
    end
    post_translation(OFFICIAL, nil, raw: "[1,2]")
    assert_response :unprocessable_entity
    assert_equal 0, events.count
  end

  test "the preview answers 204 and writes nothing" do
    post_translation(TEACHER, { surface: "lesson", scope: "card", topic: TOPIC_KEY, card: 1 }, path: "/teacher/preview/translations")
    assert_response :no_content
    assert_equal 0, events.count
    post_translation(TEACHER, { surface: "chat", scope: "card" }, path: "/teacher/preview/translations")
    assert_response :unprocessable_entity
  end

  test "the teacher and a guest get 403 and no row" do
    [ TEACHER, GUEST ].each do |headers|
      post_translation(headers, { surface: "lesson", scope: "card" })
      assert_response :forbidden
    end
    assert_equal 0, events.count
  end

  test "opening the translation is not an aid: no practice or lesson row is written" do
    before = [ PracticeEvent.count, PracticeAttempt.count, LessonEvent.count ]
    post_translation(OFFICIAL, { surface: "practice", scope: "item", serve_id: 1 })
    assert_equal before, [ PracticeEvent.count, PracticeAttempt.count, LessonEvent.count ]
  end
end
