require "test_helper"
require_relative "../../support/practice_world"

# What each student sees of the course (A6.2).
class CourseCatalogTest < ActiveSupport::TestCase
  include PracticeWorld

  KEY = "lezione.math.linear-systems".freeze
  NEW_SKILL = "math.linear-system-substitution".freeze

  setup do
    build_course
    @official = practice_student("student")
    @trial = practice_student("trial-c")
    @course = build_course_map
    @lesson_revision = make_lesson(KEY, skills: [ NEW_SKILL ])
    @item = make_practice_item("math-c-1", NEW_SKILL)
    @topic = make_topic(@lesson_revision, { NEW_SKILL => [ @item ] }, course: @course)
  end

  def decide!(kind, payload, subject: @subject)
    Decision.create!(kind: kind, subject: subject, payload_json: JSON.generate(payload), request_id: SecureRandom.hex(4), teacher_login: "teacher", remote_addr: "127.0.0.1")
  end

  def approve!(topic = @topic) = decide!("approve_topic", { topic_revision_id: topic.id, topic: KEY, seq: topic.seq, course_revision_id: topic.course_revision_id })
  def release!(open: true, course: @course) = decide!("release_course", open ? { subject: "math", open: true, course_revision_id: course.id } : { subject: "math", open: false })

  def catalog(student) = Course::Catalog.for(student)

  test "a trial student sees the latest map and the latest topic revision at once, as a draft" do
    view = catalog(@trial).sole
    assert_equal [ :trial, @subject ], [ view.mode, view.subject ]
    assert_equal @course, view.course_revision
    topic = view.topics.sole
    assert_equal [ KEY, "lezione", "Sistemi lineari", 30, [ NEW_SKILL ], @topic, @lesson_revision, false ],
                 [ topic.key, topic.kind, topic.title_it, topic.minutes, topic.skills, topic.topic_revision, topic.lesson_revision, topic.approved ]
    assert_not view.released
  end

  test "a trial student sees an approved revision as approved" do
    approve!
    assert catalog(@trial).sole.topics.sole.approved
  end

  test "the official student sees nothing until the course is released" do
    approve!
    assert_empty catalog(@official)
  end

  test "a release without an approved topic shows no subject" do
    release!
    assert_empty catalog(@official)
  end

  test "released and approved: the official student sees the released map and the approved revision" do
    approve!
    release!
    view = catalog(@official).sole
    assert_equal [ :official, true, @course ], [ view.mode, view.released, view.course_revision ]
    assert_equal [ @topic, true ], [ view.topics.sole.topic_revision, view.topics.sole.approved ]
  end

  test "a course never released is not listed for an official student" do
    approve!
    assert_empty catalog(@official)
  end

  test "closing the course hides it again; the latest release decides" do
    approve!
    release!
    release!(open: false)
    view = catalog(@official).sole
    assert_equal [ false, [], nil ], [ view.released, view.topics, view.course_revision ]
    release!
    assert_equal 1, catalog(@official).size
  end

  test "the official student keeps the approved revision while a newer unapproved one exists; a newer approval replaces it" do
    approve!
    release!
    newer = make_topic(@lesson_revision, { NEW_SKILL => [ @item ] }, course: @course)
    assert_equal @topic, catalog(@official).sole.topics.sole.topic_revision
    assert_equal newer, catalog(@trial).sole.topics.sole.topic_revision
    approve!(newer)
    assert_equal newer, catalog(@official).sole.topics.sole.topic_revision
  end

  test "the official student sees the released map, not the latest one" do
    approve!
    release!
    build_course_map(skills: JSON.parse(@course.body_json)["skills"].map { |s| s.transform_keys(&:to_sym) },
                     topics: [ { key: KEY, kind: "lezione", title_it: "Titolo nuovo", skills: [ NEW_SKILL ], minutes: 45, term: 1, after: [] } ])
    assert_equal "Sistemi lineari", catalog(@official).sole.topics.sole.title_it
    assert_equal "Titolo nuovo", catalog(@trial).sole.topics.sole.title_it
  end

  test "a topic revision whose skills differ from the map's is not visible (trial and official)" do
    other_item = make_practice_item("math-c-2", "math.linear-equation-integer")
    wrong = make_topic(@lesson_revision, { "math.linear-equation-integer" => [ other_item ] }, course: @course)
    assert_empty catalog(@trial) # the latest revision is the wrong one
    approve!(wrong)
    release!
    assert_empty catalog(@official)
    approve!(@topic)
    assert_equal @topic, catalog(@official).sole.topics.sole.topic_revision # the latest approval whose skills match
  end

  test "only topics with a revision are listed, in the map's order" do
    skills = JSON.parse(@course.body_json)["skills"].map { |s| s.transform_keys(&:to_sym) }
    topics = [ { key: "lezione.math.nothing-yet", kind: "lezione", title_it: "Non ancora", skills: [ NEW_SKILL ], minutes: 20, term: 2, after: [] },
               { key: KEY, kind: "lezione", title_it: "Sistemi lineari", skills: [ NEW_SKILL ], minutes: 30, term: 1, after: [ "lezione.math.nothing-yet" ] } ]
    course = build_course_map(skills: skills, topics: topics)
    make_lesson("lezione.math.nothing-yet", skills: [ NEW_SKILL ])
    make_topic(@lesson_revision, { NEW_SKILL => [ @item ] }, course: course)
    view = catalog(@trial).sole
    assert_equal [ KEY ], view.topics.map(&:key)
    assert_equal [ "lezione.math.nothing-yet" ], view.topics.first.after
  end

  test "skills_without_topic: graph and map skills that no visible topic holds" do
    view = catalog(@trial).sole
    graph_keys = JSON.parse(@graph.body_json)["skills"].map { |s| s["key"] }
    assert_equal graph_keys.sort, view.skills_without_topic.sort
    assert_not_includes view.skills_without_topic, NEW_SKILL
  end

  test "the preview row and a missing student have no course" do
    preview = Student.create!(key: "preview", kind: "preview")
    assert_empty catalog(preview)
    assert_empty catalog(nil)
  end

  test "two subjects are listed in subject position order" do
    english = Subject.create!(key: "english", name_it: "Inglese", position: 0)
    graph = SkillGraphRevision.create!(subject: english, seq: 1, body_json: JSON.generate(ValidationFixtures::GRAPH))
    course = CourseRevision.create!(subject: english, seq: 1, skill_graph_revision: graph, warnings_json: "[]",
                                    body_json: JSON.generate(skills: [], topics: [ { key: "ripasso.english.verbs", kind: "ripasso", title_it: "Verbi", skills: [ "english.verbs" ], minutes: 20, term: 1, after: [] } ]))
    lesson_revision = make_lesson("ripasso.english.verbs", skills: [ "english.verbs" ])
    item = make_practice_item("eng-1", "english.verbs", subject: english)
    make_topic(lesson_revision, { "english.verbs" => [ item ] }, course: course)
    assert_equal %w[english math], catalog(@trial).map { |v| v.subject.key }
  end
end
