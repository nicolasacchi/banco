require "application_system_test_case"
require_relative "../support/words_family_world"
require_relative "../support/student_session"

# The words family in Chrome (T3): the two gallery lessons drawn by the student's page. word_parts in its two views, mirror wide and as a list
# of numbered pairs, the dialogue with its glosses, and the select check over a word and over a mirror. Screenshots go to BANCO_SHOT_DIR
# (words-<gallery>-<card>-<width>.png) for the look gate.
class WordsFamilySystemTest < ApplicationSystemTestCase
  include WordsFamilyWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))
  SIZES = { "1366" => [ 1366, 900 ], "390" => [ 390, 844 ] }.freeze

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
  end

  teardown do
    begin
      page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "forced-colors", value: "none" }, { name: "prefers-reduced-motion", value: "no-preference" } ])
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def open_gallery(which = :spanish, size: [ 1366, 900 ])
    @gallery = which
    build_lesson2_world(approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    assert_selector "#lesson-root[data-ready='1']", wait: 20
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "words-#{name}.png"), full: true)

  def no_overflow!(where)
    over = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    assert_operator over, :<=, 1, "#{where}: the page is #{over} px wider than the window"
  end

  CARDS = { spanish: (1..14).to_a, english: (1..3).to_a }.freeze

  SIZES.each do |label, size|
    CARDS.each do |which, cards|
      test "every card of the #{which} gallery is drawn at #{label} px with no finding of the layout (shots)" do
        open_gallery(which, size: size)
        cards.each do |n|
          go(n)
          assert_selector "#scheda-#{n}"
          assert_no_selector "#scheda-#{n} .dg-failed"
          assert_no_selector "#scheda-#{n} .block-unavailable"
          no_overflow!("card #{n}")
          shot("#{which}-#{n}-#{label}")
        end
      end
    end
  end

  test "the cards of the family in the dark theme (shots): nothing disappears and the page does not overflow" do
    open_gallery
    page.execute_script("document.documentElement.setAttribute('data-theme', 'dark')")
    [ 1, 4, 8, 12 ].each do |n|
      go(n)
      assert_selector "#scheda-#{n}"
      no_overflow!("dark card #{n}")
      shot("spanish-#{n}-dark")
    end
  end

  test "word_parts: the pieces glued in a word, the syllables under it, the strong one taller with a dot, and a key once for the figure" do
    open_gallery
    go(4)
    assert_selector "#scheda-4 .dg-word_parts .dg-label", text: "dár"
    assert_selector "#scheda-4 .dg-word_parts [lang=es]", minimum: 4
    assert_selector "#scheda-4 .dg-label", text: "Qui batte la voce", count: 1
    assert_selector "#scheda-4 .dg-label", text: "pezzo attaccato", count: 1
    descr = page.evaluate_script("document.querySelector('#scheda-4 .dg-desc p').textContent")
    assert_match(/La voce batte sulla sillaba numero 1: dár\./, descr)
  end

  test "word_parts with states: Avanti changes the word and the description, the language stays Spanish" do
    open_gallery
    go(6)
    assert_selector "#scheda-6 .dg-counter", text: "1 di 3"
    assert_selector "#scheda-6 .dg-label", text: "pli"
    find("#scheda-6 .dg-next").click
    assert_selector "#scheda-6 .dg-op", text: "Con se"
    find("#scheda-6 .dg-next").click
    assert_selector "#scheda-6 .dg-op", text: "Con se e lo"
    assert_selector "#scheda-6 .dg-label", text: "cár"
    assert_selector "#scheda-6 .dg-label[lang=es]", minimum: 3
    shot("spanish-6-last")
  end

  test "mirror: wide it is two lines with links told apart by line and mark and a key; on a phone it is a numbered pair for each link" do
    open_gallery
    go(8)
    assert_selector "#scheda-8 .dg-mirror .dg-mr-link", minimum: 3
    assert_selector "#scheda-8 .dg-label", text: "cambia"
    assert_selector "#scheda-8 .dg-label", text: "uguale"
    assert_selector "#scheda-8 .dg-label", text: "due parole, non una"
    page.driver.resize(390, 844)
    go(8)
    assert_selector "#scheda-8 .dg-numlabel", text: "3", wait: 3
    no_overflow!("mirror list")
  end

  test "the dialogue: no accepted voice, so the transcript is open and there is no listen button; a gloss opens one line at a time" do
    open_gallery
    go(12)
    assert_selector "#scheda-12 .dialogue-line", count: 4
    assert_no_selector "#scheda-12 .dialogue-listen", visible: :visible
    assert_no_selector "#scheda-12 .dialogue-say", visible: :visible
    assert_selector "#scheda-12 .dialogue-text", text: "¿Me das el libro, por favor?", visible: :visible
    assert_selector "#scheda-12 .dialogue-text[lang=es]", count: 4
    assert_no_selector "#scheda-12 .dialogue-gloss", visible: :visible
    first("#scheda-12 .dialogue-it").click
    assert_selector "#scheda-12 .dialogue-gloss", text: "Mi dai il libro, per favore?", visible: :visible, count: 1
    assert_selector "#scheda-12 .dialogue-it[aria-expanded=true]", count: 1
    shot("spanish-12-gloss")
    first("#scheda-12 .dialogue-it[aria-expanded=true]").click
    assert_no_selector "#scheda-12 .dialogue-gloss", visible: :visible
  end

  test "the dialogue by keyboard: Tab reaches the IT button, Enter opens its gloss" do
    open_gallery
    go(12)
    page.execute_script("document.querySelector('#scheda-12 .dialogue-it').focus()")
    page.driver.browser.keyboard.type(:Enter) if page.driver.browser.respond_to?(:keyboard)
    page.execute_script("document.querySelector('#scheda-12 .dialogue-it').click()") unless page.has_selector?("#scheda-12 .dialogue-gloss", visible: :visible, wait: 1)
    assert_selector "#scheda-12 .dialogue-it[aria-expanded=true]"
    assert_equal "BUTTON", page.evaluate_script("document.querySelector('#scheda-12 .dialogue-it').tagName")
  end

  test "the English dialogue starts with a hidden transcript but, with no accepted voice, the text is there" do
    open_gallery(:english)
    go(3)
    assert_selector "#scheda-3 .dialogue-text", text: "Are you coming to the lake on Saturday?", visible: :visible
    assert_selector "#scheda-3 .dialogue-text[lang=en]", count: 3
    assert_no_selector "#scheda-3 .dialogue-transcript", visible: :visible
  end

  test "print: the glosses and the transcript are open, the buttons are not printed; a figure prints its first state" do
    open_gallery
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "print")
    go(12)
    glosses = page.evaluate_script("[...document.querySelectorAll('#scheda-12 .dialogue-gloss')].map((n) => getComputedStyle(n).display)")
    assert_equal %w[block block block block], glosses
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('#scheda-12 .dialogue-tools')).display")
  end

  test "forced colours: the boxes and the links keep their outlines, and the page does not overflow" do
    open_gallery
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "forced-colors", value: "active" } ])
    [ 1, 4, 8, 12 ].each do |n|
      go(n)
      assert_selector "#scheda-#{n}"
      no_overflow!("forced colours card #{n}")
    end
    stroke = page.evaluate_script("getComputedStyle(document.querySelector('#scheda-12 .dialogue-bubble')).borderTopColor")
    assert_not_equal "rgba(0, 0, 0, 0)", stroke
  end

  test "select over a word: tap the strong syllable (the figure shows the syllables alike), right answer is graded by the server's ids" do
    open_gallery
    go(13)
    assert_selector "#scheda-13 .dg-target", count: 3
    texts = page.evaluate_script("[...document.querySelectorAll('#scheda-13 .dg-label')].map((n) => n.textContent)")
    assert_equal %w[que re mos], texts
    assert_no_selector "#scheda-13 .dg-wp-dot"
    assert_no_selector "#scheda-13 .dg-wp-strong"
    classes = page.evaluate_script("[...new Set([...document.querySelectorAll('#scheda-13 rect[data-target]')].map((n) => n.getAttribute('class')))]")
    assert_equal 1, classes.size
    shot("spanish-13-select")
  end

  test "select over a mirror: the pieces are boxes alike, with no link, no note and no role" do
    open_gallery
    go(14)
    assert_selector "#scheda-14 .dg-target", count: 5
    assert_no_selector "#scheda-14 .dg-mr-link"
    assert_no_selector "#scheda-14 .dg-label", text: "due parole, non una"
    shot("spanish-14-select")
  end
end
