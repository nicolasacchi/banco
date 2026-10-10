require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/lesson_events_world"

# R3 (A10, A11, A14): what the teacher sees of the lesson ledger (the progress line, the questions by card), the
# box's three endpoints with their guards, and Oggi's "Riprendi" by card.
class LessonTeacherTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonEventsWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  DEVICE = "banco_device".freeze

  setup { build_student_world(approve: true, release: true) }

  def page(headers, path, **options) = on(:web, path, headers: headers, remote_addr: EDGE, **options)

  def post_json(headers, path, body = {}, cookie: nil)
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    extra = cookie ? { "Cookie" => cookie } : {}
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s).merge(extra), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def cid = "e-" + SecureRandom.hex(8)
  def full_url(id = @lesson_revision.id) = "/teacher/lesson-revisions/#{id}/full.json"

  # ---- full.json ---------------------------------------------------------------------------------------

  test "full.json: the teacher and a guest read the stored body, with the answers, and nothing is cached" do
    page(TEACHER, full_url)
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    body = response.parsed_body
    assert_equal "banco.lesson/2", body["schema"]
    card, block, check = find_block { |_, b| b["type"] == "check" && b["component"] == "choice" }
    assert_equal check["answer"], body["cards"].find { |c| c["n"] == card }["blocks"].find { |b| b["n"] == block }["answer"]
    page(GUEST, full_url)
    assert_response :success
  end

  test "full.json: students, trial students and the student's computer get 403 and no body; the API listener 404" do
    [ OFFICIAL, TRIAL, UNMAPPED ].each do |who|
      page(who, full_url)
      assert_response :forbidden, who.to_s
      assert_no_match(/answer|banco\.lesson/, response.body)
    end
    on(:web, full_url, headers: TEACHER.merge("Cookie" => "#{DEVICE}=student"), remote_addr: EDGE)
    assert_response :forbidden
    assert_empty response.body
    on(:web, full_url, headers: {}, remote_addr: EDGE)
    assert_response :forbidden
    on(:api, full_url, headers: TEACHER, remote_addr: "127.0.0.1")
    assert_response :not_found
    page(TEACHER, full_url(@lesson_revision.id + 99))
    assert_response :not_found
  end

  test "full.json of a lesson/1 revision is its stored body; a check of it is a 404" do
    old = LessonRevision.create!(lesson: @lesson, seq: 2, source_md: "---\n", source_sha256: "2" * 64, rules_version: Validation::Rules.version.to_s, warnings_json: "[]",
                                 body_json: JSON.generate(StudentCourseWorld.instance_method(:lesson_body).bind_call(self)))
    page(TEACHER, full_url(old.id))
    assert_response :success
    assert_equal "banco.lesson/1", response.parsed_body["schema"]
    post_json(TEACHER, "/teacher/lesson-revisions/#{old.id}/checks/1/1", { response: "a" })
    assert_response :not_found
  end

  # ---- the box's checks and solutions ------------------------------------------------------------------

  test "the box grades with the seed 'preview', counts the tries as the browser says, and records nothing" do
    card, block, check = find_block { |_, b| b["type"] == "check" && b["component"] == "choice" }
    map = Lessons::Checks.id_map(check, Lessons::StudentBody.seed_for("preview", @lesson_revision.id, card, block))
    url = "/teacher/lesson-revisions/#{@lesson_revision.id}/checks/#{card}/#{block}"
    wrong = post_json(TEACHER, url, { response: map.key("a"), try: 2 })
    assert_response :success
    assert_equal [ "wrong", 2, check["explain_it"] ], wrong.values_at("verdict", "try", "explain_it")
    right = post_json(TEACHER, url, { response: map.key(check["answer"]), try: 1 })
    assert_equal "right", right["verdict"]
    assert_equal 0, LessonEvent.count
    post_json(GUEST, url, { response: "x" })
    assert_response :forbidden, "a guest reads; every write of the area is refused to it"
    post_json(OFFICIAL, url, { response: "x" })
    assert_response :forbidden
    post_json(TEACHER, url, { response: "x" }, cookie: "#{DEVICE}=student")
    assert_response :forbidden
    assert_equal 0, LessonEvent.count
  end

  test "the box asks for a solution and nothing is recorded" do
    before = PracticeEvent.count
    reply = post_json(TEACHER, "/teacher/lesson-revisions/#{@lesson_revision.id}/exercises/1/solution")
    assert_response :success
    assert reply["steps"].present? || reply["solution_it"].present?
    post_json(TEACHER, "/teacher/lesson-revisions/#{@lesson_revision.id}/exercises/99/solution")
    assert_response :not_found
    post_json(TRIAL, "/teacher/lesson-revisions/#{@lesson_revision.id}/exercises/1/solution")
    assert_response :forbidden
    assert_equal before, PracticeEvent.count
  end

  # ---- the questions by card ---------------------------------------------------------------------------

  def ask(who, extra)
    post_json(who, "/questions", { client_question_id: "q-" + SecureRandom.hex(8), topic: TOPIC, lesson_revision_id: @lesson_revision.id, text_it: "Non capisco." }.merge(extra))
  end

  test "a question from a card stores the card and the card's role as its section" do
    cards = stored_body["cards"]
    idea = cards.find { |c| c["role"] == "idea" && c["level"] == "core" }
    extra = cards.find { |c| c["level"] == "extra" }
    ask(OFFICIAL, { card: idea["n"], section: "why" })
    assert_response :success
    ask(OFFICIAL, { card: extra["n"] })
    assert_response :success
    rows = StudentQuestion.order(:id).to_a
    assert_equal [ idea["n"], "idea" ], [ rows[0].card, rows[0].section ], "the section is the card's role, not what the browser said"
    assert_equal [ extra["n"], extra["role"] ], [ rows[1].card, rows[1].section ]
    ask(OFFICIAL, { card: 999 })
    assert_response :unprocessable_entity
    ask(OFFICIAL, { card: "x" })
    assert_response :unprocessable_entity
    ask(OFFICIAL, { card: 0 })
    assert_response :unprocessable_entity
    post_json(OFFICIAL, "/questions", { client_question_id: "q-" + SecureRandom.hex(8), topic: TOPIC, card: 1 })
    assert_response :unprocessable_entity, "a card needs the lesson revision it belongs to"
    assert_equal 2, StudentQuestion.count
  end

  test "a card on a lesson/1 is refused" do
    pin_old_lesson
    ask(OFFICIAL, { card: 1 })
    assert_response :unprocessable_entity
  end

  def pin_old_lesson
    @lesson_revision = LessonRevision.create!(lesson: @lesson, seq: 2, source_md: "---\n", source_sha256: "3" * 64, rules_version: Validation::Rules.version.to_s, warnings_json: "[]",
                                              body_json: JSON.generate(StudentCourseWorld.instance_method(:lesson_body).bind_call(self)))
    @topic_revision = TopicRevision.create!(lesson: @lesson, seq: 2, course_revision: @course, lesson_revision: @lesson_revision, body_json: @topic_revision.body_json)
    approve_topic!(@topic_revision)
  end

  test "the teacher's practice page tells the cards apart and shows the lesson line" do
    cards = stored_body["cards"]
    ideas = cards.select { |c| c["role"] == "idea" && c["level"] == "core" }.first(2)
    extra = cards.find { |c| c["level"] == "extra" }
    ideas.each { |c| ask(OFFICIAL, { card: c["n"], text_it: "Domanda sulla scheda #{c['n']}" }) }
    ask(OFFICIAL, { card: extra["n"], text_it: "Domanda extra" })
    page(TEACHER, "/teacher/subjects/math/practice")
    assert_response :success
    labels = css_select("[data-question] [data-card]").map(&:text)
    assert_equal [ "Approfondimento 1 «#{extra['title_it']}»", "Scheda #{ideas[1]['n']} «#{ideas[1]['title_it']}»", "Scheda #{ideas[0]['n']} «#{ideas[0]['title_it']}»" ], labels
    assert_select "[data-lesson-line]", /Lezione: 0 schede su #{cards.count { |c| c['level'] == 'core' }} viste \(approfondimenti 0 su 2\), mai aperta\./
    ids = [ 2, 3, extra["n"] ]
    post_json(OFFICIAL, "/topics/#{TOPIC}/lesson/events", { events: ids.map { |n| { kind: "card_seen", card: n, client_event_id: cid } } })
    card, block, check = find_block { |_, b| b["type"] == "check" && b["component"] == "choice" }
    seed = Lessons::StudentBody.seed_for("student", @lesson_revision.id, card, block)
    map = Lessons::Checks.id_map(check, seed)
    post_json(OFFICIAL, "/topics/#{TOPIC}/lesson/checks/#{card}/#{block}", { response: map.key("a"), client_event_id: cid })
    post_json(OFFICIAL, "/topics/#{TOPIC}/lesson/checks/#{card}/#{block}", { response: map.key(check["answer"]), client_event_id: cid })
    page(TEACHER, "/teacher/subjects/math/practice")
    assert_select "[data-lesson-line]", /Lezione: 2 schede su \d+ viste \(approfondimenti 1 su 2\), controlli giusti al primo tentativo 0 su 1, ultima apertura \d\d\/\d\d\/\d{4} \d\d:\d\d\./
    page(GUEST, "/teacher/subjects/math/practice")
    assert_response :success
  end

  test "a lesson/1 topic has no lesson line" do
    pin_old_lesson
    page(TEACHER, "/teacher/subjects/math/practice")
    assert_select "[data-lesson-line]", 0
  end

  # ---- Oggi and the lesson page ------------------------------------------------------------------------

  test "Oggi: Riprendi opens the last card seen of the lesson; after practising it opens the topic again" do
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    page(OFFICIAL, "/today")
    assert_select "#resume[href='/topics/#{TOPIC}']"
    post_json(OFFICIAL, "/topics/#{TOPIC}/lesson/events", { events: [ { kind: "card_seen", card: 2, client_event_id: cid }, { kind: "card_seen", card: 5, client_event_id: cid } ] })
    page(OFFICIAL, "/today")
    assert_select "#resume[href='/topics/#{TOPIC}/lesson#scheda-5']"
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    assert_select "#lesson-root[data-lesson2-resume-value='5'][data-lesson2-seen-value='[2,5]']"
    make_serve(@official, @topic_revision, @revisions.first.instances.first, skill_key: SKILL)
    page(OFFICIAL, "/today")
    assert_select "#resume[href='/topics/#{TOPIC}']"
  end

  test "a trial student's cards do not move the official student's resume" do
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    post_json(TRIAL, "/topics/#{TOPIC}/lesson/events", { events: [ { kind: "card_seen", card: 4, client_event_id: cid } ] })
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    assert_select "#lesson-root[data-lesson2-resume-value='0'][data-lesson2-seen-value='[]']"
  end
end
