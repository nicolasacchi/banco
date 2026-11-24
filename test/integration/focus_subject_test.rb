require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/public_api_tokens"
require_relative "../support/student_course_world"

# D-399: the teacher recommends the subject the student starts from (the decision set_focus_subject, the latest one wins). Oggi puts that
# subject's suggestion first with one plain line; with no focus nothing changes. The recorder's guards, the teacher's button, the console
# and the API door, and the student's, the preview's and a trial student's Oggi. Invented content only: math (the course world) and italian.
class FocusSubjectTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include PublicApiTokens
  include StudentCourseWorld

  LINE = "Il docente ti consiglia di cominciare da qui.".freeze
  ITALIAN_TOPIC = "lezione.italian.lettura".freeze

  setup do
    build_student_world
    add_italian_course!
  end

  # ---- helpers -------------------------------------------------------------------------------------

  def add_italian_course!(release: true)
    @italian = Subject.create!(key: "italian", name_it: "Italiano", position: 2)
    SkillGraphRevision.create!(subject: @italian, seq: 1, body_json: JSON.generate(ValidationFixtures::GRAPH.merge("subject" => "italian", "skills" => [])))
    skill = "italian.lettura"
    @italian_course = build_course_map(subject: @italian, skills: [], topics: [ { key: ITALIAN_TOPIC, kind: "lezione", title_it: "La lettura", skills: [ skill ], minutes: 20, term: 1, after: [] } ])
    lesson = Lesson.create!(subject: @italian, key: ITALIAN_TOPIC, kind: "lezione")
    body = lesson_body.merge(key: ITALIAN_TOPIC, kind: "lezione", subject: "italian", title_it: "La lettura", skills: [ skill ])
    lesson_revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: "---\n", source_sha256: "4" * 64, rules_version: Validation::Rules.version.to_s,
                                             warnings_json: "[]", body_json: JSON.generate(body))
    items = Array.new(2) { |i| make_practice_item("lettura-#{i + 1}", skill, subject: @italian) }
    topic = TopicRevision.create!(lesson: lesson, seq: 1, course_revision: @italian_course, lesson_revision: lesson_revision,
                                  body_json: JSON.generate(schema: "banco.topic/1", key: ITALIAN_TOPIC, practice: [ { skill: skill, items: items.map { |r| { item: r.item.key, revision: r.id } } } ]))
    ledger("approve_topic", { topic_revision_id: topic.id, topic: ITALIAN_TOPIC, seq: 1, course_revision_id: @italian_course.id, lesson_revision_id: lesson_revision.id })
    ledger("release_course", { subject: "italian", open: true, course_revision_id: @italian_course.id }, student: @official) if release
  end

  def ledger(kind, payload, student: nil)
    Decision.create!(kind: kind, subject: @italian, student: student, payload_json: JSON.generate(payload), request_id: SecureRandom.hex(4), teacher_login: "nik", remote_addr: "127.0.0.1")
  end

  def console = DecisionRecorder::Console.new(login: "nik", os_user: "tester")

  def record(subject, origin: console) = DecisionRecorder.call(request: origin, kind: "set_focus_subject", params: { subject: subject })

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def suggested = css_select("#suggestions li.topic").map { |li| li["data-topic"] }

  # ---- the recorder --------------------------------------------------------------------------------

  test "it is a kind of the recorder and of the API, with no reason, and records subject and official student" do
    assert_includes DecisionRecorder::KINDS, "set_focus_subject"
    assert_includes DecisionRecorder::Api::KINDS, "set_focus_subject"
    assert_nil Course::Focus.subject_key

    decision = record("italian")
    assert_equal [ "set_focus_subject", @italian, @official ], [ decision.kind, decision.subject, decision.student ]
    assert_equal({ "subject" => "italian", "via" => "console" }, JSON.parse(decision.payload_json))
    assert_equal "nik", decision.teacher_login
    assert_equal "italian", Course::Focus.subject_key
    assert_equal @italian, Course::Focus.subject
  end

  test "the latest decision wins, a decision clears it, and the rows stay: the state is derived" do
    record("italian")
    record("math")
    assert_equal "math", Course::Focus.subject_key
    cleared = record("")
    assert_nil cleared.subject
    assert_equal @official, cleared.student
    assert_equal({ "subject" => "", "via" => "console" }, JSON.parse(cleared.payload_json))
    assert_nil Course::Focus.subject_key
    assert_nil Course::Focus.subject
    assert_equal 3, Decision.where(kind: "set_focus_subject").count
    record("italian")
    assert_equal "italian", Course::Focus.subject_key
  end

  test "the guards: an unknown subject, a course not open, the same subject again, nothing to clear, no subject given" do
    assert_raises(DecisionRecorder::Missing) { record("history") }
    other = Subject.create!(key: "history", name_it: "Storia", position: 3)
    error = assert_raises(DecisionRecorder::Invalid) { record(other.key) }
    assert_equal [ "the course of history is not open to the student" ], error.reasons
    ledger("release_course", { subject: "italian", open: false }, student: @official)
    assert_raises(DecisionRecorder::Invalid) { record("italian") }

    ledger("release_course", { subject: "italian", open: true, course_revision_id: @italian_course.id }, student: @official)
    record("italian")
    error = assert_raises(DecisionRecorder::Invalid) { record("italian") }
    assert_equal [ "italian is already the recommended subject" ], error.reasons
    record("")
    error = assert_raises(DecisionRecorder::Invalid) { record("") }
    assert_equal [ "no subject is recommended now" ], error.reasons
    assert_raises(DecisionRecorder::Invalid) { DecisionRecorder.call(request: console, kind: "set_focus_subject", params: {}) }
    assert_equal 2, Decision.where(kind: "set_focus_subject").count
  end

  test "the flag and the teacher list guard it, like every decision" do
    ENV["BANCO_DECISIONS_ENABLED"] = "0"
    error = assert_raises(DecisionRecorder::Refused) { record("italian") }
    assert_equal :disabled, error.reason
    ENV["BANCO_DECISIONS_ENABLED"] = "1"
    error = assert_raises(DecisionRecorder::Refused) { record("italian", origin: DecisionRecorder::Console.new(login: "someone-else")) }
    assert_equal :no_teacher, error.reason
    assert_equal 0, Decision.where(kind: "set_focus_subject").count
  end

  test "the console: a dry run writes nothing, confirm records, an empty subject clears" do
    result = DecisionConsole.call(kind: "set_focus_subject", teacher: "nik", subject: "italian")
    assert result.ok
    assert_equal({ "subject" => "italian", "via" => "console" }, result.payload)
    assert_equal 0, Decision.where(kind: "set_focus_subject").count

    assert DecisionConsole.call(kind: "set_focus_subject", teacher: "nik", subject: "italian", confirm: true).recorded
    assert_equal "italian", Course::Focus.subject_key
    cleared = DecisionConsole.call(kind: "set_focus_subject", teacher: "nik", params: { subject: "" }, confirm: true)
    assert cleared.recorded
    assert_nil Course::Focus.subject_key
    refused = DecisionConsole.call(kind: "set_focus_subject", teacher: "nik", subject: "history")
    assert_equal :missing, refused.failure
  end

  test "over the API a teacher token sets and clears it; a dry run writes nothing" do
    teacher = issue_token("teacher")
    api_as(teacher, "/api/v1/decisions", method: :post, body: { kind: "set_focus_subject", params: { subject: "italian" } })
    assert_response :success
    assert_equal false, json["recorded"]
    assert_nil Course::Focus.subject_key

    api_as(teacher, "/api/v1/decisions", method: :post, body: { kind: "set_focus_subject", params: { subject: "italian" }, confirm: true })
    assert_response :created
    assert_equal [ "api", "set_focus_subject", "italian", "student" ], [ json["decision"]["via"], json["decision"]["kind"], json["decision"]["subject"], json["decision"]["student"] ]
    assert_equal "italian", Course::Focus.subject_key
    api_as(teacher, "/api/v1/decisions", method: :post, body: { kind: "set_focus_subject", params: { subject: "" }, confirm: true })
    assert_response :created
    assert_nil Course::Focus.subject_key
    api_as(issue_token("bot_read"), "/api/v1/decisions", method: :post, body: { kind: "set_focus_subject", params: { subject: "italian" }, confirm: true })
    assert_response :forbidden
    assert_nil Course::Focus.subject_key
  end

  test "the activity feed words it, set and cleared" do
    record("italian")
    record("")
    texts = Activity.recent.map { |r| r["summary_it"] }
    assert_includes texts, "Consigliata la materia da cui cominciare (Italiano)"
    assert_includes texts, "Tolto il consiglio sulla materia da cui cominciare"
  end

  # ---- Oggi -----------------------------------------------------------------------------------------

  test "with no focus Oggi is as it was: the round robin by subject position, no line" do
    page(OFFICIAL, "/today")
    assert_equal [ TOPIC, ITALIAN_TOPIC ], suggested
    assert_select "[data-focus-line]", 0
    assert_select "li.topic[data-focus]", 0
  end

  test "the student's Oggi puts the recommended subject first with one line, and clearing it brings the round robin back" do
    record("italian")
    page(OFFICIAL, "/today")
    assert_equal [ ITALIAN_TOPIC, TOPIC ], suggested
    assert_select "[data-focus-line]", 1
    assert_select "li.topic[data-topic=?][data-focus=true] [data-focus-line]", ITALIAN_TOPIC, text: LINE
    assert_select "li.topic[data-topic=?] [data-focus-line]", TOPIC, 0
    assert_select "li.topic[data-topic='#{ITALIAN_TOPIC}'] .topic-why", text: "È il prossimo argomento del corso.", count: 1
    assert_select "li.topic.now-card[data-topic=?]", ITALIAN_TOPIC

    record("")
    page(OFFICIAL, "/today")
    assert_equal [ TOPIC, ITALIAN_TOPIC ], suggested
    assert_select "[data-focus-line]", 0
  end

  test "the line has an English twin" do
    assert_equal LINE, I18n.t("today.focus", locale: :it)
    assert_equal "Your teacher suggests you start from here.", I18n.t("today.focus", locale: :en)
  end

  test "a trial student and the teacher's preview follow the same rule for the student they show" do
    record("italian")
    page(TRIAL, "/today")
    assert_equal [ ITALIAN_TOPIC, TOPIC ], suggested
    assert_select "li.topic[data-topic=?] [data-focus-line]", ITALIAN_TOPIC, text: LINE

    page(TEACHER, "/teacher/preview/today")
    assert_equal [ ITALIAN_TOPIC, TOPIC ], suggested
    assert_select "li.topic[data-topic=?] [data-focus-line]", ITALIAN_TOPIC, text: LINE
    assert_select "[data-focus-line]", 1

    record("")
    page(TEACHER, "/teacher/preview/today")
    assert_equal [ TOPIC, ITALIAN_TOPIC ], suggested
    assert_select "[data-focus-line]", 0
  end

  test "a student who is already resuming a topic of the recommended subject gets no line: the resume card is first" do
    record("italian")
    page(OFFICIAL, "/topics/#{ITALIAN_TOPIC}/lesson")
    page(OFFICIAL, "/today")
    assert_select "#now-resume .now-title", "La lettura"
    assert_select "[data-focus-line]", 0
    assert_equal [ TOPIC ], suggested
  end

  test "a recommended subject with every programme topic done promotes nothing" do
    @clock = Diagnosis::FakeClock.new(Time.current - 20.days)
    play_topic!(@topic_revision, SKILL, 3) # math is done; italian untouched
    record("math")
    page(OFFICIAL, "/today")
    assert_equal [ ITALIAN_TOPIC ], suggested
    assert_select "[data-focus-line]", 0
  end

  test "next_topic and banco next agree with Oggi: the first topic of a subject is the one Oggi shows first" do
    record("italian")
    view = Course::StudentView.new(@official)
    assert_equal ITALIAN_TOPIC, view.today[:suggestions].first.topic_key
    assert view.today[:suggestions].first.focus
    assert_equal ITALIAN_TOPIC, view.next_topic(view.subject("italian")).topic.key
    assert_equal TOPIC, view.next_topic(view.subject("math")).topic.key

    token = issue_token("bot_read")
    api_as(token, "/api/v1/students/student/next")
    assert_response :success
    assert_equal ITALIAN_TOPIC, json["subjects"].find { |s| s["subject"] == "italian" }["next"]["topic"]
    page(OFFICIAL, "/today")
    assert_equal ITALIAN_TOPIC, suggested.first
  end

  # ---- the teacher's page ----------------------------------------------------------------------------

  test "the course page offers the button, a post records it, and the page says which subject is recommended" do
    page(TEACHER, "/teacher/subjects/math/course")
    assert_response :success
    assert_select "#course-focus[data-focus=''][data-this=false]"
    assert_select "#course-focus", text: /Per ora non consigli nessuna materia/
    assert_select "form#course-focus-form[action='/teacher/focus'] input[name=subject][value=math]"
    assert_select "form#course-focus-form button:not([disabled])", "Consiglia di cominciare da questa materia"
    assert_select "form#course-focus-clear-form", 0

    assert_difference "Decision.where(kind: 'set_focus_subject').count", 1 do
      decide("/teacher/focus", { subject: "math" })
    end
    assert_response :success
    decision = Decision.where(kind: "set_focus_subject").last
    assert_equal [ "math", "nik", "banco-teacher", @official ], [ decision.subject.key, decision.teacher_login, decision.groups, decision.student ]
    assert_equal "math", Course::Focus.subject_key

    page(TEACHER, "/teacher/subjects/math/course")
    assert_select "#course-focus[data-focus=math][data-this=true]"
    assert_select "#course-focus strong", "Consigli allo studente di cominciare da questa materia."
    assert_select "form#course-focus-form", 0
    assert_select "form#course-focus-clear-form[action='/teacher/focus'] input[name=subject][value='']"
    assert_select "form#course-focus-clear-form button", "Togli il consiglio"

    page(TEACHER, "/teacher/subjects/italian/course")
    assert_select "#course-focus[data-focus=math][data-this=false]"
    assert_select "#course-focus", text: /Ora consigli di cominciare da Math/
    assert_select "form#course-focus-form input[name=subject][value=italian]"
    assert_select "form#course-focus-clear-form"
  end

  test "the clear button records an empty subject; the form without a script goes back with a sentence" do
    record("math")
    token = csrf_token
    on(:web, "/teacher/focus", method: :post, headers: TEACHER, params: { subject: "", back: "/teacher/subjects/math/course", authenticity_token: token }, remote_addr: EDGE)
    assert_redirected_to "/teacher/subjects/math/course"
    assert_equal "Consiglio sulla materia registrato.", flash[:notice]
    assert_nil Course::Focus.subject_key
    assert_equal 2, Decision.where(kind: "set_focus_subject").count
  end

  test "a refusal is worded in Italian on the form and is a 422 for a script" do
    token = csrf_token
    on(:web, "/teacher/focus", method: :post, headers: TEACHER, params: { subject: "", back: "/teacher/subjects/math/course", authenticity_token: token }, remote_addr: EDGE)
    assert_redirected_to "/teacher/subjects/math/course"
    assert_equal "Non c'è nessun consiglio da togliere.", flash[:alert]
    decide("/teacher/focus", { subject: "history" })
    assert_response :not_found
    decide("/teacher/focus", {})
    assert_response :unprocessable_entity
    assert_equal 0, Decision.where(kind: "set_focus_subject").count
  end

  test "the button is disabled while the course is closed, and the route is closed to a guest, the student, no flag and no token" do
    ledger("release_course", { subject: "italian", open: false }, student: @official)
    page(TEACHER, "/teacher/subjects/italian/course")
    assert_select "form#course-focus-form button[disabled]"
    assert_select "#course-focus", text: /Puoi consigliare una materia quando il suo corso è aperto allo studente/
    decide("/teacher/focus", { subject: "italian" })
    assert_response :unprocessable_entity
    assert_equal "Il corso di questa materia non è ancora aperto allo studente.", Teacher::Wording.italian(json["reasons"].first)

    decide("/teacher/focus", { subject: "math" }, headers: GUEST)
    assert_response :forbidden
    decide("/teacher/focus", { subject: "math" }, headers: OFFICIAL)
    assert_response :forbidden
    decide("/teacher/focus", { subject: "math" }, csrf: false)
    assert_response :forbidden
    %i[api harness].each do |listener|
      decide("/teacher/focus", { subject: "math" }, listener: listener)
      assert_response :not_found, listener
    end
    ENV["BANCO_DECISIONS_ENABLED"] = "0"
    decide("/teacher/focus", { subject: "math" })
    assert_response :forbidden
    assert_equal 0, Decision.where(kind: "set_focus_subject").count

    page(GUEST, "/teacher/subjects/math/course")
    assert_response :success
    assert_select "#course-focus"
    assert_select "form#course-focus-form", 0
  end

  test "the course over the API says the recommended subject" do
    record("math")
    token = issue_token("bot_read")
    api_as(token, "/api/v1/teacher/subjects/math/course")
    assert_response :success
    assert_equal [ "math", true ], json.values_at("focus_subject", "recommended")
    api_as(token, "/api/v1/teacher/subjects/italian/course")
    assert_equal [ "math", false ], json.values_at("focus_subject", "recommended")
  end
end
