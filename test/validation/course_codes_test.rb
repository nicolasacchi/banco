require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/lesson_md"

# Every code of the course map and the topic has a bad fixture here, and so has the lesson (lesson_checks_test).
# Together they cover the Phase 1b codes of the registry (A3.2).
class CourseCodesTest < ActiveSupport::TestCase
  include CourseRows
  SKILL = "math.linear-equation-integer".freeze
  NEW_SKILL = "math.linear-system-substitution".freeze

  setup do
    build_course
    build_course_map(skills: [ course_skill ], topics: [ topic_entry ])
    @lesson = lesson_from(LessonMd.build(front: { "skills" => [ SKILL ], "uses" => [] }))
    @good = make_practice_item("math-p-a", SKILL, level: 1)
    @other = make_practice_item("math-p-b", SKILL, level: 2)
  end

  def course_skill(**over)
    { "key" => NEW_SKILL, "label_it" => "Sistemi lineari", "layer" => "core", "prerequisites" => [ SKILL ],
      "refs" => [ { "source" => "seconda-2025-26", "line" => 1, "fragment" => "metodo di sostituzione", "role" => "taught_in" } ],
      "errors" => [ { "code" => "subst", "description_it" => "Sostituisce male.", "implicates" => [] } ] }.merge(over).transform_keys(&:to_s)
  end

  def topic_entry(**over)
    { "key" => "ripasso.math.demo-equations", "kind" => "ripasso", "title_it" => "Equazioni", "term" => 1, "minutes" => 30, "skills" => [ SKILL ], "after" => [] }.merge(over.transform_keys(&:to_s))
  end

  def course_doc(skills: [ course_skill ], topics: nil)
    topics ||= [ topic_entry, topic_entry(key: "lezione.math.demo-systems", kind: "lezione", skills: [ NEW_SKILL ]) ]
    { "schema" => "banco.course/1", "schema_version" => 1, "subject" => "math", "skills" => skills, "topics" => topics }
  end

  def course_codes(doc)
    Validation::CourseChecks.call(doc, subject: "math", graph: ValidationFixtures::GRAPH, context: LessonMd.context).map(&:code).uniq
  end

  def lesson_from(md)
    outcome = Validation::LessonChecks.call(md, subject: "math", context: LessonMd.context(skills: [ SKILL, "math.integer-operations" ]))
    lesson = Lesson.find_or_create_by!(key: outcome.body["key"]) { |l| l.subject = @subject; l.kind = outcome.body["kind"] }
    LessonRevision.create!(lesson: lesson, seq: (lesson.revisions.maximum(:seq) || 0) + 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md),
                           body_json: JSON.generate(outcome.body), rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  def topic_codes(doc)
    Validation::TopicChecks.call(doc, subject: @subject).findings.map(&:code).uniq
  end

  def topic(items = [ "math-p-a", "math-p-b" ], skill: SKILL, key: "ripasso.math.demo-equations", **over)
    { "schema" => "banco.topic/1", "schema_version" => 1, "subject" => "math", "key" => key, "lesson_revision" => "latest",
      "practice" => [ { "skill" => skill, "items" => items.map { |i| { "item" => i, "revision" => "latest" } } } ] }.merge(over)
  end

  CASES = {
    "E-COURSE-SKILL-DUPLICATE" => ->(t) { t.course_codes(t.course_doc(skills: [ t.course_skill("key" => SKILL) ], topics: [ t.topic_entry ])) },
    "E-COURSE-TOPIC" => ->(t) { t.course_codes(t.course_doc(topics: [ t.topic_entry, t.topic_entry("skills" => [ SKILL ], "key" => "lezione.math.demo-systems", "kind" => "lezione") ])) },
    "W-COURSE-ORDER" => ->(t) { t.course_codes(t.course_doc(topics: [ t.topic_entry("after" => [ "lezione.math.demo-systems" ]), t.topic_entry("key" => "lezione.math.demo-systems", "kind" => "lezione", "skills" => [ NEW_SKILL ]) ])) },
    "W-COURSE-GRAPH-STALE" => ->(t) {
      revision = CourseRevision.last
      SkillGraphRevision.create!(subject: t.instance_variable_get(:@subject), seq: 2, body_json: JSON.generate(ValidationFixtures::GRAPH))
      Course::State.warnings(revision).map { |w| w["code"] }
    },
    "E-TOPIC-UNKNOWN" => ->(t) { t.topic_codes(t.topic(key: "ripasso.math.not-in-the-map")) },
    "E-TOPIC-PIN" => ->(t) { t.topic_codes(t.topic([ "math-p-a", "math-p-missing" ])) },
    "E-TOPIC-SKILLS" => ->(t) { t.topic_codes(t.topic([ "math-p-a", "math-p-b" ], skill: "math.percentages")) },
    "E-TOPIC-ITEM-KIND" => ->(t) { t.make_revision("math-d-x", SKILL); t.topic_codes(t.topic([ "math-p-a", "math-d-x" ])) },
    "E-TOPIC-POOL" => ->(t) {
      t.make_practice_item("math-p-few", SKILL, instances: 2, level: 1)
      t.make_practice_item("math-p-few2", SKILL, instances: 2, level: 2)
      t.topic_codes(t.topic([ "math-p-few", "math-p-few2" ]))
    },
    "W-TOPIC-INSTANCE-IN-LESSON" => ->(t) {
      t.practice_with("math-p-copy", [ "$5x = 10$" ] + (1..11).map { |i| "$#{i + 7}x = 3$" })
      t.topic_codes(t.topic([ "math-p-a", "math-p-copy" ]))
    },
    "W-PRACTICE-DIAGNOSIS-OVERLAP" => ->(t) {
      diagnosis = t.make_revision("math-d-overlap", SKILL, instances: 1)
      t.practice_with("math-p-same", (1..12).map { |i| "$#{i + 20}x = 5$" }, fingerprints: [ diagnosis.instances.first.fingerprint ])
      t.topic_codes(t.topic([ "math-p-a", "math-p-same" ]))
    }
  }.freeze

  test "the good course map and the good topic have no error" do
    assert_not_includes course_codes(course_doc), "E-COURSE-TOPIC"
    assert_empty Validation::CourseChecks.call(course_doc, subject: "math", graph: ValidationFixtures::GRAPH, context: LessonMd.context).errors
  end

  CASES.each do |code, run|
    test "#{code} has a bad fixture" do
      assert_includes run.call(self), code
    end
  end

  # A practice item with the given stems (and fingerprints, the rest derived).
  def practice_with(key, stems, fingerprints: [], level: 1)
    revision = make_practice_item(key, SKILL, instances: 0, level: level)
    stems.each_with_index do |stem, i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_it: stem), answer_json: JSON.generate("1"),
                           hints_json: "[]", solution_json: "{}", errors_json: "[]", fingerprint: fingerprints[i] || Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end
end
