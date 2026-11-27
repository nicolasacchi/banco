require "test_helper"
require_relative "../support/public_api_tokens"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/lesson2_fixtures"

# D-403, round 9: `banco item grade --file` and `banco lesson grade --file` grade a local body that is not stored: the server builds the instances or the
# lesson body as the dry run builds them, nothing is written, and a reader token is enough.
class GradeDraftTest < ActionDispatch::IntegrationTest
  include CourseRows
  include PublicApiTokens
  F = ValidationFixtures
  SKILL = "math.linear-equation-integer".freeze
  KEY = "ripasso.math.demo-equations".freeze

  setup do
    build_course
    prima = SyllabusSource.create!(key: "prima-2025-26", line_count: 2, sha256: "2" * 64)
    SyllabusLine.create!(syllabus_source: prima, number: 1, text: "equazioni di primo grado", origin: "pdf")
    SyllabusLine.create!(syllabus_source: prima, number: 2, text: "PAGINA 2", origin: "transcript")
    seconda = SyllabusSource.create!(key: "seconda-2025-26", line_count: 2, sha256: "3" * 64)
    SyllabusLine.create!(syllabus_source: seconda, number: 1, text: "sistemi lineari: metodo di sostituzione", origin: "pdf")
    SyllabusLine.create!(syllabus_source: seconda, number: 2, text: "equazioni di primo grado numeriche intere", origin: "pdf")
    Validation::DryRun.clear_cache
    @reader = issue_token("bot_read")
    @author = issue_token("agent_claude")
  end

  def api(path, body, token: @reader)
    on(:api, path, method: :post, headers: { "Authorization" => "Bearer #{token}" }, params: body, as: :json)
  end

  def json = response.parsed_body

  def counts = [ Item, ItemRevision, ItemValidation, ItemInstance, Lesson, LessonRevision, LessonEvent, AppEvent ].map(&:count)

  def md2
    text = Lesson2Fixtures.read("base.md")
    text = text.sub("skills: [math.demo-equation]", "skills: [#{SKILL}]").sub("uses: [math.demo-signed-numbers]", "uses: [math.integer-operations]")
    text.sub("line: 12,", "line: 2,").sub("line: 7,", "line: 1,")
  end

  # The id of the number check of the lesson (the checks of the lesson are all graded once, to read their components).
  def number_check(md, ids)
    api("/api/v1/lesson-grade", { files: { "lesson.md" => md }, answers: ids.map { |id| { check: id, answer: "3" } } })
    found = json["results"].find { |r| r["component"] == "number" }
    assert found, "the lesson has a number check: #{ids}"
    found["check"]
  end

  # ---- items ----

  test "item grade --file: the instances of a local item are graded as the dry run builds them, nothing is stored, a reader token is enough" do
    before = counts
    files = F.files_for(F.static_item)
    api("/api/v1/item-grade", { files: files, answers: [ { instance: 1, answer: "7" }, { instance: 1, answer: "11" }, { instance: 2, answer: "9" }, { instance: 3, answer: "16" } ] })
    assert_response :ok, json.inspect
    assert_equal [ true, true ], [ json["draft"], json["read_only"] ]
    assert_not json.key?("revision_id")
    right, typical, other, last = json["results"]
    assert_equal [ "correct", "key", "7" ], [ right["verdict"], right["matched"]["kind"], right["matched"]["value"] ]
    assert_equal [ "typical_error", "sign_error" ], [ typical["verdict"], typical["error_code"] ], "x+2=9: 11 is the declared error value"
    assert_equal [ 2, "correct" ], [ other["instance"], other["verdict"] ], "x+4=13 has the answer 9"
    assert_equal "correct", last["verdict"]
    assert_equal before, counts, "nothing is stored"
    api("/api/v1/item-grade", { files: files, answers: [ { instance: 1, answer: "7" } ] }, token: @author)
    assert_response :ok
    assert_equal "correct", json["results"].first["verdict"]
  end

  test "item grade --file: an unknown instance is a 404, a bad body is E-FILES, an item the dry run refuses is refused with its findings" do
    files = F.files_for(F.static_item)
    api("/api/v1/item-grade", { files: files, answers: [ { instance: 9, answer: "7" } ] })
    assert_response :not_found
    assert_equal [ "E-NOT-FOUND", "answers/0/instance" ], [ json["code"], json["field"] ]
    assert_match(/the item has no instance 9 \(it has 3: 1-3\)/, json["message"])
    api("/api/v1/item-grade", { files: files, answers: [] })
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    api("/api/v1/item-grade", { files: {}, answers: [ { instance: 1, answer: "7" } ] })
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    api("/api/v1/item-grade", { files: { "item.json" => "{" }, answers: [ { instance: 1, answer: "7" } ] })
    assert_response :unprocessable_entity
    assert_equal [ "E-FILES", "item.json" ], [ json["code"], json["field"] ]
    api("/api/v1/item-grade", { files: { "notes.txt" => "x" }, answers: [ { instance: 1, answer: "7" } ] })
    assert_equal "E-FILES", json["code"]
    api("/api/v1/item-grade", { files: F.files_for(F.static_item("prompt" => { "stem_it" => "Scrivi la risposta che cercano." })), answers: [ { instance: 1, answer: "7" } ] })
    assert_response :unprocessable_entity
    assert_predicate json["codes"], :any?
    assert_predicate json["findings"], :any?
    api("/api/v1/item-grade", { files: files.merge("item.json" => F.files_for(F.static_item("subject" => "nowhere"))["item.json"]), answers: [ { instance: 1, answer: "7" } ] })
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
  end

  test "item grade --file takes no session and checks no stored item: the key of an existing item is no business of the draft" do
    stored = Item.create!(subject: @subject, key: "eq-1", kind: "diagnosis_item")
    before = counts
    api("/api/v1/item-grade", { files: F.files_for(F.static_item), answers: [ { instance: 1, answer: "7" } ] })
    assert_response :ok, json.inspect
    assert_equal before, counts
    assert_equal 0, stored.revisions.count
  end

  # ---- lessons ----

  test "lesson grade --file: the checks of a local lesson.md are graded as the dry run builds it, nothing is stored, a reader token is enough" do
    before = counts
    md = md2
    api("/api/v1/lesson-grade", { files: { "lesson.md" => md }, answers: [ { check: "9.9", answer: "x" } ] })
    assert_response :not_found
    assert_equal [ "E-NOT-FOUND", "answers/0/check" ], [ json["code"], json["field"] ]
    ids = json["checks"]
    assert_predicate ids, :any?, json.inspect
    number = number_check(md, ids)
    api("/api/v1/lesson-grade", { files: { "lesson.md" => md }, answers: [ { check: number, answer: "3" }, { check: number, answer: "12" }, { check: number, answer: "5" } ] })
    assert_response :ok, json.inspect
    assert_equal [ true, true, KEY ], [ json["draft"], json["read_only"], json["lesson"] ]
    assert_not json.key?("revision_id")
    right, typical, wrong = json["results"]
    assert_equal [ "right", "key" ], [ right["verdict"], right["matched"]["kind"] ]
    assert_equal [ "wrong", "math_divide_missing", "Hai moltiplicato per 2 invece di dividere." ], [ typical["verdict"], typical["error_code"], typical["message"]["message_it"] ]
    assert_equal "wrong", wrong["verdict"]
    assert_equal before, counts, "no lesson, no revision, no event"
    api("/api/v1/lesson-grade", { files: { "lesson.md" => md }, answers: [ { check: number, answer: "3" } ] }, token: @author)
    assert_response :ok
  end

  test "a changed lesson.md is graded as changed (a variant of the answer), and a lesson the dry run refuses is refused with its findings" do
    variant = md2.sub("answer: '3'\nerrors:\n  - {answer: '12'", "answer: '4'\nerrors:\n  - {answer: '12'")
    assert_not_equal md2, variant
    api("/api/v1/lesson-grade", { files: { "lesson.md" => variant }, answers: [ { check: "9.9", answer: "x" } ] })
    id = number_check(variant, json["checks"])
    api("/api/v1/lesson-grade", { files: { "lesson.md" => variant }, answers: [ { check: id, answer: "4" }, { check: id, answer: "3" } ] })
    assert_equal [ "right", "wrong" ], json["results"].map { |r| r["verdict"] }

    api("/api/v1/lesson-grade", { files: { "lesson.md" => md2.sub("schema: banco.lesson/2", "schema: banco.lesson/1") }, answers: [ { check: "1.1", answer: "x" } ] })
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    api("/api/v1/lesson-grade", { files: { "lesson.md" => md2.sub("skills: [#{SKILL}]", "skills: [math.no-such-skill]") }, answers: [ { check: "1.1", answer: "x" } ] })
    assert_response :unprocessable_entity
    assert_predicate json["findings"], :any?
    api("/api/v1/lesson-grade", { files: { "lesson.md" => md2.sub("key: #{KEY}", "key: ripasso.nowhere.demo") }, answers: [ { check: "1.1", answer: "x" } ] })
    assert_response :not_found
    api("/api/v1/lesson-grade", { files: { "other.md" => "x" }, answers: [ { check: "1.1", answer: "x" } ] })
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    api("/api/v1/lesson-grade", { files: { "lesson.md" => md2 }, answers: [] })
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
  end
end
