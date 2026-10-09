require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/topic_world"
require_relative "../support/practice_rows"

# Phase 1b, A10: the teacher's course page, topic page, practice trail and the home line. Read-only for the
# guest; the questions' text is the teacher's alone.
class TeacherCoursePagesTest < ActionDispatch::IntegrationTest
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
    @official = Student.official
    @trial = Student.create!(key: "prova-1", kind: "student")
  end

  def serve_and_try(student, index, raw:, verdict:, codes: [], at: Time.utc(2026, 11, 2, 8, 0))
    instance = @topic_items.first.instances.order(:id)[index]
    serve = make_serve(student, @topic, instance, skill_key: "math.number", at: at)
    make_try(serve, raw: raw, verdict: verdict, error_codes: codes, at: at + 60)
    serve
  end

  test "the course page lists the topics in order with their stage, the new skills with the programme line, and the release" do
    on(:web, "/teacher/subjects/math/course", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#course-summary", /1 argomento pronto per te · 0 approvati/
    assert_select "p.hint", /Mappa 1: 1 argomenti, 0 approvati/
    assert_select "li.topic[data-topic='#{TopicWorld::TOPIC_KEY}'][data-stage=awaiting_teacher]" do
      assert_select "a[href='/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}']"
    end
    assert_select "#course-skills article[data-skill='math.linear-system-substitution']", /metodo di sostituzione/
    assert_select "#course-skills", /sistemi lineari: metodo di sostituzione/
    assert_select "#course-release[data-open=false][data-releasable=false]"
    assert_select "#course-release li", /grafo approvato/
    assert_select "#course-open-form button[disabled]"
  end

  test "the course page offers the opening once the graph and a topic are approved, and the closing when open" do
    approve_graph_row!(@subject, @graph)
    Decision.create!(kind: "approve_topic", subject: @subject, request_id: SecureRandom.uuid, teacher_login: "nik", remote_addr: EDGE,
                     payload_json: { topic_revision_id: @topic.id, topic: TopicWorld::TOPIC_KEY, seq: 1 }.to_json)
    on(:web, "/teacher/subjects/math/course", headers: TEACHER, remote_addr: EDGE)
    assert_select "li.topic[data-stage=approved]"
    assert_select "#course-release[data-releasable=true]"
    assert_select "#course-open-form button:not([disabled])"
    decide("/teacher/subjects/math/course-release", { open: "1" })
    assert_response :success
    on(:web, "/teacher/subjects/math/course", headers: TEACHER, remote_addr: EDGE)
    assert_select "#course-close-form button:not([disabled])"
    assert_select "#course-open-form", 0
    assert_select "#course-summary[data-open=true]"
  end

  test "a missing topic page is 404, a topic in the map without a revision says it is missing" do
    on(:web, "/teacher/subjects/math/topics/ripasso.math.nothing", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
    lesson_revision_with_body!("ripasso.math.unwritten", "math.number")
    on(:web, "/teacher/subjects/math/topics/ripasso.math.unwritten", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#topic-missing"
  end

  test "the topic page shows the lesson review, a finding card with its form, and the gate reasons in Italian" do
    finding = { severity: "major", section: "solutions", exercise: 1, quote: "x = 3", problem_it: "Manca un passaggio.", fix_it: "Aggiungilo." }
    review_lesson!(@lesson_revision, findings: [ finding ], session: AgentSession.create!(label: "second", role: "reviewer", agent: "omp", model: "gpt-5.4"))
    on(:web, "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#topic-review [data-lesson-review]", 2
    assert_select "#step-findings [data-lesson-finding][data-severity=major]", /Manca un passaggio/
    assert_select "#topic-review", /Calcoli rifatti dal revisore: 1/
    assert_select "#topic-approve-form input[name=lesson_findings_reason_it]"
    assert_select "#lesson-send-back-form select[name=reason_code]"
    assert_select "#topic-approve-why", /Per ora non puoi approvare|Leggi tutta la pagina/
  end

  test "the practice page shows states, counts, typical errors, the trial student choice and the questions" do
    serve_and_try(@official, 0, raw: "2", verdict: "correct")
    serve_and_try(@official, 1, raw: "4", verdict: "typical_error", codes: [ "slip" ], at: Time.utc(2026, 11, 3, 8, 0))
    serve_and_try(@trial, 2, raw: "4", verdict: "correct")
    StudentQuestion.create!(student: @official, client_question_id: "q-1", topic_revision: @topic, section: "idea", text_it: "Non capisco la bilancia.")

    on(:web, "/teacher/subjects/math/practice", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#student-picker a[data-student=prova-1]"
    assert_select "section.topic-progress[data-topic='#{TopicWorld::TOPIC_KEY}'][data-status=in_progress]"
    assert_select "article.skill-progress[data-skill='math.number'][data-state=in_study]" do
      assert_select "p", /2 risposte in 2 esercizi/
      assert_select "ul.typical li[data-code=slip]", /Hai sbagliato un segno|slip/
    end
    assert_select "[data-question-text]", "Non capisco la bilancia."

    on(:web, "/teacher/subjects/math/practice?student=prova-1", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "article.skill-progress p", /1 risposte in 1 esercizi/
    assert_select "[data-question]", 0

    on(:web, "/teacher/subjects/math/practice?student=nobody", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
  end

  test "a guest reads the questions but not their text" do
    StudentQuestion.create!(student: @official, client_question_id: "q-2", topic_revision: @topic, exercise: 2, text_it: "Testo riservato.")
    on(:web, "/teacher/subjects/math/practice", headers: GUEST, remote_addr: EDGE)
    assert_response :success
    assert_select "[data-question]", 1
    assert_select "[data-question-text]", 0
    assert_select "[data-hidden-text]", /visibile solo all'insegnante/
    assert_no_match(/Testo riservato/, response.body)
  end

  test "the trail of a skill lists every try in time order, undetermined ones are marked to correct" do
    serve_and_try(@official, 0, raw: "2", verdict: "correct", at: Time.utc(2026, 11, 2, 8, 0))
    serve_and_try(@official, 1, raw: "xx", verdict: "typical_error", codes: [ "slip" ], at: Time.utc(2026, 11, 3, 8, 0))
    serve_and_try(@official, 3, raw: "???", verdict: "undetermined", at: Time.utc(2026, 11, 4, 8, 0))
    on(:web, "/teacher/subjects/math/practice/skills/math.number", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "li.trail-step", 3
    assert_select "li.trail-step:first-child [data-raw]", "2"
    assert_select "li.trail-step:first-child [data-outcome-label]", "Corretta"
    assert_select "li.trail-step:nth-child(2) [data-outcome-label]", /Errore/
    assert_select "li.trail-step[data-to-correct=true]", 1

    on(:web, "/teacher/subjects/math/practice/skills/math.nothing", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
  end

  test "the home shows the course line with the approved count and whether it is open" do
    on(:web, "/teacher", headers: TEACHER, remote_addr: EDGE)
    assert_select "li.subject[data-subject=math] [data-course-line]", /Corso: 0 approvati su 1 nella mappa · chiuso allo studente/
    assert_select "li.subject[data-subject=math] [data-course-line] a[href='/teacher/subjects/math/course']"
  end

  test "InstanceView carries the hints and the catalogue message of each declared error" do
    revision = @topic_items.first
    view = Teacher::InstanceView.new(revision.instances.order(:id).first, JSON.parse(revision.body_json), 1)
    assert_equal [ "Che cosa guardi prima?", "Quale regola usi?", "Fai il primo passaggio." ], view.hints
    assert_equal [ { code: "slip", value: "3", message: "Hai sbagliato un segno." } ], view.errors
    diagnosis = @world[:revisions]["number"]
    plain = Teacher::InstanceView.new(diagnosis.instances.order(:id).first, JSON.parse(diagnosis.body_json), 1)
    assert_empty plain.hints
  end
end
