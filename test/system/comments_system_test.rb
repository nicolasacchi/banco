require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# D-304 in Chrome: the student taps «Commenta», picks a place, takes a reason, writes and sends. On a lesson card the
# comment names the card; in a sitting the counted time stops while the box is open and the comment names the
# served event, and the question can still be answered afterwards.
class CommentsSystemTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  setup { sign_in_as :student }
  teardown { sign_out_env }

  def wait_until(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (value = yield)
      flunk "not true within #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    value
  end

  def write_comment(reason:, text:)
    assert_selector "#comment-box[open]", wait: 10
    choose reason
    fill_in "comment-text", with: text
    find("#comment-send").click
    assert_no_selector "#comment-box[open]", wait: 10
  end

  test "a student comments on a lesson card: pick the card, a reason, a text" do
    build_student_world(approve: true, release: true)
    card, = find_block { |_, b| b["type"] == "check" && b["component"] == "number" }
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#scheda-#{card}"
    wait_for_lesson_ready(wait: 20)
    assert_selector "article.l2-card[data-comment-anchor='card:#{card}']", wait: 10
    find(".l2-commentbtn").click # the lesson hides the student menu: its own bar carries the control
    assert_selector "#comment-banner", visible: :visible
    assert_equal "true", page.evaluate_script("document.body.classList.contains('comment-mode')").to_s
    find("article.l2-card[data-comment-anchor='card:#{card}'] .card-head").click
    assert_selector "#comment-box[open]", wait: 10
    assert_selector "#comment-where option", minimum: 2
    write_comment(reason: "Non capisco", text: "Il secondo passaggio non mi torna.")
    wait_until { Comment.count == 1 }
    c = Comment.last
    assert_equal [ "not_understood", "lesson", card, @lesson_revision.id, "Il secondo passaggio non mi torna." ],
                 [ c.reason, c.page_kind, c.card, c.lesson_revision_id, c.text_it ]
    assert_match(%r{\Acard:#{card}(/|\z)}, c.anchor)
    assert_not_nil c.viewport_width
    # The mode ends when the box has closed (after its closing transition): wait for it, do not race it.
    wait_until { page.evaluate_script("document.body.classList.contains('comment-mode')") == false }
    assert_equal [], page.evaluate_script("Object.keys(localStorage).filter(function (k) { return k.indexOf('banco.coutbox.') === 0 })"), "the outbox is empty once sent"
  end

  test "a comment written offline waits in the outbox and goes out when the network is back" do
    build_student_world(approve: true, release: true)
    visit "/today"
    page.execute_script("window.__realFetch = window.fetch; window.fetch = function () { return Promise.reject(new TypeError('offline')) }")
    find("#comment-open-menu").click
    find("#comment-whole").click
    write_comment(reason: "Mi piace", text: "Bella.")
    assert_equal 0, Comment.count
    assert_equal 1, page.evaluate_script("Object.keys(localStorage).filter(function (k) { return k.indexOf('banco.coutbox.') === 0 }).length")
    page.execute_script("window.fetch = window.__realFetch; window.dispatchEvent(new Event('online'))")
    wait_until { Comment.count == 1 }
    assert_equal "like", Comment.last.reason
    wait_until { page.evaluate_script("Object.keys(localStorage).filter(function (k) { return k.indexOf('banco.coutbox.') === 0 }).length").zero? }
  end

  test "in a sitting the clock stops while the box is open, and the comment names the served event" do
    include_ui = Module.new.extend(StudentUiRows)
    rows = include_ui.build_ui_subject
    include_ui.release_diagnosis!
    visit "/diagnosis"
    click_button "Comincia"
    click_button "Comincia"
    assert_selector "input[inputmode=decimal]", wait: 15
    run = DiagnosisRun.find_by!(student: rows[:student])
    find("#comment-open-menu").click
    find("#comment-whole").click
    assert_selector "#comment-box[open]", wait: 10
    assert_selector "#comment-clock-note", visible: :visible
    wait_until { run.events.where(kind: "comment_opened").count == 1 }
    assert_equal 0, run.events.where(kind: "comment_closed").count
    write_comment(reason: "C'è un errore", text: "Il testo ha un refuso.")
    wait_until { run.events.where(kind: "comment_closed").count == 1 }
    comment = wait_until { Comment.last }
    served = run.events.where(kind: "item_served").order(:seq).last
    assert_equal [ run.id, served.id, "error", "sitting" ], [ comment.diagnosis_run_id, comment.served_event_id, comment.reason, comment.page_kind ]
    assert_equal 0, Attempt.count, "a comment is not an answer"
    # the question is still there and can be answered
    find("input[inputmode=decimal]").set("6")
    click_button "Invia"
    wait_until { Attempt.count == 1 }
    assert_equal 1, Comment.count
  end
end
