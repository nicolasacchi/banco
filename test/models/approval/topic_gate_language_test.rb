require "test_helper"
require_relative "../../support/student_course_world"

# A topic of english or spanish half rewritten in the target language (D-402): the gate derives its language status and warns (W-TOPIC-LANG-MIXED),
# never blocks. A topic with nothing rewritten, or all of it, is not mixed; a subject that teaches no language has no status.
class TopicGateLanguageTest < ActiveSupport::TestCase
  include StudentCourseWorld

  setup { build_student_world }

  def as_english
    original = Lessons::Lang.method(:target)
    Lessons::Lang.define_singleton_method(:target) { |subject| subject.to_s == "math" ? "en" : original.call(subject) }
    yield
  ensure
    Lessons::Lang.define_singleton_method(:target, original)
  end

  def bilingual_item(key)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", kind: "practice_item", subject: "math", skill: SKILL, component: "number", bilingual: true }
    ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
  end

  # A topic revision on a new lesson revision and course map; every part optional.
  def topic_with(lesson: false, title: false, intro: false, items: [])
    body = lesson_body.merge(lesson ? { bilingual: true } : {})
    lesson_revision = LessonRevision.create!(lesson: @lesson, seq: (@lesson.revisions.maximum(:seq) || 0) + 1, source_md: "---\n", source_sha256: SecureRandom.hex(32),
                                             rules_version: Validation::Rules.version.to_s, warnings_json: "[]", body_json: JSON.generate(body))
    entry = { key: TOPIC, kind: "ripasso", title_it: TOPIC_TITLE, skills: [ SKILL ], minutes: 30, term: 1, after: [] }
    entry[:title_en] = "Linear equations" if title
    course = build_course_map(skills: [], topics: [ entry ])
    texts = { intro_it: "Qui impari." }
    texts[:intro_en] = "Learn here." if intro
    pinned = (@revisions + items).map { |r| { item: r.item.key, revision: r.id } }
    TopicRevision.create!(lesson: @lesson, seq: @lesson.topic_revisions.maximum(:seq) + 1, course_revision: course, lesson_revision: lesson_revision,
                          body_json: JSON.generate({ schema: "banco.topic/1", key: TOPIC, practice: [ { skill: SKILL, items: pinned } ] }.merge(texts)))
  end

  test "a subject that teaches no language has no status and no warning" do
    revision = topic_with(lesson: true, title: true)
    assert_nil Approval::TopicGate.language_status(revision)
    assert_nil Approval::TopicGate.language_warning(revision)
  end

  test "nothing rewritten yet is not mixed: no warning" do
    as_english do
      status = Approval::TopicGate.language_status(topic_with)
      assert_equal "en", status.lang
      assert_equal [ false, false, false, 0, 2 ], [ status.lesson, status.title, status.intro, status.items_done, status.items_total ]
      refute status.mixed?
      assert_nil Approval::TopicGate.language_warning(topic_with)
    end
  end

  test "a lesson and a title rewritten with the items not: mixed, the warning names what is left" do
    as_english do
      revision = topic_with(lesson: true, title: true)
      status = Approval::TopicGate.language_status(revision)
      assert status.mixed?
      assert_equal %i[intro items], status.missing
      warning = Approval::TopicGate.language_warning(revision)
      assert_includes warning, "W-TOPIC-LANG-MIXED"
      assert_includes warning, "l'introduzione"
      assert_includes warning, "2 esercizi su 2"
      refute_includes warning, "la lezione"
    end
  end

  test "some items rewritten and some not: the count is of the missing ones" do
    as_english do
      revision = topic_with(lesson: true, title: true, intro: true, items: [ bilingual_item("bi-1") ])
      status = Approval::TopicGate.language_status(revision)
      assert_equal [ 1, 3 ], [ status.items_done, status.items_total ]
      assert_equal [ :items ], status.missing
      assert_includes Approval::TopicGate.language_warning(revision), "2 esercizi su 3"
    end
  end

  test "everything rewritten is not mixed" do
    as_english do
      @revisions.replace([ bilingual_item("bi-a"), bilingual_item("bi-b") ])
      revision = topic_with(lesson: true, title: true, intro: true)
      status = Approval::TopicGate.language_status(revision)
      assert_empty status.missing
      refute status.mixed?
      assert_nil Approval::TopicGate.language_warning(revision)
    end
  end

  test "the warning never blocks approving: the mechanical reasons do not mention it" do
    as_english do
      revision = topic_with(lesson: true, title: true)
      assert_empty(Approval::TopicGate.mechanical(revision).reasons.grep(/lang|bilingual|translation/i))
    end
  end

  test "the teacher's topic review carries the warning for the latest revision" do
    as_english do
      topic_with(lesson: true, title: true)
      assert_includes Teacher::TopicReview.new(@subject, TOPIC).language_warning, "W-TOPIC-LANG-MIXED"
    end
  end
end
