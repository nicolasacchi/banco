require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/topic_world"
require_relative "../support/practice_rows"

# Phase 1b, A6.1: approve_topic, send_back_lesson and release_course are decisions of the teacher in the
# browser. Each is refused without the flag, for a guest, without CSRF, from the student's device and on the
# API and harness listeners; the gate says in Italian what is missing; an approved topic is what the official
# student sees once the course is released.
class TopicDecisionsTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include TopicWorld
  include PracticeRows

  setup do
    ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world
  end

  def approve_path(topic = @topic) = "/teacher/topic-revisions/#{topic.id}/approve"
  def approve_params = { confirm_seen: "1" }

  test "the gate lists what is missing, in order, and opens when everything holds" do
    fresh = make_topic(lesson_revision_with_body!("ripasso.math.fresh", "math.number"), { "math.number" => [ make_practice_item("fresh-1", "math.number"), make_practice_item("fresh-2", "math.number") ] },
                       course: @topic.course_revision)
    reasons = Approval::TopicGate.check(fresh).reasons
    assert(reasons.any? { |r| r.include?("is not in the latest course map") })
    assert_includes reasons, "the lesson revision has no review by an independent session"
    assert(reasons.any? { |r| r.include?("is not approvable") })
    assert_includes reasons.last, "did not confirm"
    assert Approval::TopicGate.mechanical(@topic).reasons.any? { |r| r.include?("was not opened") }

    record_viewed!
    assert Approval::TopicGate.mechanical(@topic).approvable
    assert Approval::TopicGate.check(@topic, confirm_seen: true).approvable
    refute Approval::TopicGate.check(@topic, confirm_seen: false).approvable
  end

  test "a banco.lesson/2 lesson is not approvable until the lesson pages read it (R1 guard)" do
    record_viewed!
    assert Approval::TopicGate.mechanical(@topic).approvable
    lesson = @topic.lesson_revision
    lesson.define_singleton_method(:body) { super().merge("schema" => "banco.lesson/2") }
    @topic.define_singleton_method(:lesson_revision) { lesson }
    assert_includes Approval::TopicGate.mechanical(@topic).reasons, Approval::TopicGate::LESSON2_PAGES
  end

  test "the topic page opens by the teacher is recorded, a guest's is not, and it shows samples with hints, messages and solutions" do
    assert_no_difference "AppEvent.count" do
      open_topic_page!(headers: GUEST)
    end
    assert_response :success
    assert_difference "AppEvent.where(kind: 'teacher_viewed_topic').count", 1 do
      open_topic_page!(headers: TEACHER)
    end
    assert_response :success
    assert_no_difference "AppEvent.count" do
      open_topic_page!(headers: TEACHER)
    end
    assert_select "#topic-lesson [data-lesson-markup]", minimum: 6
    assert_select "[data-solution]", 2
    assert_select ".exercise-card [data-presentation]", 8
    assert_select ".exercise-card details[data-more=hints] ol[data-hints] li", 24
    assert_select ".exercise-card details[data-more=errors]", /Hai sbagliato un segno/
    assert_select ".exercise-card details[data-more=solution] ol.steps li"
    assert_select "#topic-lesson [data-final]", "x = 3"
    assert_select "form.decide[action='/teacher/topic-revisions/#{@topic.id}/approve']"
    assert_select "#step-approve[data-approvable=true]"
  end

  test "approving a topic end to end: read the page, confirm, approve; the official student sees it once the course is released" do
    open_topic_page!(headers: TEACHER)
    decide(approve_path, {})
    assert_response :unprocessable_entity
    assert json["reasons"].any? { |r| r.include?("did not confirm") }

    assert_difference "Decision.where(kind: 'approve_topic').count", 1 do
      decide(approve_path, approve_params)
    end
    assert_response :success
    decision = Decision.where(kind: "approve_topic").last
    assert_equal @subject, decision.subject
    assert_equal "nik", decision.teacher_login
    payload = JSON.parse(decision.payload_json)
    assert_equal [ @topic.id, TopicWorld::TOPIC_KEY, 1, @topic.course_revision_id, @topic.lesson_revision_id ],
                 payload.values_at("topic_revision_id", "topic", "seq", "course_revision_id", "lesson_revision_id")
    assert_equal @topic_items.map(&:id), payload["item_revision_ids"]
    assert_not payload.key?("lesson_findings_reason_it")

    student = Student.official
    assert_empty Course::Catalog.for(student), "the official student sees nothing before release_course"
    approve_graph_row!(@subject, @graph)
    decide("/teacher/subjects/math/course-release", { open: "1" })
    assert_response :success
    release = JSON.parse(Decision.where(kind: "release_course").last.payload_json)
    assert_equal({ "subject" => "math", "open" => true, "course_revision_id" => @topic.course_revision_id }, release)
    view = Course::Catalog.for(student).first
    assert_equal [ TopicWorld::TOPIC_KEY ], view.topics.map(&:key)
    assert view.released

    decide("/teacher/subjects/math/course-release", { open: "0" })
    assert_response :success
    assert_nil Course::State.released_revision_id(@subject)
    assert_not Course::Catalog.for(student).first.released
  end

  test "an approval needs the latest topic revision, and a form post comes back with a sentence in Italian" do
    record_viewed!
    newer = make_topic(@lesson_revision, { "math.number" => @topic_items }, course: @topic.course_revision)
    decide(approve_path, approve_params)
    assert_response :unprocessable_entity
    assert_empty Decision.where(kind: "approve_topic")

    token = csrf_token
    on(:web, approve_path(newer), method: :post, headers: TEACHER.merge("X-CSRF-Token" => token), params: { back: "/teacher/subjects/math/course" }, remote_addr: EDGE)
    assert_redirected_to "/teacher/subjects/math/course"
    assert_match(/Apri la pagina dell'argomento/, flash[:alert])
    assert_match(/Conferma di aver letto/, flash[:alert])
  end

  test "review findings of blocker or major severity need the teacher's reason" do
    finding = { severity: "major", section: "solutions", exercise: 1, quote: "x = 3", problem_it: "Manca un passaggio.", fix_it: "Aggiungilo." }
    other = make_lesson_world_with_findings([ finding ])
    record_viewed!(other)
    decide(approve_path(other), approve_params)
    assert_response :unprocessable_entity
    assert json["reasons"].any? { |r| r.include?("a reason is required") }
    decide(approve_path(other), approve_params.merge(lesson_findings_reason_it: "ab"))
    assert_response :unprocessable_entity

    decide(approve_path(other), approve_params.merge(lesson_findings_reason_it: "Approvo nonostante i rilievi perché il passaggio è nell'esempio."))
    assert_response :success
    assert_equal "Approvo nonostante i rilievi perché il passaggio è nell'esempio.", JSON.parse(Decision.where(kind: "approve_topic").last.payload_json)["lesson_findings_reason_it"]
  end

  def make_lesson_world_with_findings(findings)
    skill = "math.number"
    key = "ripasso.math.graver"
    lesson = lesson_revision_with_body!(key, skill)
    review_lesson!(lesson, findings: findings)
    items = Array.new(2) { |i| make_practice_item("graver-#{i}", skill, instances: 6).tap { |r| work_item!(r) } }
    map = build_course_map(subject: @subject, topics: [ { key: key, kind: "ripasso", title_it: "Altro", skills: [ skill ], minutes: 20, term: nil, after: [] },
                                                        { key: TopicWorld::TOPIC_KEY, kind: "ripasso", title_it: "Ripasso di prova", skills: [ skill ], minutes: 30, term: 1, after: [] } ])
    make_topic(lesson, { skill => items }, course: map)
  end

  test "send_back_lesson records the comment and blocks the next approval, not the current one" do
    record_viewed!
    decide("/teacher/lesson-revisions/#{@lesson_revision.id}/send-back", { reason_code: "nonsense", comment_it: "Troppo difficile." })
    assert_response :unprocessable_entity
    decide("/teacher/lesson-revisions/#{@lesson_revision.id}/send-back", { reason_code: "too_hard", comment_it: "no" })
    assert_response :unprocessable_entity
    decide("/teacher/lesson-revisions/999999/send-back", { reason_code: "too_hard", comment_it: "Troppo difficile." })
    assert_response :not_found

    decide("/teacher/lesson-revisions/#{@lesson_revision.id}/send-back", { reason_code: "too_hard", comment_it: "Troppo difficile." })
    assert_response :success
    payload = JSON.parse(Decision.where(kind: "send_back_lesson").last.payload_json)
    assert_equal({ "lesson_revision_id" => @lesson_revision.id, "lesson" => TopicWorld::TOPIC_KEY, "seq" => 1, "reason_code" => "too_hard", "comment_it" => "Troppo difficile." }, payload)
    decide(approve_path, approve_params)
    assert_response :unprocessable_entity
    assert json["reasons"].any? { |r| r.include?("sent the lesson revision back") }
    assert_equal "Hai rimandato questa lezione: serve una versione nuova.", Teacher::Wording.italian("the teacher sent the lesson revision back")
  end

  test "release_course needs the approved graph and an approved topic, and closing needs an open course" do
    decide("/teacher/subjects/math/course-release", { open: "1" })
    assert_response :unprocessable_entity
    assert json["reasons"].any? { |r| r.include?("approved graph") }
    assert json["reasons"].any? { |r| r.include?("no topic of the course map is approved") }
    decide("/teacher/subjects/math/course-release", { open: "0" })
    assert_response :unprocessable_entity
    decide("/teacher/subjects/math/course-release", { open: "maybe" })
    assert_response :unprocessable_entity
    decide("/teacher/subjects/nothing/course-release", { open: "1" })
    assert_response :not_found
    assert_empty Decision.where(kind: "release_course")

    record_viewed!
    decide(approve_path, approve_params)
    assert_response :success
    decide("/teacher/subjects/math/course-release", { open: "1" })
    assert_response :unprocessable_entity
    assert_equal 1, json["reasons"].size, "the approved topic is enough, the graph is not approved yet"
    approve_graph_row!(@subject, @graph)
    decide("/teacher/subjects/math/course-release", { open: "1" })
    assert_response :success
    assert_equal Student.official, Decision.where(kind: "release_course").last.student
    decide("/teacher/subjects/math/course-release", { open: "1" })
    assert_response :unprocessable_entity
  end

  test "a trial student sees the draft, the official student sees nothing without release" do
    trial = Student.create!(key: "prova-1", kind: "student")
    view = Course::Catalog.for(trial).first
    assert_not view.topics.first.approved
    assert_empty Course::Catalog.for(Student.official)
  end

  def kinds
    record_viewed!
    {
      "approve_topic" => [ approve_path, approve_params ],
      "send_back_lesson" => [ "/teacher/lesson-revisions/#{@lesson_revision.id}/send-back", { reason_code: "too_hard", comment_it: "Troppo difficile." } ],
      "release_course" => [ "/teacher/subjects/math/course-release", { open: "0" } ]
    }
  end

  test "every new kind is refused without the flag, for a guest, without CSRF, from the student's device, and a 404 on the API and harness listeners" do
    approve_graph_row!(@subject, @graph)
    Decision.create!(kind: "release_course", subject: @subject, payload_json: { subject: "math", open: true, course_revision_id: @topic.course_revision_id }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE)
    kinds.each do |kind, (path, params)|
      assert_no_difference "Decision.count", kind do
        %i[api harness].each { |listener| decide(path, params, listener: listener); assert_response :not_found, "#{kind} #{listener}" }
        decide(path, params, headers: GUEST); assert_response :forbidden, "#{kind} guest"
        decide(path, params, csrf: false); assert_response :forbidden, "#{kind} csrf"
        decide(path, params, headers: TEACHER.merge("Cookie" => "banco_device=1")); assert_response :forbidden, "#{kind} device"
        decide(path, params, headers: OFFICIAL); assert_response :forbidden, "#{kind} student"
        ENV["BANCO_DECISIONS_ENABLED"] = "0"
        decide(path, params); assert_response :forbidden, "#{kind} flag"
        ENV["BANCO_DECISIONS_ENABLED"] = "1"
      end
    end
    kinds.each do |kind, (path, params)|
      assert_difference "Decision.where(kind: '#{kind}').count", 1, kind do
        decide(path, params)
        assert_response :success, kind
      end
    end
  end

  test "no API route writes a decision of these kinds" do
    paths = Rails.application.routes.routes.map { |r| r.path.spec.to_s }.grep(%r{\Aapi/v1|\A/api/v1})
    assert_empty paths.grep(/approve|send-back|release/)
  end
end
