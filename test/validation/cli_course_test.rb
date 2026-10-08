require "test_helper"
require "open3"
require "tmpdir"
require_relative "../support/validation_servers"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/lesson_md"

# The compiled CLI against the API listener: the course cycle of Phase 1b, end to end. course -> lesson ->
# review -> practice items -> topic -> topics list says awaiting_teacher, where the agent stops. No Chrome:
# the practice items are rows (their pipeline is tested with the items). Needs Go; skips without it.
class CliCourseTest < ActiveSupport::TestCase
  include CourseRows
  L = LessonMd
  SKILL = "math.linear-equation-integer".freeze

  class << self
    def bin = @bin ||= Rails.root.join("tmp/banco-course-#{Process.pid}").to_s

    def build_cli
      return @built unless @built.nil?

      @built = system({ "GOFLAGS" => "-buildvcs=false" }, "go", "build", "-o", bin, "./cli", chdir: Rails.root.to_s, out: File::NULL, err: File::NULL)
      path = bin
      at_exit { FileUtils.rm_f(path) }
      @built
    end
  end

  setup do
    skip "go is not installed" unless system("go", "version", out: File::NULL, err: File::NULL)
    skip "the CLI did not build" unless self.class.build_cli
    @token = ApiToken.issue!(role: "agent_claude", label: "cli course")
    build_course
    prima = SyllabusSource.create!(key: "prima-2025-26", line_count: 1, sha256: "2" * 64)
    SyllabusLine.create!(syllabus_source: prima, number: 1, text: "equazioni di primo grado", origin: "pdf")
    seconda = SyllabusSource.create!(key: "seconda-2025-26", line_count: 2, sha256: "3" * 64)
    SyllabusLine.create!(syllabus_source: seconda, number: 1, text: "sistemi lineari: metodo di sostituzione", origin: "pdf")
    SyllabusLine.create!(syllabus_source: seconda, number: 2, text: "equazioni di primo grado numeriche intere", origin: "pdf")
    @author = AgentSession.create!(label: "cli", role: "author", agent: "test", model: "claude-opus-5-5")
    @reviewer = AgentSession.create!(label: "cli", role: "reviewer", agent: "test", model: "gpt-5.2")
    @tmp = Dir.mktmpdir("banco-cli-course-")
  end

  teardown { FileUtils.rm_rf(@tmp) if @tmp }

  def banco(*args, as: @author)
    env = { "BANCO_URL" => ValidationServers.url(:api), "BANCO_TOKEN" => @token, "BANCO_SESSION" => as.id.to_s, "TMPDIR" => @tmp }
    out, err, status = Open3.capture3(env, self.class.bin, *args, chdir: @tmp)
    [ status.exitstatus, (JSON.parse(out) rescue nil), (JSON.parse(err.lines.last.to_s) rescue nil), err ]
  end

  def write(name, content)
    path = File.join(@tmp, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content.is_a?(String) ? content : JSON.pretty_generate(content))
    path
  end

  def course
    { "schema" => "banco.course/1", "schema_version" => 1, "subject" => "math", "skills" => [], "topics" => [
      { "key" => "ripasso.math.demo-equations", "kind" => "ripasso", "title_it" => "Equazioni di primo grado", "term" => 1, "minutes" => 45, "skills" => [ SKILL ], "after" => [] }
    ] }
  end

  test "the whole cycle, up to awaiting_teacher" do
    code, out, err, raw = banco("course", "submit", "--subject", "math", write("course.json", course), "--dry-run")
    assert_equal 0, code, raw
    assert_equal "passed", out["status"]
    code, out, = banco("course", "submit", "--subject", "math", write("course.json", course))
    assert_equal 0, code
    assert_equal false, out["replayed"]
    code, out, = banco("course", "open", "--subject", "math")
    assert_equal 1, out.dig("revision", "course", "topics").size

    # A new lesson does not exist yet: lesson open answers 404, the author writes lesson.md and submits the folder.
    code, _o, err, = banco("lesson", "open", "ripasso.math.demo-equations")
    assert_equal "E-NOT-FOUND", err["code"]
    assert_not_equal 0, code
    dir = File.join(@tmp, "lesson")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "lesson.md"), L.build(front: { "skills" => [ SKILL ], "uses" => [ "math.integer-operations" ] }))
    code, out, err, raw = banco("lesson", "submit", dir, "--dry-run")
    assert_equal 0, code, raw
    code, out, = banco("lesson", "submit", dir)
    assert_equal 0, code
    revision = out["revision_id"]
    assert_equal revision.to_s, File.read(File.join(dir, ".base")).strip
    code, out, = banco("lessons", "list", "--subject", "math")
    assert_equal 0, out["rows"].first["reviews"]

    # The lesson as written is not accepted twice with the wrong base, and a bad lesson is refused with its code.
    File.write(File.join(dir, "lesson.md"), L.build(front: { "skills" => [ SKILL ] }, sections: { "idea_it" => "Il valore x^2 è grande." }))
    code, _o, err, = banco("lesson", "submit", dir, "--dry-run")
    assert_equal 3, code
    assert_equal "E-LESSON-MARKUP", err["code"]

    # A reviewer in another session reads and files one review.
    code, out, = banco("lesson-review", "open", revision.to_s, as: @reviewer)
    assert_equal 0, code
    assert_equal 8, out["checklist"].size
    review = { "schema" => "banco.lesson_review/1", "schema_version" => 1, "revision" => revision.to_s,
               "checklist" => (1..8).map { |i| { "id" => i, "result" => "pass", "evidence" => "Ricontrollato l'esercizio numero #{i} con il calcolo esatto, nessun difetto." } },
               "recomputed" => (1..8).map { |i| { "where" => "solutions", "n" => (i % 4) + 1, "expression" => "#{i} + #{i}", "value" => (i * 2).to_s } }, "findings" => [] }
    code, out, _e, raw = banco("lesson-review", "submit", revision.to_s, "--file", write("review.json", review), as: @reviewer)
    assert_equal 0, code, raw
    code, out, = banco("lesson", "status", revision.to_s)
    assert_equal 1, out["reviews"].size

    # The practice items (rows here), then the topic.
    a = make_practice_item("math-p-demo-1", SKILL, level: 1)
    b = make_practice_item("math-p-demo-2", SKILL, level: 2)
    code, out, = banco("items", "list", "--subject", "math", "--kind", "practice")
    assert_equal 0, code
    assert_equal %w[math-p-demo-1 math-p-demo-2], out["rows"].map { |r| r["item"] }.sort
    topic = { "schema" => "banco.topic/1", "schema_version" => 1, "subject" => "math", "key" => "ripasso.math.demo-equations", "lesson_revision" => "latest",
              "practice" => [ { "skill" => SKILL, "items" => [ { "item" => "math-p-demo-1", "revision" => "latest" }, { "item" => "math-p-demo-2", "revision" => "latest" } ] } ] }
    code, out, _e, raw = banco("topic", "submit", write("topic.json", topic), "--dry-run")
    assert_equal 0, code, raw
    assert_equal revision, out.dig("stored", "lesson_revision")
    code, out, _e, raw = banco("topic", "submit", write("topic.json", topic))
    assert_equal 0, code, raw
    code, out, = banco("topics", "list", "--subject", "math")
    assert_equal "in_review", out["rows"].first["stage"]
    [ a, b ].each do |r|
      ItemReview.create!(item_revision: r, agent_session: AgentSession.create!(label: "r", role: "reviewer", agent: "t", model: "gpt-5.2"), checklist_json: "[]")
      BlindSolve.create!(item_revision: r, agent_session: AgentSession.create!(label: "s", role: "solver", agent: "t", model: "kimi-k3"), answers_json: "[]", results_json: "[]")
    end
    code, out, = banco("topics", "list", "--subject", "math")
    assert_equal "awaiting_teacher", out["rows"].first["stage"], out.inspect
    code, out, = banco("topic", "open", "ripasso.math.demo-equations")
    assert_equal "awaiting_teacher", out["stage"]
    code, out, = banco("status")
    assert_equal "corso: 1 dal docente (1 nella mappa) · chiuso allo studente", out["subjects"].first.dig("course", "line_it")
    code, out, = banco("practice", "progress", "--subject", "math")
    assert_equal 0, code
  end
end
