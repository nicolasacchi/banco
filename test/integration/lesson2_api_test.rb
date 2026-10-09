require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/lesson_md"
require_relative "../support/lesson2_fixtures"

# banco.lesson/2 over the agent API (rich lessons R1): submit dispatches on the schema, open --schema 2 converts,
# the switch lesson.accept_schema1. Invented content only.
class Lesson2ApiTest < ActionDispatch::IntegrationTest
  include CourseRows
  SKILL = "math.linear-equation-integer".freeze
  KEY = "ripasso.math.demo-equations".freeze

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "lesson2 test")
    build_course
    prima = SyllabusSource.create!(key: "prima-2025-26", line_count: 2, sha256: "2" * 64)
    SyllabusLine.create!(syllabus_source: prima, number: 1, text: "equazioni di primo grado", origin: "pdf")
    SyllabusLine.create!(syllabus_source: prima, number: 2, text: "PAGINA 2", origin: "transcript")
    seconda = SyllabusSource.create!(key: "seconda-2025-26", line_count: 2, sha256: "3" * 64)
    SyllabusLine.create!(syllabus_source: seconda, number: 1, text: "sistemi lineari: metodo di sostituzione", origin: "pdf")
    SyllabusLine.create!(syllabus_source: seconda, number: 2, text: "equazioni di primo grado numeriche intere", origin: "pdf")
    @author = AgentSession.create!(label: "t", role: "author", agent: "test", model: "claude-opus-5-5")
  end

  def api(path, method: :get, body: nil, as: nil, dry: false)
    headers = { "Authorization" => "Bearer #{@token}" }
    headers["X-Banco-Session"] = as.id.to_s if as
    headers["X-Banco-Dry-Run"] = "1" if dry
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil)
  end

  def json = response.parsed_body

  # base.md of the lesson2 fixtures, placed in this test's invented course.
  def md2
    text = Lesson2Fixtures.read("base.md")
    text = text.sub("skills: [math.demo-equation]", "skills: [#{SKILL}]").sub("uses: [math.demo-signed-numbers]", "uses: [math.integer-operations]")
    text = text.sub("line: 12,", "line: 2,").sub("line: 7,", "line: 1,")
    block_given? ? yield(text) : text
  end

  def submit(md, base: nil, dry: false) = api("/api/v1/lessons/submit", method: :post, body: { lesson: KEY, base: base, files: { "lesson.md" => md } }, as: @author, dry: dry)

  test "a lesson/2 file is checked by the lesson/2 checks and stored as a banco.lesson/2 body" do
    submit(md2, dry: true)
    assert_response :ok, json.inspect
    assert_equal 0, LessonRevision.count
    submit(md2)
    assert_response :created, json.inspect
    revision = LessonRevision.find(json["revision_id"])
    assert_equal "banco.lesson/2", revision.body["schema"]
    assert_equal 7, revision.body["cards"].size
    assert_empty Banco::Schemas.validate("lesson", revision.body)
    assert_equal "8", revision.rules_version
    submit(md2, base: revision.id)
    assert_response :ok
    assert_equal true, json["replayed"]
  end

  test "a lesson/2 fault answers with its code and the line" do
    submit(md2 { |t| t.sub("## Errori da evitare {mistakes}", "## Errori da evitare") })
    assert_response :unprocessable_entity
    assert_equal "E-LESSON-CARD", json["code"]
    assert_equal 99, json["findings"].first.dig("detail", "line")
    submit(md2 { |t| t.sub("answer: b\n", "answer: z\n") })
    assert_equal "E-LESSON-CHECK", json["code"]
    assert_equal 0, LessonRevision.count
  end

  test "a lesson/2 file over 96 KB is E-LESSON-SIZE, not a bare 413" do
    submit(md2 { |t| t.sub(/\n---\n\n## /, "\n#{"# x\n" * 40_000}---\n\n## ") })
    assert_response :unprocessable_entity
    assert_equal "E-LESSON-SIZE", json["code"]
  end

  test "lesson open --schema 2 converts the latest lesson/1 revision and leaves a lesson/2 as it is" do
    submit(LessonMd.build(front: { "skills" => [ SKILL ], "uses" => [ "math.integer-operations" ] }))
    assert_response :created, json.inspect
    first = json["revision_id"]
    api("/api/v1/lessons/#{KEY}?schema=2")
    assert_response :ok, json.inspect
    assert_equal true, json["converted_from_schema1"]
    assert_equal first, json.dig("latest", "revision_id")
    draft = json.dig("files", "lesson.md")
    assert Lessons::Parser2.schema2?(draft)
    assert_includes draft, "## In sintesi {summary}"
    api("/api/v1/lessons/#{KEY}")
    assert_includes json.dig("files", "lesson.md"), "banco.lesson/1"
    api("/api/v1/lessons/#{KEY}?schema=3")
    assert_response :unprocessable_entity
    submit(md2, base: first)
    assert_response :created, json.inspect
    api("/api/v1/lessons/#{KEY}?schema=2")
    assert_equal false, json["converted_from_schema1"]
    assert_includes json.dig("files", "lesson.md"), "banco.lesson/2"
  end

  test "with lesson.accept_schema1 false a lesson/1 submit is E-LESSON-SCHEMA and a lesson/2 still passes" do
    Validation::Rules.with(lesson: { accept_schema1: false }) do
      submit(LessonMd.build(front: { "skills" => [ SKILL ], "uses" => [ "math.integer-operations" ] }))
      assert_response :unprocessable_entity
      assert_equal "E-LESSON-SCHEMA", json["code"]
      submit(md2, dry: true)
      assert_response :ok, json.inspect
    end
  end

  test "status and the lessons list read a lesson/2 revision" do
    submit(md2)
    assert_response :created
    id = json["revision_id"]
    api("/api/v1/lesson-revisions/#{id}")
    assert_response :ok, json.inspect
    api("/api/v1/subjects/math/lessons")
    assert_response :ok, json.inspect
    assert_equal KEY, json["rows"].first["lesson"]
  end
end
