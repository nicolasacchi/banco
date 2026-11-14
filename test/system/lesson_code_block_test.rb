require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# The `code` block on the student's page in Chrome (D-329): the program keeps its spaces and never wraps, a long line scrolls inside the box and the
# page does not grow (390 px), "Copia" puts the text of the block on the clipboard exactly and "Copiato" shows. The gallery of the block
# (test/fixtures/lesson2/gallery/code.md) is the lesson. Screenshots go to BANCO_SHOT_DIR (code-*.png) for the look gate.
class LessonCodeBlockSystemTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))
  GALLERY = Rails.root.join("test/fixtures/lesson2/gallery/code.md")

  def lesson_body
    @gallery_body ||= Lessons::Parser2.call(GALLERY.read, Validation::Findings.new).body.merge("key" => TOPIC)
  end

  def program(card) = lesson_body["cards"].find { |c| c["n"] == card }["blocks"].find { |b| b["type"] == "code" }

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
    build_student_world(approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
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

  def open_lesson(size)
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 20)
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "code-#{name}.png"), full: true)

  def no_overflow!(where)
    over = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    assert_operator over, :<=, 1, "#{where}: the page is #{over} px wider than the window"
  end

  # A clipboard that keeps what it is given, as a headless page has none it may use.
  def stub_clipboard!
    page.execute_script(<<~JS)
      window.__copied = []
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: (text) => { window.__copied.push(text); return Promise.resolve() } } })
    JS
  end

  test "at 390 px every card is drawn with no overflow, and the box of the long line scrolls inside the card" do
    open_lesson([ 390, 844 ])
    (1..4).each do |n|
      go(n)
      assert_selector "#scheda-#{n} .block-code"
      no_overflow!("card #{n}")
      assert_no_selector "#scheda-#{n} .block-unavailable"
      shot("card#{n}-390")
    end
    go(3)
    box = page.evaluate_script(<<~JS)
      (() => {
        const pre = document.querySelector("#scheda-3 .code-box")
        const style = getComputedStyle(pre)
        const rect = pre.getBoundingClientRect()
        return { whiteSpace: style.whiteSpace, overflowX: style.overflowX, scrolls: pre.scrollWidth > pre.clientWidth + 3, right: rect.right, window: window.innerWidth, tab: pre.getAttribute("tabindex") }
      })()
    JS
    assert_equal "pre", box["whiteSpace"], "the program never wraps"
    assert_equal "auto", box["overflowX"]
    assert box["scrolls"], "the line of 90 characters is wider than the box and scrolls in it"
    assert_operator box["right"], :<=, box["window"], "the box stays inside the window"
    assert_equal "0", box["tab"], "the keyboard can reach the box to scroll it"
  end

  test "the box shows the program as written: every space, the empty lines, the lines apart" do
    open_lesson([ 1280, 900 ])
    [ 1, 2, 3, 4 ].each do |n|
      go(n)
      text = page.evaluate_script("document.querySelector('#scheda-#{n} .code-box code').textContent")
      assert_equal program(n)["text"].chomp, text, "card #{n}"
    end
    go(2)
    lines = page.evaluate_script("(() => { const pre = document.querySelector('#scheda-2 .code-box'); const s = getComputedStyle(pre); return (pre.clientHeight - parseFloat(s.paddingTop) - parseFloat(s.paddingBottom)) / parseFloat(s.lineHeight) })()")
    assert_in_delta 13, lines, 0.1, "thirteen lines, one under the other, none wrapped"
    assert_equal "35000", page.evaluate_script("document.querySelector('#scheda-2 .code-key').textContent")
    assert_text "Scrivi:"
    assert_text "Sullo schermo vedi:"
    shot("card2-1280")
  end

  test "\"Copia\" copies the text of the block exactly and \"Copiato\" shows on the button" do
    open_lesson([ 390, 844 ])
    stub_clipboard!
    [ 1, 2, 3 ].each do |n|
      go(n)
      within("#scheda-#{n}") { click_button "Copia" }
      assert_selector "#scheda-#{n} .code-copy.is-copied", text: "Copiato", wait: 5
      assert_equal program(n)["text"], page.evaluate_script("window.__copied[window.__copied.length - 1]"), "card #{n}"
    end
    assert_equal 3, page.evaluate_script("window.__copied.length")
    assert_selector "#scheda-3 .code-copy", text: "Copia", exact_text: true, wait: 6
    shot("copied-390")
  end

  test "in the dark theme at 390 px the boxes are drawn and nothing grows the page" do
    open_lesson([ 390, 844 ])
    page.execute_script("document.documentElement.setAttribute('data-theme', 'dark')")
    [ 2, 3 ].each do |n|
      go(n)
      assert_selector "#scheda-#{n} .code-box"
      no_overflow!("dark card #{n}")
      shot("card#{n}-dark-390")
    end
  end
end
