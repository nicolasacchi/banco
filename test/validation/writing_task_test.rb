require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/lesson_md"
require_relative "../support/writing_world"

# D-407: the writing tasks of a topic. A topic may pin short_answer items of its subject with a word range (`writing`); the pins are checked like the other pinned
# items, never count for the practice pool, are reviewed and blind-solved like any pinned item and are stale like any pin. A blueprint never pins one.
class WritingTaskTest < ActiveSupport::TestCase
  include CourseRows
  SKILL = "math.linear-equation-integer".freeze
  KEY = "ripasso.math.demo-equations".freeze

  setup do
    build_course
    entry = { key: KEY, kind: "ripasso", title_it: "Equazioni", term: 1, minutes: 30, skills: [ SKILL ], after: [] }
    @course = build_course_map(skills: [], topics: [ entry ])
    outcome = Validation::LessonChecks.call(LessonMd.build(front: { "skills" => [ SKILL ], "uses" => [] }), subject: "math", context: LessonMd.context(skills: [ SKILL ]))
    lesson = Lesson.create!(subject: @subject, key: outcome.body["key"], kind: outcome.body["kind"])
    @lesson_revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: "---\n", source_sha256: "1" * 64, body_json: JSON.generate(outcome.body),
                                              rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
    @a = make_practice_item("math-p-a", SKILL, level: 1)
    @b = make_practice_item("math-p-b", SKILL, level: 2)
    @task = writing_item("math-w-a")
  end

  def writing_item(key, status: "passed", without: [], **over)
    item = Item.create!(subject: @subject, key: key, kind: "short_answer")
    body = { "schema" => "banco.item/1", "schema_version" => 1, "kind" => "short_answer", "subject" => "math", "skill" => SKILL, "component" => "short_answer",
             "prompt" => { "stem_it" => "Racconta come hai risolto un'equazione." }, "words_min" => 20, "words_max" => 60, "teacher_notes_it" => "Guarda la verifica.",
             "rubric" => { "points" => [ { "id" => "steps", "weight" => 1, "expected_it" => "Nomina i passaggi." }, { "id" => "check", "weight" => 1, "expected_it" => "Nomina la verifica." } ],
                           "threshold" => 0.5, "model_answer_it" => "Passaggi e verifica." },
             "sources" => [ { "kind" => "textbook", "ref" => "capitolo di esempio", "fragment" => "equazioni" } ] }.merge(over).except(*without)
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: status, codes_json: "[]") if status
    revision
  end

  def topic(writing: [ { "item" => "math-w-a", "revision" => "latest" } ], items: %w[math-p-a math-p-b])
    doc = { "schema" => "banco.topic/1", "schema_version" => 1, "subject" => "math", "key" => KEY, "lesson_revision" => "latest",
            "practice" => [ { "skill" => SKILL, "items" => items.map { |i| { "item" => i, "revision" => "latest" } } } ] }
    writing ? doc.merge("writing" => writing) : doc
  end

  def check(doc) = Validation::TopicChecks.call(doc, subject: @subject)
  def codes(doc) = check(doc).findings.map(&:code).uniq

  # ---- the topic ---------------------------------------------------------------------------------------------

  test "a topic pins a writing task: stored with the integer revision beside the practice, whose pool and findings it does not change" do
    without = check(topic(writing: nil))
    result = check(topic)
    assert_empty without.findings.errors.map(&:code), "the practice alone is a good topic"
    assert_equal without.findings.map(&:code), result.findings.map(&:code), "a writing task adds no finding and removes none"
    assert_equal [ { "item" => "math-w-a", "revision" => @task.id } ], result.stored["writing"]
    assert_equal [ @a.id, @b.id ], result.stored["practice"].flat_map { |p| p["items"].map { |i| i["revision"] } }
    assert_equal [ @a, @b, @task ].map(&:id), result.item_revisions.map(&:id)
    assert_nil without.stored["writing"], "a topic with no task stores none"
  end

  test "the writing pins are checked: a practice item, a short answer with no range, an exercise pinned twice, an unknown and an unpassed item" do
    writing_item("math-w-bare", without: %w[words_min words_max teacher_notes_it])
    writing_item("math-w-failed", status: "failed")
    {
      "E-TOPIC-WRITING" => [ [ "math-p-a" ], [ "math-w-bare" ] ],
      "E-TOPIC-PIN" => [ [ "math-w-missing" ] ],
      "E-ITEM-NOT-PASSED" => [ [ "math-w-failed" ] ]
    }.each do |code, cases|
      cases.each do |keys|
        found = codes(topic(writing: keys.map { |k| { "item" => k, "revision" => "latest" } }))
        assert_includes found, code, keys.inspect
      end
    end
    twice = check(topic(writing: [ { "item" => "math-w-a", "revision" => "latest" }, { "item" => "math-w-a", "revision" => "latest" } ]))
    assert_includes twice.findings.map(&:code), "E-TOPIC-WRITING"
  end

  test "a writing task of another subject is not found in this one" do
    other = Subject.create!(key: "italian", name_it: "Italiano", position: 2)
    Item.create!(subject: other, key: "italian-w-x", kind: "short_answer")
    assert_includes codes(topic(writing: [ { "item" => "italian-w-x", "revision" => "latest" } ])), "E-TOPIC-PIN"
  end

  test "a pinned revision of a writing task that is not the newest passed one is a stale pin, as for an exercise" do
    newer = ItemRevision.create!(item: @task.item, seq: 2, body_json: @task.body_json, file_sessions_json: "{}")
    ItemValidation.create!(item_revision: newer, seq: 1, status: "passed", codes_json: "[]")
    assert_includes check(topic(writing: [ { "item" => "math-w-a", "revision" => @task.id } ])).findings.map(&:code), "W-STALE-PIN"
    assert_not_includes check(topic(writing: [ { "item" => "math-w-a", "revision" => newer.id } ])).findings.map(&:code), "W-STALE-PIN"
  end

  # ---- the gate and the stale pins -----------------------------------------------------------------------------

  test "the approval gate reads the writing task like a pinned item: its review and its blind solve are asked, a newer revision makes it stale" do
    body = {
      "schema" => "banco.topic/1", "key" => KEY, "practice" => [ { "skill" => SKILL, "items" => [ { "item" => "math-p-a", "revision" => @a.id }, { "item" => "math-p-b", "revision" => @b.id } ] } ],
      "writing" => [ { "item" => "math-w-a", "revision" => @task.id } ]
    }
    revision = TopicRevision.create!(lesson: @lesson_revision.lesson, seq: 1, course_revision: @course, lesson_revision: @lesson_revision, body_json: JSON.generate(body))
    assert_equal [ @a.id, @b.id, @task.id ], revision.pinned_item_revision_ids
    assert_equal [ @task.id ], revision.writing_pins.map { |p| p["revision"] }
    assert_equal revision.pinned_item_revision_ids, Approval::TopicGate.item_revision_ids(revision)
    reasons = Approval::TopicGate.mechanical(revision).reasons
    assert(reasons.any? { |r| r.include?("item revision #{@task.id} is not approvable") && r.include?("no expert review") }, reasons.inspect)

    newer = ItemRevision.create!(item: @task.item, seq: 2, body_json: @task.body_json, file_sessions_json: "{}")
    ItemValidation.create!(item_revision: newer, seq: 1, status: "passed", codes_json: "[]")
    stale, = Course::TopicStage.stale_pins(revision)
    assert_equal [ { skill: nil, item: "math-w-a", pinned: @task.id, newest_passed: newer.id } ], stale
    assert_includes Course::TopicStage.reasons(revision, { "skills" => [ SKILL ] }, stale, { pinned: 1, latest: 1 }).join, "not the newest passed revision"
  end

  # ---- the item and the blueprint --------------------------------------------------------------------------------

  test "a word range that runs backwards is E-WRITING-RANGE; the schema wants both ends and the notes only with a range" do
    findings = Validation::Findings.new
    Validation::ItemChecks.writing_range({ "words_min" => 90, "words_max" => 60 }, findings)
    assert_equal [ "E-WRITING-RANGE" ], findings.map(&:code)
    findings = Validation::Findings.new
    Validation::ItemChecks.writing_range({ "words_min" => 60, "words_max" => 60 }, findings)
    assert_empty findings.map(&:code)

    body = JSON.parse(@task.body_json)
    assert_empty Banco::Schemas.validate("item", body).map(&:message)
    [ body.except("words_max"), body.except("words_min", "words_max"), body.merge("words_min" => 0), body.merge("words_max" => 601),
      body.merge("kind" => "diagnosis_item", "component" => "number") ].each do |bad|
      assert_not_empty Banco::Schemas.validate("item", bad), bad.slice("words_min", "words_max", "teacher_notes_it").inspect
    end
  end

  test "a blueprint never pins a writing task" do
    info = Validation::ItemInfo.for(@task)
    assert info.writing
    assert_equal "short_answer", info.kind
    assert_not Validation::ItemInfo.for(@a).writing
    findings = Validation::Findings.new
    Validation::BlueprintChecks.pinned([ @task.id ], SKILL, "/entries/0/pinned", ->(_id) { info }, findings)
    assert_equal [ "E-BLUEPRINT-WRITING-ITEM" ], findings.map(&:code)
  end

  test "the new codes are in the registry" do
    registry = YAML.load_file(Rails.root.join("config/banco/error_codes.yml"))["validation"]
    %w[E-TOPIC-WRITING E-WRITING-RANGE E-BLUEPRINT-WRITING-ITEM].each { |code| assert registry.key?(code), code }
  end
end
