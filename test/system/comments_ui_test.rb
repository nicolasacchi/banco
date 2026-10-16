require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# D-305, the look and the use of «Commenta» in Chrome: Esc leaves the comment mode, "Tutta la pagina" names the place, a reason is a
# chip, the confirmation says "Inviato al docente" and fades, the control stays inside a phone at the largest text, and the lists
# (the student's, the teacher's) show what the design promises. The rules of D-304 are in comments_system_test.rb.
class CommentsUiTest < ApplicationSystemTestCase
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

  def mode? = page.evaluate_script("document.body.classList.contains('comment-mode')")

  test "Esc leaves the comment mode and writes nothing; focus goes back to the control" do
    build_student_world(approve: true, release: true)
    visit "/today"
    find("#comment-open-menu").click
    assert_selector "#comment-banner", visible: :visible
    assert_text "Tocca la parte di cui vuoi parlare"
    assert mode?
    page.driver.browser.keyboard.type(:Escape)
    assert_no_selector "#comment-banner", visible: :visible
    assert_not mode?
    assert_equal "comment-open-menu", page.evaluate_script("document.activeElement.id")
    assert_equal 0, Comment.count
    assert_no_selector "#comment-box[open]"
  end

  test "Tutta la pagina opens the box naming the whole page; a reason is a chip; sending says Inviato al docente and fades" do
    build_student_world(approve: true, release: true)
    visit "/today"
    find("#comment-open-menu").click
    find("#comment-whole").click
    assert_selector "#comment-box[open]", wait: 10
    assert_equal "Tutta la pagina", page.evaluate_script("document.getElementById('comment-where').selectedOptions[0].textContent")
    assert_no_selector "#comment-clock-note", visible: :visible, wait: 1 # not in a sitting: the clock is not ours
    assert_selector ".comment-chip", count: 5
    # no reason yet: the box says so and stays open
    find("#comment-send").click
    assert_text "Scegli prima"
    assert_selector "#comment-box[open]"
    choose "Non funziona"
    assert_equal "not_working", page.evaluate_script("document.querySelector('.comment-chip input:checked').value")
    assert_selector ".comment-chip:has(input:checked)", count: 1
    fill_in "comment-text", with: "Il pulsante non risponde."
    assert_text "25 di 500"
    find("#comment-send").click
    assert_no_selector "#comment-box[open]", wait: 10
    assert_selector "#comment-toast.show", text: "Inviato al docente", wait: 10
    assert_equal "polite", find("#comment-toast", visible: :all)["aria-live"]
    wait_until { Comment.count == 1 }
    assert_equal [ "not_working", "Il pulsante non risponde." ], [ Comment.last.reason, Comment.last.text_it ]
    assert_not mode?, "the page is as before"
    assert_no_selector "#comment-toast.show", wait: 8
  end

  test "a comment can be cancelled with the close button and the box leaves no outline on the page" do
    build_student_world(approve: true, release: true)
    visit "/today"
    find("#comment-open-menu").click
    find("#comment-whole").click
    assert_selector "#comment-box[open]", wait: 10
    find("#comment-close").click
    assert_no_selector "#comment-box[open]"
    wait_until { !mode? }
    assert_selector ".comment-picked", count: 0
    assert_equal 0, Comment.count
  end

  test "on a phone at the largest text the page does not scroll sideways and the control is on screen" do
    build_student_world(approve: true, release: true)
    page.driver.resize(390, 800)
    visit "/today"
    page.execute_script("document.documentElement.dataset.size = 'larger'")
    assert_equal true, page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
    rect = page.evaluate_script("(() => { const r = document.getElementById('comment-open-menu').getBoundingClientRect(); return [r.left, r.right] })()")
    assert rect[0] >= 0 && rect[1] <= 390, rect.inspect
    find("#comment-open-menu").click
    assert_equal true, page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
    find("#comment-whole").click
    assert_selector "#comment-box[open]", wait: 10
    sheet = -> { page.evaluate_script("(() => { const r = document.getElementById('comment-box').getBoundingClientRect(); return [r.left, r.right, r.bottom, innerHeight] })()") }
    box = wait_until { sheet.call.then { |b| b if b[2] <= b[3] + 1 } } # the sheet slides up first
    assert box[0] >= 0 && box[1] <= 390, "the box is a sheet inside the phone: #{box.inspect}"
  ensure
    page.driver.resize(1280, 900)
  end

  test "I miei commenti shows the reason, the state and the teacher's reply as a bubble" do
    build_student_world(approve: true, release: true)
    visit "/today"
    find("#comment-open-menu").click
    find("#comment-whole").click
    assert_selector "#comment-box[open]", wait: 10
    choose "Mi piace"
    find("#comment-send").click
    wait_until { Comment.count == 1 }
    comment = Comment.last
    CommentEvent.create!(comment: comment, kind: "reply", origin: "web", actor: "nik", request_id: nil, remote_addr: "", payload_json: "{}", text_it: "Grazie, bene così.", created_at: Time.current)
    visit "/comments"
    assert_selector ".comment-item[data-new]", wait: 10
    assert_selector ".comment-item .comment-reason", text: "Mi piace"
    assert_selector ".comment-state", text: "Risposto"
    assert_selector "blockquote.comment-reply", text: "Grazie, bene così."
  end
end
