require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# The browser's arrow back on the student's pages (D-355; the student, 2026-11-18: «La freccia indietro dalla parte del browser non funziona
# sul programma»). Every common path is walked forward and then back, and each test says where the arrow lands: Oggi, Materie, a subject, a
# topic, its lesson (a card is a step of the history) and its practice (an exercise served in the page is not); Impostazioni after a save;
# «I miei commenti» and a conversation; the front door `GET /`; a practice exercise served after another, with a half-typed answer and with a
# sent one. The sitting of the entry test is in back_navigation_sitting_test.rb. Text-free on purpose: ids, hrefs and the lesson's own api.
class BackNavigationTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  OFFICIAL_HEADERS = { "Remote-User" => "kid-a", "Remote-Groups" => "banco-student" }.freeze
  NUMBER_FIELD = ".item-body input[inputmode=decimal]".freeze

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "kid-a=student"
  end

  teardown do
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def sign_in_official
    sign_in_as :student
    page.driver.headers = OFFICIAL_HEADERS
  end

  def wait_until(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (value = yield)
      flunk "not true within #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    value
  end

  def history_length = page.evaluate_script("history.length")
  def location_hash = page.evaluate_script("location.hash")
  def card = page.evaluate_script("window.lessonApi.current()")
  def practice_path = "/topics/#{TOPIC}/practice/#{SKILL}"

  # The menu is a dialog on every page; its links have the ids menu-today, menu-subjects, menu-comments, menu-settings.
  def open_menu_link(key)
    find("#student-menu-open").click
    find("#menu-#{key}").click
  end

  def open_practice
    visit "/topics/#{TOPIC}"
    find("a[href$='/practice/#{SKILL}']", match: :first).click
    assert_current_path practice_path
    assert_selector NUMBER_FIELD, wait: 30
  end

  # ---- the course, forward and all the way back ---------------------------------------------------------

  test "Oggi, Materie, a subject, a topic, its lesson and its practice: the arrow back walks the same way home, card by card in the lesson" do
    build_lesson2_world(name: "equations", approve: true, release: true)
    sign_in_official
    visit "/today"
    assert_current_path "/today"
    open_menu_link(:subjects)
    assert_current_path "/subjects"
    find("a[href='/subjects/#{@subject.key}']").click
    assert_current_path "/subjects/#{@subject.key}"
    find("a[href='/topics/#{TOPIC}']", match: :first).click
    assert_current_path "/topics/#{TOPIC}"
    find("a[href='/topics/#{TOPIC}/lesson']", match: :first).click
    wait_for_lesson_ready(wait: 30)
    assert_current_path "/topics/#{TOPIC}/lesson"
    assert_equal "#scheda-0", location_hash, "the cover is the first entry of the lesson, with its address"
    at_cover = history_length

    # the cards of the lesson are steps of the history
    find(".l2-start").click
    assert_selector "#scheda-1"
    assert_equal "#scheda-1", location_hash
    find(".l2-next").click
    assert_selector "#scheda-2"
    assert_equal "#scheda-2", location_hash
    assert_equal [ at_cover + 2, 50 ].min, history_length, "two steps more (Chrome keeps at most 50 entries)"

    page.go_back
    wait_until { location_hash == "#scheda-1" }
    assert_selector "#scheda-1"
    assert_equal 1, card
    assert_current_path "/topics/#{TOPIC}/lesson"
    page.go_back
    wait_until { location_hash == "#scheda-0" }
    assert_selector ".l2-cover"
    assert_equal 0, card
    # the arrow goes forward too, and the lesson follows
    page.go_forward
    wait_until { location_hash == "#scheda-1" }
    assert_selector "#scheda-1"
    assert_equal 1, card
    page.go_back
    wait_until { location_hash == "#scheda-0" }
    assert_selector ".l2-cover"

    # from the cover the arrow leaves the lesson, for the topic
    page.go_back
    assert_current_path "/topics/#{TOPIC}"

    # its practice, and the same way home
    find("a[href$='/practice/#{SKILL}']", match: :first).click
    assert_current_path practice_path
    assert_selector NUMBER_FIELD, wait: 30
    page.go_back
    assert_current_path "/topics/#{TOPIC}"
    page.go_back
    assert_current_path "/subjects/#{@subject.key}"
    page.go_back
    assert_current_path "/subjects"
    page.go_back
    assert_current_path "/today"
    assert_no_selector "dialog[open]"
  end

  test "a link inside the lesson that opens another card is a step too, and the arrow back returns to the card it left" do
    build_lesson2_world(name: "equations", approve: true, release: true)
    sign_in_official
    visit "/topics/#{TOPIC}/lesson"
    wait_for_lesson_ready(wait: 30)
    find(".l2-start").click
    assert_selector "#scheda-1"
    page.execute_script("window.lessonApi.goTo(5, { focus: true })")
    assert_selector "#scheda-5"
    assert_equal "#scheda-5", location_hash
    page.go_back
    wait_until { location_hash == "#scheda-1" }
    assert_selector "#scheda-1"
    assert_equal 1, card
  end

  # ---- Impostazioni --------------------------------------------------------------------------------------

  test "Oggi, Impostazioni, a choice and «Salva», then back: Oggi again, with the choice on it and no second Impostazioni on the way" do
    build_student_world(approve: true, release: true)
    sign_in_official
    visit "/today"
    open_menu_link(:settings)
    assert_current_path "/settings"
    choose "theme_dark"
    choose "size_large"
    find("#preferences button[type=submit]").click
    wait_until { Diagnosis::Preferences.for(@official).values_at(:theme, :size) == %w[dark large] }
    assert_current_path "/settings"

    page.go_back
    assert_current_path "/today"
    assert_selector "html[data-theme=dark][data-size=large]"
    assert_no_selector "dialog[open]"
  end

  # ---- «I miei commenti» ---------------------------------------------------------------------------------

  # One comment of the student's, written through the box, with the teacher's reply on it.
  def answered_comment
    visit "/today"
    find("#comment-open-menu").click
    find("#comment-whole").click
    assert_selector "#comment-box[open]", wait: 10
    choose "Non capisco"
    fill_in "comment-text", with: "Non mi torna il secondo passaggio."
    find("#comment-send").click
    wait_until { Comment.count == 1 }
    comment = Comment.last
    CommentEvent.create!(comment: comment, kind: "reply", origin: "web", actor: "nik", request_id: nil, remote_addr: "", payload_json: "{}",
                         text_it: "Guarda la scheda due.", created_at: Time.current)
    comment
  end

  test "«I miei commenti», a conversation, a message sent in it: the arrow back goes to the list and then to Oggi, and the message is not sent again" do
    build_student_world(approve: true, release: true)
    sign_in_official
    comment = answered_comment
    visit "/today"
    open_menu_link(:comments)
    assert_current_path "/comments"
    find("#comment-#{comment.id} .cm-row-link").click
    assert_selector "#conversation", wait: 10
    assert_current_path "/comments/#{comment.id}"

    length = history_length
    find("#reply-#{comment.id}").send_keys("Grazie, ora è chiaro.", :enter)
    assert_selector ".cm-msg[data-from=student] .cm-bubble", text: "Grazie, ora è chiaro.", wait: 10
    wait_until { comment.events.reload.where(kind: "student_reply").count == 1 }
    assert_equal length, history_length, "sending a message adds no step to the history"

    page.go_back
    assert_current_path "/comments"
    assert_selector "#comment-#{comment.id}", wait: 10
    assert_selector "#conversation", count: 0
    page.go_back
    assert_current_path "/today"
    assert_equal 1, comment.events.reload.where(kind: "student_reply").count, "the arrow does not send the message again"
  end

  # ---- the front door ------------------------------------------------------------------------------------

  test "GET / goes to Oggi through a redirect that leaves no step: the arrow back from Oggi goes to the page before the front door" do
    build_student_world(approve: true, release: true)
    sign_in_official
    visit "/settings"
    assert_current_path "/settings"
    visit "/"
    assert_current_path "/today"
    page.go_back
    assert_current_path "/settings"
    page.go_forward
    assert_current_path "/today"
  end

  # ---- the practice page ---------------------------------------------------------------------------------

  test "practice: an exercise served after another in the page adds no step; the arrow back leaves for the topic with the half-typed answer kept, and forward resumes it" do
    build_student_world(approve: true, release: true)
    sign_in_official
    open_practice
    first = PracticeServe.order(:id).last
    length = history_length
    find(NUMBER_FIELD).set("77")
    find("#skip-button").click
    wait_until { PracticeServe.count == 2 }
    assert_selector NUMBER_FIELD
    second = PracticeServe.order(:id).last
    assert_not_equal first.id, second.id
    assert_equal length, history_length, "an exercise served in the page is not a step of the history"
    assert_equal "77", PracticeDraft.where(practice_serve_id: first.id).order(:id).last&.raw

    # typed, saved by the page's autosave (D-337), then the arrow back: the topic, with nothing sent
    find(NUMBER_FIELD).set("5")
    wait_until(15) { PracticeDraft.where(practice_serve_id: second.id).order(:id).last&.raw == "5" }
    page.go_back
    assert_current_path "/topics/#{TOPIC}"
    assert_equal 0, PracticeAttempt.count, "leaving sends no answer"

    page.go_forward
    assert_current_path practice_path
    assert_selector NUMBER_FIELD, wait: 30
    wait_until { find(NUMBER_FIELD).value == "5" }
    assert_equal 2, PracticeServe.count, "the page resumes the open exercise and serves no new one"
    assert_equal 0, PracticeAttempt.count
  end

  test "practice: a sent answer is recorded once; the arrow back and forward neither send it again nor lose it" do
    build_student_world(approve: true, release: true)
    sign_in_official
    open_practice
    serve = PracticeServe.order(:id).last
    find(NUMBER_FIELD).set(JSON.parse(serve.item_instance.answer_json).to_s)
    find("#check").click
    wait_until { PracticeAttempt.count == 1 }
    assert_selector "#feedback.notice", wait: 10

    page.go_back
    assert_current_path "/topics/#{TOPIC}"
    page.go_forward
    assert_current_path practice_path
    assert_selector "#skill-name", wait: 10
    assert_selector "#feedback, #next-actions", visible: :all, wait: 30
    sleep 1 # a page that would send the answer again has had its time
    assert_equal 1, PracticeAttempt.count
    assert_equal 0, page.evaluate_script("Object.keys(localStorage).filter(function (k) { return k.indexOf('banco.poutbox.') === 0 }).length"), "nothing is left in the outbox"
  end
end
