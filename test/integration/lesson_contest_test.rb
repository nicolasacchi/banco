require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/lesson_events_world"

# «Per me va bene così» on a check of a lesson/2 (D-396), through the endpoint: POST /topics/:topic/lesson/contest. What it writes (one lesson event with his answer in words, no comment, D-400), what it answers, who may press it, and that the teacher's preview has no button and no route.
class LessonContestTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonEventsWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def post_json(headers, path, body = {})
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def check_url(card, block, tail = "") = "/topics/#{TOPIC}/lesson/checks/#{card}/#{block}#{tail}"
  def contest_url = "/topics/#{TOPIC}/lesson/contest"
  def cid = "e-" + SecureRandom.hex(8)

  setup { build_student_world(approve: true, release: true) }

  def choice = @choice ||= find_block { |_, b| b["type"] == "check" && b["component"] == "choice" }
  def try_block = @try_block ||= find_block { |_, b| b["type"] == "try" }

  def wrong_choice(headers = OFFICIAL, student = @official)
    card, block, check = choice
    reply = post_json(headers, check_url(card, block), { response: shown_id(student, card, block, "a"), try: 1, client_event_id: cid })
    assert_equal "wrong", reply["verdict"]
    [ card, block, check ]
  end

  test "S sends a wrong answer: one lesson event with his answer in words and no comment, the explanation, and the answer again changes nothing" do
    card, block, check = wrong_choice
    first = post_json(OFFICIAL, contest_url, { card: card, block: block })
    assert_response :success
    assert_equal [ "contested", check["explain_it"] ], first.values_at("status", "explain_it")

    assert_equal 0, Comment.count, "no comment in his name"
    option = check["options"].find { |o| o["id"] == "a" }["text_it"]
    event = LessonEvent.where(kind: "check_contested").sole
    assert_equal [ @official.id, card, block, 1, option ], [ event.student_id, event.card, event.block, event.payload["try"], event.payload["words"] ]
    assert_not event.payload.key?("comment_id")

    again = post_json(OFFICIAL, contest_url, { card: card, block: block })
    assert_equal first, again
    assert_equal [ 0, 1 ], [ Comment.count, LessonEvent.where(kind: "check_contested").count ]
    assert_equal %w[wrong], LessonEvent.where(kind: "check_answered").map { |e| e.payload["verdict"] }, "the grading is not touched"
  end

  test "D-400: S's list of comments holds nothing he did not write, and the teacher's Contestazioni lists the contest with his answer" do
    wrong_choice
    card, block, check = choice
    post_json(OFFICIAL, contest_url, { card: card, block: block })
    page(OFFICIAL, "/comments")
    assert_response :success
    assert_select "[data-comment]", 0
    page(TEACHER, "/teacher/grading")
    assert_response :success
    option = check["options"].find { |o| o["id"] == "a" }["text_it"]
    assert_select "#grading-lesson-contests tbody tr", 1
    assert_select "#grading-lesson-contests q[data-student-text]", text: option
  end

  test "a number typed in «Prova tu» is sent as typed, on its exercise" do
    card, block = try_block
    post_json(OFFICIAL, check_url(card, block, "/ex/1"), { response: "98765", try: 1, client_event_id: cid })
    assert_equal "wrong", response.parsed_body["verdict"]
    post_json(OFFICIAL, contest_url, { card: card, block: block, ex: 1 })
    assert_equal "contested", response.parsed_body["status"]
    assert_equal 0, Comment.count
    assert_equal [ 1, "98765" ], LessonEvent.where(kind: "check_contested").sole.payload.values_at("ex", "words")
  end

  test "a blank of an example sends the rest of the example with the contest" do
    card, block, example = find_block { |_, b| b["type"] == "example" }
    index = example["steps"].index { |s| s["blank"] }
    reply = post_json(OFFICIAL, check_url(card, block, "/#{index + 1}"), { response: "99", try: 1, client_event_id: cid })
    assert_not reply.key?("steps")
    sent = post_json(OFFICIAL, contest_url, { card: card, block: block, step: index + 1 })
    assert_equal "contested", sent["status"]
    assert_equal example["steps"][index..].map { |s| s["do_it"] }, sent["steps"].map { |s| s["do_it"] }
    assert_equal 0, Comment.count
    assert_equal index + 1, LessonEvent.where(kind: "check_contested").sole.payload["step"]
  end

  test "nothing is sent before the first try, after a right answer, or for a check that is not there" do
    card, block, check = choice
    post_json(OFFICIAL, contest_url, { card: card, block: block })
    assert_response :conflict
    assert_equal "not_contestable", response.parsed_body["status"]
    post_json(OFFICIAL, check_url(card, block), { response: shown_id(@official, card, block, check["answer"]), try: 1, client_event_id: cid })
    post_json(OFFICIAL, contest_url, { card: card, block: block })
    assert_response :conflict
    post_json(OFFICIAL, contest_url, { card: 99, block: 1 })
    assert_response :not_found
    post_json(OFFICIAL, contest_url, { card: "x", block: block })
    assert_response :not_found
    assert_equal [ 0, 0 ], [ Comment.count, LessonEvent.where(kind: "check_contested").count ]
  end

  test "the trial student's contest is his own event, and no comment" do
    card, block = wrong_choice(TRIAL, @trial)
    post_json(TRIAL, contest_url, { card: card, block: block })
    assert_equal "contested", response.parsed_body["status"]
    assert_equal [ 0, [ @trial.id ] ], [ Comment.count, LessonEvent.where(kind: "check_contested").map(&:student_id) ]
  end

  test "guests, the teacher and unmapped students get 403 and no row; a hidden topic is a 404; a lesson/1 topic has none" do
    card, block = wrong_choice
    [ GUEST, TEACHER, UNMAPPED ].each do |who|
      post_json(who, contest_url, { card: card, block: block })
      assert_response :forbidden
    end
    post_json(OFFICIAL, "/topics/ripasso.math.nope/lesson/contest", { card: card, block: block })
    assert_response :not_found
    assert_equal [ 0, 0 ], [ Comment.count, LessonEvent.where(kind: "check_contested").count ]
  end

  test "the teacher's preview has no route, no address in its page, and S's page has the address" do
    card, block = wrong_choice
    on(:web, "/teacher/preview#{contest_url}", method: :post, headers: TEACHER.merge(JSON_HEADERS), params: { card: card, block: block }.to_json, remote_addr: EDGE)
    assert_response :not_found
    page(TEACHER, "/teacher/preview/topics/#{TOPIC}/lesson")
    assert_response :success
    assert_nil JSON.parse(css_select("[data-lesson2-urls-value]").first["data-lesson2-urls-value"])["contest"]
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    assert_equal contest_url, JSON.parse(css_select("[data-lesson2-urls-value]").first["data-lesson2-urls-value"])["contest"]
    assert_equal [ 0, 0 ], [ Comment.count, LessonEvent.where(kind: "check_contested").count ]
  end

  test "a lesson/1 topic has no contest" do
    pin = StudentCourseWorld.instance_method(:lesson_body).bind_call(self)
    @lesson_revision = LessonRevision.create!(lesson: @lesson, seq: 2, source_md: "---\n", source_sha256: "1" * 64, rules_version: Validation::Rules.version.to_s,
                                              warnings_json: "[]", body_json: JSON.generate(pin))
    @topic_revision = TopicRevision.create!(lesson: @lesson, seq: 2, course_revision: @course, lesson_revision: @lesson_revision, body_json: @topic_revision.body_json)
    approve_topic!(@topic_revision)
    post_json(OFFICIAL, contest_url, { card: 1, block: 3 })
    assert_response :not_found
  end
end
