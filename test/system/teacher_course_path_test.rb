require "application_system_test_case"
require_relative "../support/student_session"
require_relative "../support/course_path_world"

# D-241 in Chrome: from the path to the approval through the four steps, with the student's own templates drawing the
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
    assert_selector ".exercise-card .q-render input[disabled]", count: 3, wait: 20
    # the other three samples of an exercise are folded and drawn when they are opened
    first(".exercise-card details.other-samples summary").click
    assert_selector ".exercise-card details.other-samples[open] .q-render input[disabled]", count: 3, wait: 20
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

  test "the link in the progress bar jumps to the approval step" do
    visit "/teacher/subjects/math/topics/#{CoursePathWorld::READY}"
    assert_selector "#step-lesson"
    click_link "Vai ad Approva"
    sleep 0.3
    top = page.evaluate_script("document.getElementById('step-approve').getBoundingClientRect().top")
    assert_operator top, :<, 400
  end

  test "on a phone the progress bar does not cover the text and the steps stack; on a desktop it stays on top (D-380)" do
    page.driver.resize(390, 844)
    visit "/teacher/subjects/math/topics/#{CoursePathWorld::READY}"
    assert_selector "#step-lesson"
    width, window = page.evaluate_script("[document.documentElement.scrollWidth, window.innerWidth]")
    assert_operator width, :<=, 390, "the page scrolls sideways (#{width} px in a #{window} px window)"
    bar = page.evaluate_script("(() => { const e = document.getElementById('review-progress'); return [getComputedStyle(e).position, e.getBoundingClientRect().height]; })()")
    assert(bar[0] != "sticky" || bar[1] < 120, "the bar is #{bar[1].round} px tall and sticky: it covers the text of a phone")
    page.execute_script("window.scrollTo(0, 1500)")
    top = page.evaluate_script("document.getElementById('review-progress').getBoundingClientRect().top")
    assert_operator top, :<, 0, "the bar scrolled away with the text" unless bar[0] == "sticky"
    lesson = page.evaluate_script("document.getElementById('lesson-text').getBoundingClientRect().left")
    aside = page.evaluate_script("document.querySelector('.lesson-review').getBoundingClientRect().left")
    assert_in_delta lesson, aside, 4, "the review sits below the lesson"
  ensure
    page.driver.resize(1280, 900)
  end

  test "on a phone the «i» button of an exercise is no taller than a line of text, so it does not ride over the line above (D-380)" do
    page.driver.resize(390, 844)
    visit "/teacher/subjects/math/topics/#{CoursePathWorld::READY}"
    assert_selector ".exercise-meta .ref-info", minimum: 1
    sizes = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('.exercise-meta .ref-info')).map((b) => [b.getBoundingClientRect().height, parseFloat(getComputedStyle(b.closest('.exercise-meta')).lineHeight)])
    JS
    sizes.each { |height, line| assert_operator height, :<=, line + 1, "the button is #{height.round} px in a #{line.round} px line" }
    target = page.evaluate_script("(() => { const b = document.querySelector('.exercise-meta .ref-info'); return getComputedStyle(b, '::before').position; })()")
    assert_equal "absolute", target, "the hit area stays larger than the button"
  ensure
    page.driver.resize(1280, 900)
  end

  test "on a desktop the progress bar stays on top while the page scrolls (D-380)" do
    visit "/teacher/subjects/math/topics/#{CoursePathWorld::READY}"
    assert_selector "#step-lesson"
    assert_equal "sticky", page.evaluate_script("getComputedStyle(document.getElementById('review-progress')).position")
  end
end
