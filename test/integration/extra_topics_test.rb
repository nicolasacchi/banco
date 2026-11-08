require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/lesson_md"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"
require_relative "../support/decision_world"
require_relative "../support/course_path_world"

# Topics outside the programme (D-324): what the content agents rely on (map, lesson and topic validation over the API),
# what the student sees (Materia's own section, never in Oggi) and what the teacher sees (the course path's section, the
# badge). Invented content only.
class ExtraTopicsApiTest < ActionDispatch::IntegrationTest
  include CourseRows
  L = LessonMd
  SKILL = "math.linear-equation-integer".freeze
  NEW_SKILL = "math.linear-system-substitution".freeze
  EXTRA_SKILL = "math.demo-inequalities".freeze
  EXTRA = "extra.math.demo-inequalities".freeze
  OFFICIAL_REF = { "source" => "ufficiale-2026-27", "line" => 1, "fragment" => "disequazioni di primo grado", "role" => "taught_in" }.freeze

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "extra topics test")
    build_course
    seconda = SyllabusSource.create!(key: "seconda-2025-26", line_count: 1, sha256: "3" * 64)
    SyllabusLine.create!(syllabus_source: seconda, number: 1, text: "sistemi lineari: metodo di sostituzione", origin: "pdf")
    official = SyllabusSource.create!(key: "ufficiale-2026-27", line_count: 1, sha256: "4" * 64)
    SyllabusLine.create!(syllabus_source: official, number: 1, text: "disequazioni di primo grado intere", origin: "pdf")
    @author = AgentSession.create!(label: "t", role: "author", agent: "test", model: "claude-opus-5-5")
  end

  def api(path, method: :get, body: nil)
    headers = { "Authorization" => "Bearer #{@token}", "X-Banco-Session" => @author.id.to_s }
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil)
  end

  def json = response.parsed_body

  def skill(key, ref)
    { "key" => key, "label_it" => "Abilità #{key}", "layer" => "core", "prerequisites" => [], "refs" => [ ref ],
      "errors" => [ { "code" => "slip", "description_it" => "Sbaglia un passaggio.", "implicates" => [] } ] }
  end

  def course_doc(extra_kind: "extra")
    extra_key = "#{extra_kind}.math.demo-inequalities"
    { "schema" => "banco.course/1", "schema_version" => 1, "subject" => "math",
      "skills" => [ skill(NEW_SKILL, { "source" => "seconda-2025-26", "line" => 1, "fragment" => "metodo di sostituzione", "role" => "taught_in" }),
                    skill(EXTRA_SKILL, OFFICIAL_REF) ],
      "topics" => [
        { "key" => "lezione.math.demo-systems", "kind" => "lezione", "title_it" => "Sistemi lineari", "term" => 1, "minutes" => 45, "skills" => [ NEW_SKILL ], "after" => [] },
        { "key" => extra_key, "kind" => extra_kind, "title_it" => "Disequazioni", "term" => nil, "minutes" => 30, "skills" => [ EXTRA_SKILL ], "after" => [] }
      ] }
  end

  def submit_course(doc) = api("/api/v1/subjects/math/course", method: :post, body: { course: doc })

  def submit_lesson(md, key) = api("/api/v1/lessons/submit", method: :post, body: { lesson: key, base: nil, files: { "lesson.md" => md } })

  def extra_md(refs: [ OFFICIAL_REF ], scope: "extra")
    L.build(front: { "kind" => "extra", "key" => EXTRA, "scope" => scope, "skills" => [ EXTRA_SKILL ], "uses" => [], "refs" => refs })
  end

  def lezione_md
    L.build(front: { "kind" => "lezione", "key" => "lezione.math.demo-systems", "scope" => "seconda", "skills" => [ NEW_SKILL ], "uses" => [],
                     "refs" => [ { "source" => "seconda-2025-26", "line" => 1, "fragment" => "metodo di sostituzione", "role" => "taught_in" } ] })
  end

  def submit_topic(key, skill, items)
    doc = { "schema" => "banco.topic/1", "schema_version" => 1, "subject" => "math", "key" => key, "lesson_revision" => "latest",
            "practice" => [ { "skill" => skill, "items" => items.map { |i| { "item" => i, "revision" => "latest" } } } ] }
    api("/api/v1/topics/#{key}", method: :post, body: { topic: doc })
  end

  test "a skill taught only in the official programme is refused in a lezione and accepted in an extra topic" do
    submit_course(course_doc(extra_kind: "lezione"))
    assert_response :unprocessable_entity
    assert_equal "E-COURSE-EXTRA-SKILL", json["code"], json.inspect
    assert_equal 0, CourseRevision.count
    submit_course(course_doc)
    assert_response :created, json.inspect
  end

  test "an extra lesson validates with kind and scope extra and a taught_in ref on the official programme" do
    submit_course(course_doc)
    submit_lesson(extra_md(refs: [ { "source" => "seconda-2025-26", "line" => 1, "fragment" => "metodo di sostituzione", "role" => "needed_by" } ]), EXTRA)
    assert_response :unprocessable_entity
    assert_equal "E-LESSON-REFS", json["code"], json.inspect
    submit_lesson(extra_md(scope: "seconda"), EXTRA)
    assert_response :unprocessable_entity
    assert_equal "E-LESSON-REFS", json["code"], json.inspect
    submit_lesson(extra_md, EXTRA)
    assert_response :created, json.inspect
    assert_equal "extra", Lesson.find_by!(key: EXTRA).kind
  end

  test "a pool of 10 instances, all hard to guess, passes for an extra topic and fails for a lezione" do
    submit_course(course_doc)
    submit_lesson(extra_md, EXTRA)
    assert_response :created, json.inspect
    submit_lesson(lezione_md, "lezione.math.demo-systems")
    assert_response :created, json.inspect
    make_practice_item("math-p-ex-1", EXTRA_SKILL, instances: 5, level: 1)
    make_practice_item("math-p-ex-2", EXTRA_SKILL, instances: 5, level: 2)
    make_practice_item("math-p-sys-1", NEW_SKILL, instances: 5, level: 1)
    make_practice_item("math-p-sys-2", NEW_SKILL, instances: 5, level: 2)
    submit_topic("lezione.math.demo-systems", NEW_SKILL, %w[math-p-sys-1 math-p-sys-2])
    assert_response :unprocessable_entity
    assert_equal "E-TOPIC-POOL", json["code"], json.inspect
    submit_topic(EXTRA, EXTRA_SKILL, %w[math-p-ex-1 math-p-ex-2])
    assert_response :created, json.inspect
  end

  test "an extra topic still needs 6 hard-to-guess instances per skill" do
    submit_course(course_doc)
    submit_lesson(extra_md, EXTRA)
    make_practice_item("math-p-ex-1", EXTRA_SKILL, instances: 5, level: 1)
    make_practice_item("math-p-ex-choice", EXTRA_SKILL, instances: 5, level: 2, component: "choice")
    submit_topic(EXTRA, EXTRA_SKILL, %w[math-p-ex-1 math-p-ex-choice])
    assert_response :unprocessable_entity
    assert_equal "E-TOPIC-POOL", json["code"], json.inspect
    assert_match(/hard-to-guess/, json.to_s)
  end
end

class ExtraTopicsStudentTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  EXTRA = "extra.math.demo-percentages".freeze
  EXTRA_SKILL = "math.percentages".freeze
  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

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
  end

  def page(path) = on(:web, path, headers: OFFICIAL, remote_addr: EDGE)

  def post_json(path, body)
    page("/today")
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: OFFICIAL.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  test "Materia lists the extra topic after the programme, under «Fuori programma (facoltativo)», with its badge" do
    page("/subjects/math")
    assert_response :success
    assert_select "#topics li[data-topic=?]", TOPIC
    assert_select "#topics li[data-topic=?]", EXTRA, 0
    assert_select "#extra-topics-section h2", "Fuori programma (facoltativo)"
    assert_select "#extra-topics li[data-topic=?][data-extra=true] [data-extra-badge]", EXTRA, text: "Fuori programma"
    assert_operator response.body.index("id=\"topics\""), :<, response.body.index("id=\"extra-topics\"")
    page("/topics/#{EXTRA}")
    assert_response :success
    assert_select "#extra-badge", "Fuori programma"
  end

  test "the counts of the subject leave the extra topic out" do
    view = Course::StudentView.new(@official)
    sv = view.subject("math")
    assert_equal [ TOPIC ], view.programme_topics(sv).map(&:key)
    assert_equal [ EXTRA ], view.extra_topics(sv).map(&:key)
    assert_equal 1, view.counts(sv).values.sum
    assert_not_includes view.skills_without_topic(sv), EXTRA_SKILL
  end

  test "Oggi never suggests an extra topic, not even after the student practised it" do
    page("/today")
    assert_response :success
    assert_select "#suggestions li[data-topic=?]", TOPIC
    assert_select "#course-part [data-topic=?]", EXTRA, 0
    post_json("/practice/serves", { topic: EXTRA, skill: EXTRA_SKILL })
    assert_response :success
    assert_equal 1, PracticeServe.where(student: @official).count
    page("/today")
    assert_select "#course-part [data-topic=?]", EXTRA, 0
    assert css_select("#course-part a").none? { |a| a["href"].to_s.include?(EXTRA) }, "Oggi links the extra topic"
  end
end

class ExtraTopicsTeacherTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include CoursePathWorld

  EXTRA = "extra.math.substitution-more".freeze
  EXTRA_SKILL = "math.linear-system-substitution".freeze

  setup do
    build_course_path_world
    @course = build_course_map(subject: @subject, topics: PATH_TOPICS + [
      { key: EXTRA, kind: "extra", title_it: "Sostituzione, per curiosità", skills: [ EXTRA_SKILL ], minutes: 20, term: nil, after: [] }
    ])
    lesson = path_lesson!(EXTRA, EXTRA_SKILL, reviewed: true)
    make_topic(lesson, { EXTRA_SKILL => [ 1, 2 ].map { |level| path_item!("substitution-more-#{level}", EXTRA_SKILL, level) } }, course: @course)
  end

  def page(path) = on(:web, path, headers: TEACHER, remote_addr: EDGE)

  test "the course path lists the extra topic in its own section «Fuori programma», with the badge" do
    page("/teacher/subjects/math/course")
    assert_response :success
    assert_select "#course-topics li[data-topic=?]", EXTRA, 0
    assert_equal [ READY, WORKING, MISSING, DONE ], css_select("#course-topics ol.path > li").map { |li| li["data-topic"] }
    assert_select "#course-extra-topics h2", "Fuori programma"
    assert_select "#course-extra-topics li[data-topic=?][data-extra=true]", EXTRA do
      assert_select "[data-extra-badge]", "Fuori programma"
      assert_select ".step-number", "1"
    end
  end

  test "the topic page shows the badge on an extra topic only" do
    page("/teacher/subjects/math/topics/#{EXTRA}")
    assert_response :success
    assert_select "#topic-extra-badge", "Fuori programma"
    assert_select "#topic-extra-note"
    page("/teacher/subjects/math/topics/#{READY}")
    assert_select "#topic-extra-badge", 0
  end
end
