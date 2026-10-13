require "test_helper"
require "rake"
require "minitest/mock"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/topic_world"
require_relative "../support/practice_rows"

# D-260: the operator's console attestation for approve_topic. The words waive exactly one requirement (the
# review page was opened, and the confirmation that goes with it); every other requirement of the gate holds.
class ConsoleAttestationTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include TopicWorld
  include PracticeRows

  WORDS = "Ho letto la lezione fuori dall'app."
  EVENT_KINDS = [ Approval::TopicGate::VIEW_KIND, Teacher::TopicSeen::LESSON_KIND, Teacher::TopicSeen::EXERCISE_KIND ].freeze

  setup do
    ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    build_topic_world
  end

  def attest(revision = @topic, words: WORDS, confirm: true, kind: "approve_topic", **extra)
    DecisionConsole.call(kind: kind, teacher: "nik", os_user: "operator", revision: revision.id, attest_it: words, confirm: confirm, **extra)
  end

  test "without the words the page-opened requirement still refuses" do
    result = DecisionConsole.call(kind: "approve_topic", teacher: "nik", os_user: "operator", revision: @topic.id, confirm: true)
    assert_not result.ok
    assert(result.errors.any? { |e| e.include?("was not opened") })
  end

  test "with the words the decision is recorded with the attestation and no page event" do
    assert_no_difference -> { AppEvent.where(kind: EVENT_KINDS).count } do
      assert_difference "Decision.where(kind: 'approve_topic').count", 1 do
        result = attest
        assert result.ok, result.errors.inspect
      end
    end
    payload = JSON.parse(Decision.where(kind: "approve_topic").last.payload_json)
    assert_equal true, payload["attested"]
    assert_equal WORDS, payload["attest_it"]
    assert_equal [ "topic_review_page_not_opened" ], payload["waived"]
    assert_equal "console", payload["via"]
    assert_equal @topic.id, Course::Decisions.approved_topic_revision_id(TopicWorld::TOPIC_KEY)
  end

  test "a dry run writes nothing" do
    assert_no_difference "Decision.count" do
      result = attest(confirm: false)
      assert result.ok
      assert_not result.recorded
      assert_equal true, result.payload["attested"]
    end
  end

  test "the words are required, non blank and at most 1000 characters" do
    [ "", "   ", "x" * 1001 ].each do |bad|
      assert_no_difference "Decision.count" do
        result = attest(words: bad)
        assert_not result.ok, bad.inspect
        assert(result.errors.any? { |e| e.include?("ATTEST_IT") })
      end
    end
    assert attest(words: "x" * 1000, confirm: false).ok
  end

  test "any other kind refuses the words" do
    assert_no_difference "Decision.count" do
      result = attest(kind: "approve_skill_graph", subject: "math")
      assert_not result.ok
      assert_includes result.errors.first, "only for approve_topic and approve_blueprint"
    end
  end

  test "the recorder itself refuses the words from a web request" do
    assert_raises(DecisionRecorder::Invalid) do
      DecisionRecorder.new(Object.new, "approve_topic", { revision_id: @topic.id, attest_it: WORDS }.with_indifferent_access).send(:attestation)
    end
  end

  test "every other requirement still refuses" do
    # not the latest revision
    newer = make_topic(@lesson_revision, { "math.number" => @topic_items }, course: @topic.course_revision)
    result = attest(@topic)
    assert_not result.ok
    assert(result.errors.any? { |e| e.include?("not the latest") })
    assert attest(newer, confirm: false).ok

    # no independent review of the lesson, a stale lesson pin
    fresh = make_topic(lesson_revision_with_body!("ripasso.math.fresh", "math.number"), { "math.number" => [ make_practice_item("fresh-1", "math.number"), make_practice_item("fresh-2", "math.number") ] },
                       course: newer.course_revision)
    result = attest(fresh)
    assert_not result.ok
    assert(result.errors.any? { |e| e.include?("no review by an independent session") })

    # render check, lesson sent back
    LessonRenders.stub(:gate_reason, "the lesson revision has no render check") do
      assert(attest(newer, confirm: false).errors.any? { |e| e.include?("render check") })
    end
    Course::Decisions.stub(:lesson_sent_back?, true) do
      assert(attest(newer, confirm: false).errors.any? { |e| e.include?("sent the lesson revision back") })
    end

    # an item that is no longer approvable
    Review::Gate.stub(:check, Review::Gate::Result.new(approvable: false, reasons: [ "no blind solve" ])) do
      assert(attest(newer, confirm: false).errors.any? { |e| e.include?("is not approvable") })
    end

    # a stale lesson pin
    LessonRevision.create!(lesson: @lesson_revision.lesson, seq: @lesson_revision.seq + 1, source_md: @lesson_revision.source_md, source_sha256: "0" * 64,
                           body_json: @lesson_revision.body_json, rules_version: @lesson_revision.rules_version, warnings_json: "[]")
    assert(attest(newer, confirm: false).errors.any? { |e| e.include?("is not the newest revision of its lesson") })
    assert_empty Decision.where(kind: "approve_topic")
  end

  test "blocker or major findings still need the operator's reason" do
    finding = { severity: "major", section: "solutions", exercise: 1, quote: "x = 3", problem_it: "Manca un passaggio.", fix_it: "Aggiungilo." }
    other = make_lesson_world_with_findings([ finding ])
    result = attest(other)
    assert_not result.ok
    assert(result.errors.any? { |e| e.include?("a reason is required") })
    result = attest(other, params: { lesson_findings_reason_it: "Approvo nonostante i rilievi perché il passaggio è nell'esempio." })
    assert result.ok, result.errors.inspect
  end

  test "the web path ignores the attestation and still wants the page opened" do
    assert_no_difference "Decision.count" do
      decide("/teacher/topic-revisions/#{@topic.id}/approve", { confirm_seen: "1", attest_it: WORDS, attested: true, waived: [ "topic_review_page_not_opened" ] })
    end
    assert_response :unprocessable_entity
    assert json["reasons"].any? { |r| r.include?("was not opened") }

    record_viewed!
    decide("/teacher/topic-revisions/#{@topic.id}/approve", { confirm_seen: "1", attest_it: WORDS })
    assert_response :success
    payload = JSON.parse(Decision.where(kind: "approve_topic").last.payload_json)
    assert_not payload.key?("attested")
    assert_not payload.key?("attest_it")
    assert_not payload.key?("waived")
  end

  test "the topic page and the course path say it was approved from the console, with the words" do
    attest
    line = "Approvato da console, senza aprire la pagina di revisione: «#{WORDS}»"
    open_topic_page!(headers: TEACHER)
    assert_response :success
    assert_select "#topic-attested", line
    on(:web, "/teacher/subjects/math/course", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select ".step-attested", line
  end

  test "an ordinary approval shows no such line" do
    record_viewed!
    DecisionConsole.call(kind: "approve_topic", teacher: "nik", os_user: "operator", revision: @topic.id, params: { confirm_seen: "1" }, confirm: true)
    open_topic_page!(headers: TEACHER)
    assert_select "#topic-attested", false
  end

  test "the rake task passes ATTEST_IT" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("banco:decide")
    saved = ENV.to_h.slice("KIND", "TEACHER", "REVISION", "ATTEST_IT", "CONFIRM")
    ENV.update("KIND" => "approve_topic", "TEACHER" => "nik", "REVISION" => @topic.id.to_s, "ATTEST_IT" => WORDS, "CONFIRM" => "1")
    Rake::Task["banco:decide"].reenable
    assert_difference "Decision.where(kind: 'approve_topic').count", 1 do
      capture_io { Rake::Task["banco:decide"].invoke }
    end
  ensure
    %w[KIND TEACHER REVISION ATTEST_IT CONFIRM].each { |k| saved&.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  def make_lesson_world_with_findings(findings)
    skill = "math.number"
    key = "ripasso.math.findings"
    lesson_rev = lesson_revision_with_body!(key, skill)
    review_lesson!(lesson_rev, findings: findings)
    items = Array.new(2) { |i| make_practice_item("findings-#{i + 1}", skill, subject: @subject, instances: 6) }
    items.each { |r| work_item!(r) }
    map = build_course_map(subject: @subject, topics: [ { key: TopicWorld::TOPIC_KEY, kind: "ripasso", title_it: "Ripasso di prova", skills: [ skill ], minutes: 30, term: 1, after: [] },
                                                        { key: key, kind: "ripasso", title_it: "Altro", skills: [ skill ], minutes: 20, term: nil, after: [] } ])
    make_topic(lesson_rev, { skill => items }, course: map)
  end
end
