require "test_helper"
require_relative "../support/course_rows"
require_relative "../support/practice_rows"

# The ten Phase 1b tables (A7): constraints in the database, and the two test helpers.
class CourseTablesTest < ActiveSupport::TestCase
  include CourseRows
  include PracticeRows

  setup do
    build_course
    @student = practice_student
    @lesson_revision = make_lesson("ripasso.math.demo")
    @item_revision = make_practice_item("math-p-1", "math.linear-equation-integer")
    @topic = make_topic(@lesson_revision, { "math.linear-equation-integer" => [ @item_revision ] })
    @instance = @item_revision.instances.first
    @serve = make_serve(@student, @topic, @instance, skill_key: "math.linear-equation-integer")
  end

  def refused(message_part = nil, &block)
    error = assert_raises(ActiveRecord::StatementInvalid, ActiveRecord::RecordNotUnique, &block)
    assert_match(/#{message_part}/i, error.message) if message_part
  end

  test "the helpers build a coherent course" do
    assert_equal @topic.lesson, @lesson_revision.lesson
    assert_equal "practice_item", @item_revision.item.kind
    assert_equal 12, @instance.item_revision.instances.count
    assert_equal [ @item_revision.id ], JSON.parse(@topic.body_json)["practice"].first["items"].map { |i| i["revision"] }
    assert_equal 1, CourseRevision.where(subject: @subject).count
    second = make_lesson("ripasso.math.demo")
    assert_equal [ 1, 2 ], second.lesson.revisions.order(:seq).pluck(:seq)
  end

  test "a lesson key is unique and its kind is one of three" do
    refused("unique") { Lesson.create!(subject: @subject, key: "ripasso.math.demo", kind: "ripasso") }
    refused("check") { Lesson.create!(subject: @subject, key: "ripasso.math.other", kind: "corso") }
  end

  test "revisions are unique per lesson and per subject; sha256 has 64 characters" do
    refused("unique") { LessonRevision.create!(lesson: @lesson_revision.lesson, seq: 1, source_md: "x", source_sha256: "a" * 64, body_json: "{}", rules_version: "7", warnings_json: "[]") }
    refused("check") { LessonRevision.create!(lesson: @lesson_revision.lesson, seq: 9, source_md: "x", source_sha256: "short", body_json: "{}", rules_version: "7", warnings_json: "[]") }
    course = CourseRevision.first
    refused("unique") { CourseRevision.create!(subject: @subject, seq: course.seq, skill_graph_revision: @graph, body_json: "{}", warnings_json: "[]") }
    refused("unique") { TopicRevision.create!(lesson: @topic.lesson, seq: 1, course_revision: course, lesson_revision: @lesson_revision, body_json: "{}") }
  end

  test "one lesson review per session and revision" do
    session = AgentSession.create!(label: "r", role: "reviewer")
    LessonReview.create!(lesson_revision: @lesson_revision, agent_session: session, checklist_json: "[]", recomputed_json: "[]", findings_json: "[]")
    refused("unique") { LessonReview.create!(lesson_revision: @lesson_revision, agent_session: session, checklist_json: "[]", recomputed_json: "[]", findings_json: "[]") }
  end

  test "a serve: reasons, error code only with prova_questo, a parent for prova_questo and after_solution" do
    refused("check") { make_serve(@student, @topic, @instance, skill_key: "s", reason: "again") }
    refused("check") { make_serve(@student, @topic, @instance, skill_key: "s", reason: "prova_questo", parent: @serve) }
    refused("check") { make_serve(@student, @topic, @instance, skill_key: "s", reason: "next", error_code: "slip") }
    refused("check") { make_serve(@student, @topic, @instance, skill_key: "s", reason: "prova_questo", error_code: "slip") }
    refused("check") { make_serve(@student, @topic, @instance, skill_key: "s", reason: "after_solution") }
    assert make_serve(@student, @topic, @instance, skill_key: "s", reason: "prova_questo", parent: @serve, error_code: "slip").persisted?
    assert make_serve(@student, @topic, @instance, skill_key: "s", reason: "after_solution", parent: @serve).persisted?
    assert make_serve(@student, @topic, @instance, skill_key: "s", reason: "reseen").persisted?
  end

  test "a try: number 1 to 3, unique per serve, a unique client id, a known source" do
    make_try(@serve, try_number: 1)
    refused("unique") { make_try(@serve, try_number: 1) }
    refused("check") { make_try(@serve, try_number: 4) }
    refused("check") { make_try(@serve, try_number: 0) }
    refused("check") { make_try(@serve, try_number: 2, source: "voice") }
    refused("check") { make_try(@serve, try_number: 2, hints_before: -1) }
    assert_equal 2, make_try(@serve, try_number: 2).try_number
    attempt = PracticeAttempt.first
    refused("unique") do
      PracticeAttempt.create!(student: @student, practice_serve: make_serve(@student, @topic, @instance, skill_key: "s"), try_number: 1,
                              client_attempt_id: attempt.client_attempt_id, raw: "1", source: "text", hints_before: 0, aided: false, answered_at: Time.current)
    end
  end

  test "gradings are numbered per attempt; method and source are restricted" do
    attempt = make_try(@serve)
    refused("unique") { PracticeGrading.create!(practice_attempt: attempt, seq: 1, verdict: "correct", grader: "closed", grader_version: "x", source: "sync") }
    refused("check") { PracticeGrading.create!(practice_attempt: attempt, seq: 2, verdict: "correct", grader: "closed", grader_version: "x", source: "async") }
    refused("check") { PracticeGrading.create!(practice_attempt: attempt, seq: 2, verdict: "correct", method: "guess", grader: "closed", grader_version: "x", source: "retry") }
    assert PracticeGrading.create!(practice_attempt: attempt, seq: 2, verdict: "wrong", grader: "closed", grader_version: "x", source: "retry").persisted?
  end

  test "events: hints and solutions need a serve, lesson events need a lesson and a topic revision" do
    refused("check") { PracticeEvent.create!(student: @student, kind: "hint_shown", payload_json: "{}", at: Time.current) }
    refused("check") { PracticeEvent.create!(student: @student, kind: "solution_shown", payload_json: "{}", at: Time.current) }
    refused("check") { PracticeEvent.create!(student: @student, kind: "lesson_opened", payload_json: "{}", at: Time.current, lesson_revision: @lesson_revision) }
    refused("check") { PracticeEvent.create!(student: @student, kind: "lesson_solution_shown", payload_json: "{}", at: Time.current, topic_revision: @topic) }
    refused("check") { PracticeEvent.create!(student: @student, kind: "chat", payload_json: "{}", at: Time.current) }
    assert make_practice_event(@student, "hint_shown", serve: @serve, payload: { n: 1, auto: false }).persisted?
    assert make_practice_event(@student, "lesson_opened", topic_revision: @topic, lesson_revision: @lesson_revision).persisted?
  end

  test "questions: a unique client id, a known section, at most 300 characters" do
    StudentQuestion.create!(student: @student, client_question_id: "q-1", section: "example", exercise: 2, text_it: "Perche?")
    refused("unique") { StudentQuestion.create!(student: @student, client_question_id: "q-1") }
    refused("check") { StudentQuestion.create!(student: @student, client_question_id: "q-2", section: "intro") }
    refused("check") { StudentQuestion.create!(student: @student, client_question_id: "q-3", text_it: "x" * 301) }
    refused("check") { StudentQuestion.create!(student: @student, client_question_id: "q-4", text_it: "") }
    assert StudentQuestion.create!(student: @student, client_question_id: "q-5").persisted?
  end

  test "the new tables refuse update and delete" do
    attempt = make_try(@serve)
    [ @lesson_revision.lesson, @lesson_revision, @topic, @serve, attempt ].each do |row|
      refused("append-only") { row.class.where(id: row.id).update_all(created_at: 1.day.ago) }
      refused("append-only") { row.class.where(id: row.id).delete_all }
    end
  end
end
