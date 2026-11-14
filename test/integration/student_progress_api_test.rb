require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"
require_relative "../support/student_ui_rows"

# D-328: what the student sees of their progress, over the API, for every token role that may read. The answer is compared with
# the student's own pages (Materia and the diagnosis list) for the same world; invented content only.
class StudentProgressApiTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld
  include StudentUiRows

  EXTRA = "extra.math.demo-percentages".freeze
  EXTRA_SKILL = "math.percentages".freeze
  READ_ROLES = %w[bot_read teacher agent_claude agent_omp ci].freeze

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
    @tokens = (READ_ROLES & ApiToken::ROLES).to_h { |role| [ role, ApiToken.issue!(role: role, label: "progress #{role}") ] }
  end

  def api(path, token: @tokens.fetch("agent_claude")) = on(:api, path, headers: token ? { "Authorization" => "Bearer #{token}" } : {})

  def json = response.parsed_body

  def page(path, headers: OFFICIAL) = on(:web, path, headers: headers, remote_addr: EDGE)

  test "no token is E-AUTH, and every role that may read gets the same answer" do
    api("/api/v1/students/student/progress", token: nil)
    assert_response :unauthorized
    assert_equal "E-AUTH", json["code"]
    bodies = @tokens.map do |role, token|
      api("/api/v1/students/student/progress", token: token)
      assert_response :success, role
      response.body
    end
    assert_equal 1, bodies.uniq.size
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
    assert_equal({ "done" => 0, "in_progress" => 0, "todo" => 1, "total" => 1 }, subject["topic_counts"], "the extra topic is in no count")
    assert_equal 1, subject["skill_counts"].values.sum
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
    assert_equal({ "done" => 0, "in_progress" => 1, "todo" => 0, "total" => 1 }, subject["topic_counts"])
    assert_equal "todo", subject["extra_topics"].first["status"]
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
