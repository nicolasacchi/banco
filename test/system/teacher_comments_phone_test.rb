require "application_system_test_case"
require_relative "../support/changelog_world"
require_relative "../support/student_session"

# D-376: the teacher's comment inbox on a 390 px phone. A comment with a selection or an element id that is one long unbroken word, and a reply of the
# same kind, used to widen every card (the page was 633 px wide on the copy of production): the document, each card and its history fit the window.
class TeacherCommentsPhoneTest < ApplicationSystemTestCase
  include ChangelogWorld
  include StudentSession

  LONG = ("\\mathrm{h}ereisnovaluefura" * 6).freeze
  ANCHOR = "id:my-path-title-with-a-name-that-is-long-and-has-no-space-at-all".freeze

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV.delete("BANCO_STUDENT_USERS")
    build_student_world(approve: true, release: true)
    @only_selection = make_comment("/account", "account", at: 22.hours.ago, text: nil)
    @long = make_comment("/topics/#{TOPIC}/lesson", "lesson", at: 2.days.ago, card: 1, text: "Parola#{'lunga' * 40} senza spazi.")
    CommentEvent.create!(comment: @long, kind: "reply", actor: "nik", origin: "web", text_it: "Risposta#{'lunga' * 40}")
    sign_in_as :teacher
    page.driver.resize(390, 844)
  end

  teardown do
    begin
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def make_comment(path, kind, at:, text:, card: nil)
    Comment.create!(student: @official, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "error", text_it: text, page_path: path, page_kind: kind, subject: @subject,
                    card: card, selected_text: LONG, anchor: ANCHOR, created_at: at)
  end

  def overflow = page.evaluate_script("[document.documentElement.scrollWidth, window.innerWidth]")

  test "the inbox fits a 390 px phone: no sideways scroll, every card and its history inside the window" do
    visit "/teacher/comments"
    assert_selector "li.comment-row", minimum: 2, wait: 10
    width, window = overflow
    assert_operator width, :<=, window, "the page scrolls sideways (#{width} px in a #{window} px window)"
    rights = page.evaluate_script("Array.from(document.querySelectorAll('li.comment-row, li.comment-row *')).map((e) => Math.round(e.getBoundingClientRect().right))")
    assert_operator rights.max, :<=, 390, "something of a card runs off the right edge"
    assert_selector ".comment-row .comment-history li", minimum: 1
    assert_selector ".comment-row textarea", minimum: 1
  end

  test "the card shows words, not internals: no raw element id, «Solo il punto segnato, senza parole» for a comment with no text" do
    visit "/teacher/comments"
    assert_selector "li.comment-row", minimum: 2, wait: 10
    assert_no_text "(nessun testo)"
    assert_no_text ANCHOR
    assert_selector "#comment-#{@only_selection.id} .comment-text", text: "Solo il punto segnato, senza parole"
  end
end
