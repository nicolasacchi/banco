require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# D-397, in Chrome: the student picks the point of his comment from the list in the box, on the topic page and on a practice page (no test did
# before), and the list never shows a raw «id:…»: a tapped place with no name is told by its words.
class CommentsAnchorsTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  setup do
    build_student_world(approve: true, release: true)
    sign_in_as :student
  end

  teardown { sign_out_env }

  def wait_until(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (value = yield)
      flunk "not true within #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    value
  end

  def options = page.evaluate_script("Array.from(document.getElementById('comment-where').options).map(o => o.textContent)")

  # «Commenta», «Scegli dall'elenco», the option whose words match, a reason, a text, «Invia». Returns the comment that was stored.
  def comment_from_list(choice)
    before = Comment.count
    find("[data-comment-open]", match: :first, visible: :visible, wait: 15).click
    find("#comment-list", wait: 10).click
    assert_selector "#comment-box[open]", wait: 10
    assert_empty options.grep(/\Aid:/), "no raw anchor in the list"
    assert_equal options.uniq, options, "each point of the list has a name of its own"
    option = find("#comment-where option", text: choice, visible: :all, wait: 10)
    option.select_option
    assert_selector "#comment-where option:checked", text: choice, visible: :all
    choose "Altro"
    fill_in "comment-text", with: "Scelto dall'elenco."
    find("#comment-send").click
    assert_no_selector "#comment-box[open]", wait: 10
    wait_until { Comment.count == before + 1 }
    Comment.order(:id).last
  end

  test "on the topic page the list offers the steps and the skill, and the chosen point is the comment's anchor" do
    visit "/topics/#{TOPIC}"
    assert_selector "#step-practice", wait: 15
    comment = comment_from_list(/\AIl passo Esercizi/)
    assert_equal [ "topic", "step_practice" ], [ comment.page_kind, comment.anchor ]
    visit "/topics/#{TOPIC}"
    assert_equal "skill:1", comment_from_list(/Cosa eserciti, voce 1/).anchor
    visit "/topics/#{TOPIC}"
    assert_equal "step_lesson", comment_from_list(/\AIl passo Lezione/).anchor
  end

  test "on a practice page the list offers the skill status and the exercise list" do
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_selector "#skill-state", wait: 30
    comment = comment_from_list(/\ACome stai andando/)
    assert_equal [ "practice", "skill_status" ], [ comment.page_kind, comment.anchor ]
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_selector "#skill-state", wait: 30
    find("[data-comment-open]", match: :first, visible: :visible, wait: 15).click
    find("#comment-list", wait: 10).click
    assert_selector "#comment-box[open]", wait: 10
    assert_includes options.join("\n"), "L'elenco degli esercizi"
  end

  test "a tap on a part with no name is shown by its words, never as an id" do
    visit "/topics/#{TOPIC}"
    assert_selector "#intro", wait: 15
    find("[data-comment-open]", match: :first, visible: :visible, wait: 15).click
    find("#intro").click
    assert_selector "#comment-box[open]", wait: 10
    shown = page.evaluate_script("document.getElementById('comment-where').selectedOptions[0].textContent")
    assert_no_match(/\Aid:/, shown)
    assert_includes shown, "Qui impari"
    choose "Altro"
    find("#comment-send").click
    assert_no_selector "#comment-box[open]", wait: 10
    wait_until { Comment.count == 1 }
    assert_equal "id:intro", Comment.last.anchor, "the server keeps what the page named; only the words shown to him change"
  end
end
