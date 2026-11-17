require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# D-349 in Chrome: «I miei commenti» as a mailbox and a chat. The inbox lists the conversation with its tabs and its dot; opening it
# shows the bubbles and the composer; on a desktop Enter sends and Shift+Enter makes a new line; the bubble is there at once and
# the server has the message once; on a phone the conversation has a back arrow and the list is not beside it.
class CommentsV2Test < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  setup { sign_in_as :student }
  teardown do
    page.driver.resize(1280, 900)
    sign_out_env
  end

  def wait_until(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (value = yield)
      flunk "not true within #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    value
  end

  # One comment of the student's, written through the box, with the teacher's reply on it.
  def answered_comment
    build_student_world(approve: true, release: true)
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

  def outbox_keys = page.evaluate_script("Object.keys(localStorage).filter(function (k) { return k.indexOf('banco.routbox.') === 0 })")

  test "open the inbox, open a conversation, send with Enter and see the bubble; Shift+Enter is a new line" do
    comment = answered_comment
    visit "/comments"
    assert_selector "#reply-window", text: "Il docente risponde entro un giorno.", wait: 10
    assert_selector "#comment-tabs [data-tab=new] .cm-tab-n", text: "1"
    assert_selector "#comment-#{comment.id}[data-unread=true] .cm-dot"
    assert_equal %w[reply], comment.events.reload.map(&:kind), "the list marks nothing seen"
    assert_selector "#conversation", count: 0

    find("#comment-#{comment.id} .cm-row-link").click
    assert_selector "#conversation", wait: 10
    assert_selector ".cm-msg[data-from=teacher] .cm-bubble", text: "Guarda la scheda due."
    assert_selector ".cm-msg[data-from=student] .cm-bubble", text: "Non capisco"
    assert_selector "#comment-list-pane", wait: 5 # two panes on a wide screen
    wait_until { comment.events.reload.map(&:kind).include?("reply_seen") }
    assert_selector "#comment-#{comment.id}[data-unread=false]"

    field = find("#reply-#{comment.id}")
    field.send_keys("Grazie, ora è chiaro.", :enter)
    assert_selector ".cm-msg[data-from=student] .cm-bubble", text: "Grazie, ora è chiaro.", wait: 10
    wait_until { comment.events.reload.where(kind: "student_reply").count == 1 }
    assert_no_selector ".cm-msg[data-pending]", wait: 10
    assert_equal "Grazie, ora è chiaro.", comment.events.reload.where(kind: "student_reply").last.text_it
    assert_equal "", find("#reply-#{comment.id}").value, "the composer is empty once the message is sent"
    assert_equal [], outbox_keys, "the outbox is empty once sent"
    assert_selector ".cm-msg[data-from=student] .cm-time", text: /\d\d:\d\d/

    find("#reply-#{comment.id}").send_keys("Prima riga", [ :shift, :enter ], "Seconda riga")
    assert_equal "Prima riga\nSeconda riga", find("#reply-#{comment.id}").value, "Shift+Enter makes a new line"
    assert_equal 1, comment.events.reload.where(kind: "student_reply").count, "and sends nothing"
    find("#reply-send").click
    wait_until { comment.events.reload.where(kind: "student_reply").count == 2 }
    assert_equal "Prima riga\nSeconda riga", comment.events.where(kind: "student_reply").last.text_it
    assert_selector ".cm-msg[data-from=student]", count: 3
  end

  test "a message that cannot go out stays as a bubble that says so, and goes out when the network is back" do
    comment = answered_comment
    visit "/comments/#{comment.id}"
    assert_selector "#conversation", wait: 10
    page.execute_script("window.__realFetch = window.fetch; window.fetch = function () { return Promise.reject(new TypeError('offline')) }")
    find("#reply-#{comment.id}").send_keys("Mi senti?", :enter)
    assert_selector ".cm-msg[data-pending=failed] .cm-retry", text: "Non inviato", wait: 10
    assert_selector ".cm-msg[data-pending=failed] .cm-bubble", text: "Mi senti?"
    assert_equal 0, comment.events.reload.where(kind: "student_reply").count
    assert_equal 1, outbox_keys.size
    page.execute_script("window.fetch = window.__realFetch")
    find(".cm-retry").click
    wait_until { comment.events.reload.where(kind: "student_reply").count == 1 }
    assert_no_selector ".cm-msg[data-pending]", wait: 10
    wait_until { outbox_keys.empty? }
  end

  test "on a phone the conversation is the whole screen with a back arrow to the list" do
    comment = answered_comment
    page.driver.resize(390, 800)
    visit "/comments"
    assert_selector "#comment-#{comment.id}", wait: 10
    assert_no_selector "#conversation"
    find("#comment-#{comment.id} .cm-row-link").click
    assert_selector "#conversation", wait: 10
    assert_no_selector "#comment-list-pane", visible: :visible
    assert_selector "#reply-#{comment.id}", visible: :visible
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"), "no sideways scroll"
    find("#comment-back").click
    assert_selector "#comment-#{comment.id}", wait: 10
    assert_no_selector "#conversation"
  end
end
