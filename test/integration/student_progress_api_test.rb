require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"
require_relative "../support/student_ui_rows"

# D-328: what the student sees of their progress, over the API, for the token roles that read (bot_read, teacher). The answer is compared with
# the student's own pages (Materia and the diagnosis list) for the same world; invented content only.
class StudentProgressApiTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld
  include StudentUiRows

  EXTRA = "extra.math.demo-percentages".freeze
  EXTRA_SKILL = "math.percentages".freeze
  READ_ROLES = %w[bot_read teacher].freeze
  CONTENT_ROLES = %w[agent_claude agent_omp ci].freeze

  setup do
    build_student_world(release: false)
    course = build_course_map(skills: [], topics: [
      { key: TOPIC, kind: "ripasso", title_it: TOPIC_TITLE, skills: [ SKILL ], minutes: 30, term: 1, after: [] },
      { key: EXTRA, kind: "extra", title_it: "Percentuali per curiosità", skills: [ EXTRA_SKILL ], minutes: 20, term: nil, after: [] }
    ])
    lesson = Lesson.create!(subject: @subject, key: EXTRA, kind: "extra")
    body = lesson_body.merge(key: EXTRA, kind: "extra", title_it: "Percentuali", skills: [ EXTRA_SKILL ], scope: "extra",
                             refs: [ { source: "ufficiale-2026-27", line: 1, fragment: "percentuali", role: "taught_in" } ])
    revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: "---\n", source_sha256: "1" * 64, rules_version: Validation::Rules.version.to_s,
                                      warnings_json: "[]", body_json: JSON.generate(body))
    items = Array.new(2) { |i| make_practice_item("extra-item-#{i + 1}", EXTRA_SKILL, instances: 6, level: i + 1) }
    @extra_topic = TopicRevision.create!(lesson: lesson, seq: 1, course_revision: course, lesson_revision: revision,
                                         body_json: JSON.generate(schema: "banco.topic/1", key: EXTRA,
                                                                  practice: [ { skill: EXTRA_SKILL, items: items.map { |r| { item: r.item.key, revision: r.id } } } ]))
    approve_topic!(@extra_topic)
    release_course!(course)
    # Both reading roles read the same (the content roles are refused, D-327); a teacher token acts as a login on the teacher list (MultiUser lists "nik"), and none needs a session.
    @tokens = (READ_ROLES + CONTENT_ROLES).to_h { |role| [ role, ApiToken.issue!(role: role, label: "progress #{role}", expires_at: 30.days.from_now, teacher_login: ("nik" if role == "teacher")) ] }
  end

  def api(path, token: @tokens.fetch("bot_read")) = on(:api, path, headers: token ? { "Authorization" => "Bearer #{token}" } : {})

  def json = response.parsed_body

  def page(path, headers: OFFICIAL) = on(:web, path, headers: headers, remote_addr: EDGE)

  test "no token is E-AUTH, and every role that may read gets the same answer" do
    api("/api/v1/students/student/progress", token: nil)
    assert_response :unauthorized
    assert_equal "E-AUTH", json["code"]
    bodies = @tokens.slice(*READ_ROLES).map do |role, token|
      api("/api/v1/students/student/progress", token: token)
      assert_response :success, role
      response.body
    end
    assert_equal 1, bodies.uniq.size
  end

  test "a content agent's token is refused: the student's progress is not content (D-327)" do
    CONTENT_ROLES.each do |role|
      api("/api/v1/students/student/progress", token: @tokens.fetch(role))
      assert_response :forbidden, role
      assert_equal "token_role", json["reason"]
    end
  end

  test "the topics and their status are the ones of Materia, the extra topic apart" do
    page("/subjects/math")
    rows = css_select("li.topic").map { |li| [ li["data-topic"], li["data-status"], li["data-extra"] == "true" ] }
    api("/api/v1/students/student/progress")
    subject = json["subjects"].find { |s| s["key"] == "math" }
    assert_equal rows.reject(&:last).map { |key, status, _| [ key, status ] }, subject["topics"].map { |t| [ t["key"], t["status"] ] }
    assert_equal rows.select(&:last).map { |key, status, _| [ key, status ] }, subject["extra_topics"].map { |t| [ t["key"], t["status"] ] }
    assert_equal [ [ TOPIC, "todo" ] ], subject["topics"].map { |t| [ t["key"], t["status"] ] }
    assert_equal [ [ EXTRA, "todo" ] ], subject["extra_topics"].map { |t| [ t["key"], t["status"] ] }
    assert_equal({ "total" => 1, "done" => 0, "in_progress" => 0, "missing" => 1, "percent" => 0, "known" => 0, "exercises" => 0, "minutes_left" => 30, "hours_left" => 0 }, subject["programme"])
    assert_equal({ "total" => 1, "done" => 0, "in_progress" => 0, "missing" => 1, "percent" => 0, "known" => 0, "exercises" => 0, "minutes_left" => 20, "hours_left" => 0 }, subject["extra"])
    assert_equal 0, subject["correct_exercises"]
    assert_equal 0, json["overall"]["correct_exercises"]
    assert_equal subject["programme"], json["overall"]["programme"], "one subject: the overall is its programme"
    assert_equal subject["extra"], json["overall"]["extra"]
    assert_nil subject["entry_test"], "no entry test for this subject in the list"
    assert_equal true, subject["released"]
    assert_equal "student", json.dig("student", "key")
    assert_equal true, json.dig("student", "official")
    assert_equal [ SKILL, EXTRA_SKILL ].sort, subject["skills"].map { |s| s["key"] }.sort
    assert(subject["skills"].all? { |s| s["state"] == "not_seen" })
  end

  test "opening a lesson makes the topic in progress, here as on Materia" do
    page("/topics/#{TOPIC}/lesson")
    assert_response :success
    page("/subjects/math")
    assert_equal "in_progress", css_select("li.topic[data-topic='#{TOPIC}']").first["data-status"]
    api("/api/v1/students/student/progress")
    subject = json["subjects"].first
    assert_equal "in_progress", subject["topics"].first["status"]
    assert_equal true, subject["topics"].first["lesson_read"]
    assert_equal({ "total" => 1, "done" => 0, "in_progress" => 1, "missing" => 1, "percent" => 0, "known" => 0, "exercises" => 0, "minutes_left" => 30, "hours_left" => 0 }, subject["programme"])
    assert_equal subject["programme"], json["overall"]["programme"]
    assert_equal "todo", subject["extra_topics"].first["status"]
  end

  # D-367: the same split as the pages, added to the tallies; every field of D-328 is still there with the same meaning.
  test "the programme tally says how many were known from the entry test and how many were done with the exercises, and the time left" do
    seeds = { SKILL => Practice::Seed.new(skill: SKILL, state: "demonstrated", at: Time.current - 5.days, run_id: 1, implied: false) }
    Practice::Seeder.stub(:call, seeds) do
      api("/api/v1/students/student/progress")
    end
    subject = json["subjects"].first
    assert_equal({ "total" => 1, "done" => 1, "in_progress" => 0, "missing" => 0, "percent" => 100, "known" => 1, "exercises" => 0, "minutes_left" => 0, "hours_left" => 0 }, subject["programme"])
    assert_equal "done", subject["topics"].first["status"]
    assert_equal 0, subject["correct_exercises"], "nothing was answered: the entry test is not an exercise"
    assert_equal subject["programme"], json["overall"]["programme"]
  end

  test "a topic closed with the exercises is counted apart, with the right answers of the subject" do
    @clock = Diagnosis::FakeClock.new(Time.current - 20.days)
    play_topic!(@topic_revision, SKILL, 3)
    api("/api/v1/students/student/progress")
    subject = json["subjects"].first
    assert_equal({ "total" => 1, "done" => 1, "in_progress" => 0, "missing" => 0, "percent" => 100, "known" => 0, "exercises" => 1, "minutes_left" => 0, "hours_left" => 0 }, subject["programme"])
    assert_equal({ "total" => 1, "done" => 0, "in_progress" => 0, "missing" => 1, "percent" => 0, "known" => 0, "exercises" => 0, "minutes_left" => 20, "hours_left" => 0 }, subject["extra"])
    assert_equal 3, subject["correct_exercises"]
    assert_equal 3, json["overall"]["correct_exercises"]
    page("/subjects/math")
    assert_select "#subject-summary .progress-line[data-line=correct] .progress-text", "Esercizi giusti: 3"
    assert_select "#subject-summary .progress-line[data-line=exercises] .progress-text", "Fatti con gli esercizi: 1"
  end

  test "the entry tests are the diagnosis list of the student" do
    build_ui_subject(key: "geography", name: "Geografia", position: 2)
    release_diagnosis!
    page("/diagnosis")
    rows = css_select("li[data-subject]").map { |li| [ li["data-subject"], li["data-state"], li.at_css(".subject-state").text.strip ] }
    assert_operator rows.size, :>, 0
    api("/api/v1/students/student/progress")
    assert_equal rows, json["entry_tests"].map { |e| [ e["subject"], e["status"], e["label_it"] ] }
    assert_equal [ "geography" ], json["entry_tests"].map { |e| e["subject"] }
    assert_equal [ true ], json["entry_tests"].map { |e| e["startable"] }
  end

  test "the entry test of geography is named as at the student's school (D-343), on the page and over the API" do
    build_ui_subject(key: "geography", name: "Geografia", position: 2)
    release_diagnosis!
    page("/diagnosis")
    assert_select "li[data-subject=geography] .subject-name", "Geografia economica"
    api("/api/v1/students/student/progress")
    assert_equal [ "Geografia economica" ], json["entry_tests"].map { |e| e["name_it"] }
  end

  test "a trial student has own progress; an unknown key is E-NOT-FOUND; the preview student is not a student" do
    api("/api/v1/students/prova-1/progress")
    assert_response :success
    assert_equal false, json.dig("student", "official")
    assert_equal "math", json["subjects"].first["key"]
    api("/api/v1/students/nobody/progress")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    api("/api/v1/students/preview/progress")
    assert_response :not_found
  end

  test "the official student before the release has no subject in the course part" do
    release_course!(Course::State.latest(@subject), open: false)
    api("/api/v1/students/student/progress")
    assert_response :success
    assert_empty json["subjects"]
    assert_equal [ "math" ], json["closed_subjects"].map { |s| s["key"] }
  end

  test "a read writes nothing" do
    assert_no_difference [ "PracticeEvent.count", "PracticeServe.count", "Decision.count", "AppEvent.count" ] do
      api("/api/v1/students/student/progress")
      api("/api/v1/students/prova-1/progress")
    end
  end
end
