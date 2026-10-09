require "application_system_test_case"
require_relative "../support/student_session"
require_relative "../support/course_path_world"

# D-240 in Chrome: from the path to the approval through the four steps, with the student's own templates drawing the
# samples, and no policy violation.
class TeacherCoursePathSystemTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession
  include CoursePathWorld

  setup do
    build_course_path_world
    dispose_finding!(path_finding!(@ready_items.first))
    lesson = path_lesson!("ripasso.math.more-numbers", "math.number", reviewed: true)
    course = build_course_map(subject: @subject, topics: CoursePathWorld::PATH_TOPICS + [ { key: "ripasso.math.more-numbers", kind: "ripasso", title_it: "Ancora numeri", skills: [ "math.number" ], minutes: 20, term: 1, after: [] } ])
    make_topic(lesson, { "math.number" => [ path_item!("more-numbers-1", "math.number", 1) ] }, course: course)
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  test "the path, the four steps with their done states, the approval and the next topic" do
    page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source:
      "window.__csp = []; document.addEventListener('securitypolicyviolation', e => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI));")
    visit "/teacher/subjects/math/course"
    assert_selector "#course-summary", text: "2 argomenti pronti per te"
    click_link "Solo quelli pronti per te"
    assert_selector "ol.path > li", count: 2
    first("a[data-review-button]").click

    assert_selector "#review-progress progress[value='1']"
    # the lesson as S sees it
    assert_selector "#lesson-text strong", text: "bilancia"
    assert_no_text "**bilancia**"
    assert_selector "#lesson-text .katex", minimum: 1
    # the samples are drawn by the student's templates and switched off
    assert_selector ".exercise-card .q-render input[disabled]", minimum: 4, wait: 20
    assert_selector "#topic-approve-button[disabled]"

    click_button "Ho letto la lezione"
    assert_selector "#step-lesson[data-done=true] [data-step-state]", text: "Fatto"
    assert_selector "#review-progress progress[value='2']"
    assert_selector "#topic-approve-button[disabled]"

    all("[data-seen-button]").each(&:click)
    assert_selector "#step-exercises[data-done=true]"
    assert_selector ".exercise-card[data-seen=true]", count: 3
    assert_selector "#review-progress progress[value='3']"
    assert_selector "#topic-approve-button:not([disabled])"
    assert_equal 1, AppEvent.where(kind: "teacher_read_lesson").count
    assert_equal 3, AppEvent.where(kind: "teacher_saw_exercise").count

    check "topic-confirm-seen"
    click_button "Approva l'argomento"
    assert_selector ".flash", text: "Argomento approvato."
    assert_selector "#step-approve[data-done=true]"
    assert_selector "#review-progress progress[value='4']"
    assert_selector "#next-topic a", text: "Ancora numeri"
    assert_equal [], page.evaluate_script("window.__csp")
    assert_equal 1, Decision.where(kind: "approve_topic").where("payload_json LIKE ?", "%#{CoursePathWorld::READY}%").count
  end

  test "the progress bar stays visible on a phone and the steps stack" do
    page.driver.resize(390, 844)
    visit "/teacher/subjects/math/topics/#{CoursePathWorld::READY}"
    assert_selector "#step-lesson"
    page.execute_script("window.scrollTo(0, 1500)")
    top = page.evaluate_script("document.getElementById('review-progress').getBoundingClientRect().top")
    assert_in_delta 0, top, 2
    lesson = page.evaluate_script("document.getElementById('lesson-text').getBoundingClientRect().left")
    aside = page.evaluate_script("document.querySelector('.lesson-review').getBoundingClientRect().left")
    assert_in_delta lesson, aside, 4, "the review sits below the lesson"
  end
end
