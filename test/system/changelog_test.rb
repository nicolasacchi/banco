require "application_system_test_case"
require_relative "../support/changelog_world"
require_relative "../support/student_session"

# D-375, «Novità» in Chrome, on a 390 px phone: the dot on the menu button and on the entry while something is newer than his last visit, the page with its
# three sections (his own comments, the entries, the topics updated by day), the dot gone after the visit, no sideways scroll, a tap target of 44 px on each
# link, the teacher's reason nowhere, and «Commenta» working on the page.
class ChangelogSystemTest < ApplicationSystemTestCase
  include ChangelogWorld
  include StudentSession

  REASON = "SEGRETO-DEL-DOCENTE: la correzione cambia il segno.".freeze

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV.delete("BANCO_STUDENT_USERS")
    build_student_world(approve: true, release: true)
    comment_on(@official, "/topics/#{TOPIC}/lesson", "lesson", at: 2.days.ago, card: 1)
    revise!(lesson_findings_reason_it: REASON)
    sign_in_as :student
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

  def wait_until(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (value = yield)
      flunk "not true within #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    value
  end

  def no_sideways_scroll = assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "the page scrolls sideways"

  test "on a phone: the dot, the page in three sections, the dot gone after the visit, the targets and the comment box" do
    visit "/today"
    assert_selector "#student-menu-open .menu-dot", visible: :all, wait: 10
    find("#student-menu-open").click
    assert_selector "#student-menu-dialog[open]"
    assert_selector "#menu-changelog #changelog-dot", visible: :all
    page.execute_script("document.querySelector('#menu-changelog').scrollIntoView({ block: 'center', behavior: 'instant' })")
    wait_until { page.evaluate_script("document.querySelector('#menu-changelog').getBoundingClientRect().top < window.innerHeight") }
    find("#menu-changelog").click

    assert_selector "h1", text: "Novità", wait: 10
    assert_current_path "/novita"
    assert_selector "#changelog-followups li[data-topic='#{TOPIC}']", text: /Equazioni di primo grado\s+1 commento\s+Argomento rivisto il/
    assert_selector "#changelog-entries li[data-entry=my-schemas] h3", text: "I miei schemi", visible: :all
    assert_selector "#changelog-updates li[data-topic='#{TOPIC}'] a", text: "Aggiornato: Equazioni di primo grado"
    assert_selector "#changelog-updates .changelog-note", text: "Esercizi o lezione rivisti negli ultimi 14 giorni."
    assert_equal %w[changelog-followups changelog-entries changelog-updates], page.all("section.changelog-section").map { |s| s[:id] }
    assert_not page.has_text?("SEGRETO-DEL-DOCENTE"), "the teacher's reason is not on his page"
    assert page.has_selector?("[data-new=true]", minimum: 1), "what came after his account is marked new"
    no_sideways_scroll

    # every link and button of the page is a 44 px target and fits the window
    sizes = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("#changelog-page a.button, #changelog-page a.changelog-topic-link")).filter((a) => a.offsetParent).map((a) => { const r = a.getBoundingClientRect(); return [Math.round(r.height), Math.round(r.right), a.textContent.trim()] })
    JS
    assert_operator sizes.size, :>=, 3
    sizes.each do |height, right, text|
      assert_operator height, :>=, 44, "#{text}: a 44 px target"
      assert_operator right, :<=, 390, "#{text}: inside the window"
    end

    # the visit was recorded and the dot is gone from every page
    wait_until { AppEvent.where(kind: "changelog_viewed", student_id: @official.id).count == 1 }
    visit "/today"
    assert_no_selector "#student-menu-open .menu-dot", visible: :all
    find("#student-menu-open").click
    assert_selector "#student-menu-dialog[open]"
    assert_no_selector "#changelog-dot", visible: :all
    find("#student-menu-close").click

    # the followup links to the conversation
    visit "/novita"
    find("#changelog-followups a.button").click
    assert_current_path %r{\A/comments/\d+\z}

    # «Commenta» works on the page and files it under its own kind
    visit "/novita"
    before = Comment.count
    find("[data-comment-open]", match: :first, visible: :visible, wait: 15).click
    find("#comment-whole", wait: 10).click
    assert_selector "#comment-box[open]", wait: 10
    choose "Altro"
    fill_in "comment-text", with: "Prova da Novità."
    find("#comment-send").click
    assert_no_selector "#comment-box[open]", wait: 10
    wait_until { Comment.count == before + 1 }
    last = Comment.order(:id).last
    assert_equal [ "changelog", "/novita" ], [ last.page_kind, last.page_path ]
  end
end
