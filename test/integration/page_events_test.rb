require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/lesson_events_world"

# The events of a free page in the lesson's own ledger (D-289, SPEC B4, B5): page_opened, page_event, page_failed. Append-only, never
# an outcome, never a skill state; refused when malformed.
class PageEventsTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonEventsWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  setup { build_student_world(approve: true, release: true) }

  def post_events(events)
    on(:web, "/today", headers: OFFICIAL, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, "/topics/#{TOPIC}/lesson/events", method: :post, headers: OFFICIAL.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: { events: events }.to_json, remote_addr: EDGE)
  end

  def cid = "e-" + SecureRandom.hex(8)

  test "page_opened is stored once per card per ten minutes with its block" do
    post_events([ { kind: "page_opened", card: 2, block: 1, client_event_id: cid } ])
    assert_response :success
    post_events([ { kind: "page_opened", card: 2, block: 1, client_event_id: cid } ])
    assert_response :success
    events = LessonEvent.where(kind: "page_opened")
    assert_equal 1, events.count
    assert_equal({ "block" => 1 }, events.first.payload)
  end

  test "page_event keeps the kind the page named and its small data; every one is kept" do
    post_events([ { kind: "page_event", card: 2, block: 1, page_event: "interacted", data: { slope: 1.5 }, client_event_id: cid },
                  { kind: "page_event", card: 2, block: 1, page_event: "done", data: {}, client_event_id: cid } ])
    assert_response :success
    assert_equal [ { "block" => 1, "kind" => "interacted", "data" => { "slope" => 1.5 } }, { "block" => 1, "kind" => "done", "data" => {} } ], LessonEvent.where(kind: "page_event").order(:id).map(&:payload)
  end

  test "page_failed records the limit that tripped" do
    post_events([ { kind: "page_failed", card: 2, block: 1, limit: "ready", client_event_id: cid } ])
    assert_response :success
    assert_equal({ "block" => 1, "limit" => "ready" }, LessonEvent.find_by(kind: "page_failed").payload)
  end

  test "a malformed page event is refused as a whole and stores nothing" do
    bad = [
      { kind: "page_event", card: 2, block: 1, page_event: "won", client_event_id: cid },
      { kind: "page_event", card: 2, block: 1, page_event: "done", data: { text: "x" * 1100 }, client_event_id: cid },
      { kind: "page_event", card: 2, page_event: "done", client_event_id: cid },
      { kind: "page_event", card: 2, block: 99, page_event: "done", client_event_id: cid },
      { kind: "page_failed", card: 2, block: 1, limit: "whenever", client_event_id: cid },
      { kind: "page_opened", card: 999, block: 1, client_event_id: cid },
      { kind: "page_solved", card: 2, block: 1, client_event_id: cid }
    ]
    bad.each do |event|
      post_events([ event ])
      assert_response :unprocessable_entity, event.inspect
    end
    assert_equal 0, LessonEvent.where(kind: %w[page_opened page_event page_failed]).count
  end

  test "no read model of the skill states names these kinds" do
    sources = Dir[Rails.root.join("app/models/{practice,diagnosis,course}/**/*.rb").to_s, Rails.root.join("lib/{practice,diagnosis}/**/*.rb").to_s]
    assert_empty sources.select { |f| File.read(f).match?(/page_opened|page_event|page_failed/) }
  end
end
