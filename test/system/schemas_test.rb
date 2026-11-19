require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# D-372, «I miei schemi» in Chrome, on a 390 px phone: the schema of a done topic with its diagram drawn (the lesson renderer on one card: no bar,
# no map, no end box), the page closed for a topic that is not done, «I miei schemi» in the menu and its list, «Stampa» (window.print) and the print
# rules (one schema on an A4 page, no menu, no comment box, no buttons), and no sideways scroll.
class SchemasSystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV.delete("BANCO_STUDENT_USERS")
    build_lesson2_world(approve: true, release: true)
    sign_in_as :student
    page.driver.resize(390, 844)
  end

  teardown do
    begin
      page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "screen")
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  # Three right answers on three days: the topic is done.
  def finish_topic!
    @clock = Diagnosis::FakeClock.new(Time.current - 20.days)
    play_topic!(@topic_revision, SKILL, 3)
  end

  # On a phone the menu dialog slides up (sheet-in); a click on a link while it moves can land on the backdrop and close it. Waits for the end of its animation.
  def wait_until_still(selector, wait: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
    until page.evaluate_script("document.querySelector(#{selector.to_json}).getAnimations().length === 0")
      flunk "#{selector} was still animating after #{wait} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
  end

  def open_schema
    visit "about:blank"
    visit "/topics/#{TOPIC}/schema?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 30)
  end

  def no_sideways_scroll = assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "the page scrolls sideways"

  def emulate_print
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "print")
    Timeout.timeout(10) { sleep 0.1 until page.evaluate_script("matchMedia('print').matches") }
  end

  test "the schema of a done topic on a phone: the summary card and its diagram drawn, no lesson bar, the links and «Stampa»" do
    finish_topic!
    open_schema
    assert_selector "h1", text: "Schema: Equazioni di primo grado"
    assert_selector "#lesson-root[data-schema] article.l2-card[data-role=summary]", count: 1
    assert_selector ".l2-card .summary-points li", count: 4
    assert_selector "article.l2-card figure.dg .dg-stage svg", minimum: 1, wait: 20
    assert_no_selector "figure.dg[data-error]", visible: :all
    assert_equal 1, page.evaluate_script("document.querySelectorAll('.l2-card').length"), "only the summary card is drawn"
    %w[.l2-top .l2-bar .l2-sidemap .l2-end .l2-cover].each { |selector| assert_no_selector selector, visible: :all }
    assert_selector "#student-menu-open", visible: :visible, wait: 10 # the student's own bar stays: the menu and «Commenta»
    assert_selector "[data-comment-open]", visible: :visible
    assert_selector "#schema-lesson", text: "Rileggi la lezione"
    assert_selector "#schema-practice", text: "Esercizi"
    assert_selector "#schema-print", text: "Stampa"
    assert_equal "", page.evaluate_script("location.hash"), "the page keeps no card in the address: it records no position"
    no_sideways_scroll
    boxes = page.evaluate_script("[...document.querySelectorAll('#schema-page .button, #schema-page .l2-card')].map((e) => { const r = e.getBoundingClientRect(); return [e.id || e.className, r.left, r.right] })")
    boxes.each { |name, left, right| assert_operator left, :>=, 0, "#{name} starts at #{left}"; assert_operator right, :<=, 390.5, "#{name} ends at #{right}" }
  end

  test "«Stampa» calls window.print, and the print rules: one schema on an A4 page, nothing but the schema" do
    finish_topic!
    open_schema
    page.execute_script("window.__printed = 0; window.print = () => { window.__printed += 1 }")
    find("#schema-print").click
    assert_equal 1, page.evaluate_script("window.__printed")
    assert page.evaluate_script("Array.from(document.styleSheets).some((s) => Array.from(s.cssRules).some((r) => r.constructor.name === 'CSSPageRule' && /size:\\s*a4/i.test(r.cssText)))"),
           "an @page rule sets A4"
    emulate_print
    assert_selector ".l2-card[data-role=summary] .summary-points li", count: 4, visible: :visible
    assert_selector "figure.dg .dg-stage svg", minimum: 1, visible: :visible
    [ ".topbar", ".schema-actions", "#schema-print", ".comment-open", ".l2-top" ].each { |selector| assert_no_selector selector, visible: :visible }
    assert_selector "h1", text: "Schema: Equazioni di primo grado", visible: :visible
    assert_equal 1, page.evaluate_script("[...document.querySelectorAll('.l2-card')].filter((c) => c.offsetParent !== null).length")
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "the print layout does not scroll sideways"
  end

  test "a topic that is not done: the phone shows it closed, with the words and the two links, and no card" do
    open_url = "/topics/#{TOPIC}/schema?n=#{SecureRandom.hex(3)}"
    visit "about:blank"
    visit open_url
    assert_selector "h1", text: "Schema: Equazioni di primo grado"
    assert_selector "#schema-locked", text: "Si apre quando finisci l'argomento."
    assert_selector "#schema-practice", text: "Esercizi"
    assert_selector "#schema-lesson", text: "Rileggi la lezione"
    assert_no_selector "#lesson-root"
    assert_no_selector ".l2-card"
    no_sideways_scroll
  end

  test "«I miei schemi» in the menu and its list on a phone: the open schemas, a click opens one" do
    finish_topic!
    visit "/today"
    find("#student-menu-open").click
    assert_selector "#student-menu-dialog[open]"
    wait_until_still("#student-menu-dialog")
    assert_selector "#menu-schemas", text: "I miei schemi"
    find("#menu-schemas").click
    assert_selector "h1", text: "I miei schemi"
    assert_selector "#schemas-page .schema-link", text: "Equazioni di primo grado"
    assert_selector "#topbar-title", text: "I miei schemi", visible: :all
    no_sideways_scroll
    find("a.schema-link", text: "Equazioni di primo grado").click
    wait_for_lesson_ready(wait: 30)
    assert_selector "#lesson-root[data-schema] article.l2-card[data-role=summary]"
  end

  test "the list on a phone with a closed schema counts it and shows no title" do
    visit "/schemas"
    assert_selector "h1", text: "I miei schemi"
    assert_selector ".schemas-locked", text: "Ancora chiuso: 1 schema. Si apre quando finisci l'argomento."
    assert_no_selector ".schema-link"
    assert_no_text "Equazioni di primo grado"
    no_sideways_scroll
  end

  test "the box takes a comment on the schema page and on the list, filed under their own kinds" do
    finish_topic!
    { "/topics/#{TOPIC}/schema" => "schema", "/schemas" => "schemas" }.each do |path, kind|
      visit path
      find("[data-comment-open]", match: :first, visible: :visible, wait: 15).click
      find("#comment-whole", wait: 10).click
      assert_selector "#comment-box[open]", wait: 10
      choose "Altro"
      fill_in "comment-text", with: "Prova dallo schema."
      before = Comment.count
      find("#comment-send").click
      assert_no_selector "#comment-box[open]", wait: 10
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      sleep 0.1 until Comment.count > before || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      comment = Comment.order(:id).last
      assert_equal [ kind, path ], [ comment.page_kind, comment.page_path ], path
    end
    assert_equal @lesson_revision.id, Comment.where(page_kind: "schema").last.lesson_revision_id, "the schema's comment names the revision he was shown"
  end
end
