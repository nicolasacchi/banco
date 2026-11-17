require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"
require_relative "../support/student_ui_rows"

# D-333: what the student does next, per subject, over the API (`banco next`), for the token roles that read. No rule of its own: the topic
# is the one Oggi shows first for the subject (the page is read in the same test and the two are compared), «skills to recover» are the
# states the pages call «Dal test: da ripassare». Invented content only (the progress world of D-326).
class StudentNextApiTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld
  include StudentUiRows

  READ_ROLES = %w[bot_read teacher].freeze
  CONTENT_ROLES = %w[agent_claude agent_omp ci].freeze
  NEXT_KEYS = %w[topic title_it kind minutes term why_it].freeze

  setup do
    build_progress_world
    # Both reading roles read the same (the content roles are refused, D-327); a teacher token acts as a login on the teacher list, and none needs a session.
    @tokens = (READ_ROLES + CONTENT_ROLES).to_h { |role| [ role, ApiToken.issue!(role: role, label: "next #{role}", expires_at: 30.days.from_now, teacher_login: ("nik" if role == "teacher")) ] }
  end

  def api(path, token: @tokens.fetch("bot_read")) = on(:api, path, headers: token ? { "Authorization" => "Bearer #{token}" } : {})

  def json = response.parsed_body

  def page(path, headers: OFFICIAL) = on(:web, path, headers: headers, remote_addr: EDGE)

  # The topic Oggi shows first: the «Riprendi» card when there is one, else the first suggestion.
  def oggi_first(headers: OFFICIAL)
    page("/today", headers: headers)
    assert_response :success
    resume = css_select("#resume").first
    return resume["href"][%r{/topics/([^/#?]+)}, 1] if resume

    css_select("#suggestions li.topic").first&.[]("data-topic")
  end

  def math = json["subjects"].find { |s| s["subject"] == "math" }

  test "no token is E-AUTH, every role that may read gets the same answer, a content agent's token is refused" do
    api("/api/v1/students/student/next", token: nil)
    assert_response :unauthorized
    assert_equal "E-AUTH", json["code"]
    bodies = @tokens.slice(*READ_ROLES).map do |role, token|
      api("/api/v1/students/student/next", token: token)
      assert_response :success, role
      response.body
    end
    assert_equal 1, bodies.uniq.size
    CONTENT_ROLES.each do |role|
      api("/api/v1/students/student/next", token: @tokens.fetch(role))
      assert_response :forbidden, role
      assert_equal "token_role", json["reason"]
    end
  end

  test "next is the topic Oggi shows first for the subject, with its facts, never an extra topic" do
    expected = oggi_first
    assert_equal PROGRESS_STARTED, expected, "the world: the topic begun comes first in course order"
    api("/api/v1/students/student/next")
    assert_response :success
    assert_equal "student", json["student"]
    assert_equal [ "math" ], json["subjects"].map { |s| s["subject"] }
    assert_equal @subject.name_it, math["name_it"]
    pick = math["next"]
    assert_equal NEXT_KEYS.sort, pick.keys.sort
    assert_equal expected, pick["topic"]
    assert_equal [ "Frazioni", "lezione", 20, 1 ], pick.values_at("title_it", "kind", "minutes", "term")
    assert_equal I18n.t("today.reason.course_next"), pick["why_it"]
    assert_not_operator pick["topic"], :start_with?, "extra."
    assert_equal "Obbligatori: 1 fatto su 3", math["done_it"]
    assert_empty math["skills_to_recover"]
  end

  test "a lesson opened is the topic Oggi resumes, and next says so" do
    page("/topics/#{PROGRESS_TODO}/lesson")
    assert_response :success
    expected = oggi_first
    assert_equal PROGRESS_TODO, expected, "Oggi resumes the lesson that was opened"
    api("/api/v1/students/student/next")
    assert_equal expected, math["next"]["topic"]
    assert_equal I18n.t("today.reason.resume"), math["next"]["why_it"]
  end

  test "a skill that went back to review is listed to recover, with the topic that teaches it, as Materia tags it" do
    choice = serve!(student: @official, topic: @topic_revision, skill: SKILL)
    answer!(choice, wrong_raw, student: @official)
    api("/api/v1/students/student/progress")
    progress = json["subjects"].find { |s| s["key"] == "math" }
    assert_equal "to_review", progress["skills"].find { |s| s["key"] == SKILL }["state"]
    assert_equal [ TOPIC ], progress["topics"].select { |t| t["to_recover"] }.map { |t| t["key"] }
    label = progress["skills"].find { |s| s["key"] == SKILL }["label_it"]
    expected = oggi_first
    api("/api/v1/students/student/next")
    assert_equal [ { "skill" => SKILL, "label_it" => label, "taught_in" => TOPIC } ], math["skills_to_recover"]
    assert_equal expected, math["next"]["topic"]
  end

  test "a subject with every programme topic done has next null, as Oggi has nothing to propose" do
    play_topic!(@progress_topics.fetch(PROGRESS_STARTED), "math.prog-iniziato", 3)
    play_topic!(@progress_topics.fetch(PROGRESS_TODO), "math.prog-da-fare", 3)
    assert_nil oggi_first
    api("/api/v1/students/student/next")
    assert_response :success
    assert_nil math["next"]
    assert_empty math["skills_to_recover"]
    assert_equal "Obbligatori: 3 fatti su 3", math["done_it"]
  end

  test "a subject whose course was withdrawn is listed with next null" do
    release_course!(Course::State.latest(@subject), open: false)
    api("/api/v1/students/student/next")
    assert_response :success
    assert_equal [ { "subject" => "math", "name_it" => @subject.name_it, "next" => nil, "skills_to_recover" => [], "done_it" => I18n.t("today.closed") } ], json["subjects"]
  end

  test "subject keeps one subject; a subject without a course gives no row; an unknown one is E-NOT-FOUND" do
    build_ui_subject(key: "geography", name: "Geografia", position: 2)
    api("/api/v1/students/student/next?subject=math")
    assert_response :success
    assert_equal [ "math" ], json["subjects"].map { |s| s["subject"] }
    api("/api/v1/students/student/next?subject=geography")
    assert_response :success
    assert_empty json["subjects"]
    [ "nope", "Bad!" ].each do |name|
      api("/api/v1/students/student/next?subject=#{name}")
      assert_response :not_found, name
      assert_equal [ "E-NOT-FOUND", "subject" ], json.values_at("code", "field")
    end
  end

  test "a trial student has own next, the one Oggi shows that student" do
    expected = oggi_first(headers: TRIAL)
    assert_equal TOPIC, expected
    api("/api/v1/students/prova-1/next")
    assert_response :success
    assert_equal "prova-1", json["student"]
    assert_equal expected, math["next"]["topic"]
  end

  test "an unknown key and the preview student are E-NOT-FOUND" do
    api("/api/v1/students/nobody/next")
    assert_response :not_found
    assert_equal [ "E-NOT-FOUND", "student" ], json.values_at("code", "field")
    api("/api/v1/students/preview/next")
    assert_response :not_found
  end

  test "a read writes nothing" do
    assert_no_difference [ "PracticeEvent.count", "PracticeServe.count", "Decision.count", "AppEvent.count", "CommentEvent.count" ] do
      api("/api/v1/students/student/next")
      api("/api/v1/students/prova-1/next?subject=math")
    end
  end
end
