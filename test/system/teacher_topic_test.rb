require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/student_session"
require_relative "../support/topic_world"

# A topic from "tocca a te" to approved in Chrome: the lesson drawn with the student's renderer, the samples,
# the approval that needs the confirmation, then the course opened to the student.
class TeacherTopicTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession
  include TopicWorld

  setup do
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  test "read the topic, confirm, approve, then open the course" do
    visit "/teacher"
    assert_selector "[data-course-line]", text: "Corso: 0 approvati su 1 nella mappa · chiuso allo studente"
    click_link "Corso: 0 approvati su 1 nella mappa · chiuso allo studente"
    assert_selector "li.topic[data-stage=awaiting_teacher]"
    click_link "Ripasso di prova"

    # The lesson is drawn with the student's renderer: bold, a list, no raw markup.
    assert_selector "#lesson-text strong", text: "bilancia"
    assert_selector "#lesson-text [data-section=mistakes] ul li", text: "Dimenticare il segno."
    assert_no_text "**bilancia**"
    assert_selector ".exercise-card", count: 2

    assert_selector "#step-approve[data-approvable=true]"
    assert_selector "#topic-approve-button[disabled]"
    click_button "Ho letto la lezione"
    all("[data-seen-button]").each(&:click)
    assert_selector "#topic-approve-button:not([disabled])"
    check "topic-confirm-seen"
    click_button "Approva l'argomento"
    assert_selector ".flash", text: "Argomento approvato."
    assert_selector "#topic-summary[data-approved=true]"
    assert_equal 1, Decision.where(kind: "approve_topic").count

    approve_graph_row!(@subject, @graph)
    visit "/teacher/subjects/math/course"
    click_button "Apri il corso allo studente"
    assert_selector ".flash", text: "Apertura del corso registrata."
    assert_selector "#course-summary[data-open=true]"
  end
end
