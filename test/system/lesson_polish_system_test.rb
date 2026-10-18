require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# The renderer problems the authors reported in wave 3 (D-310), in the student's page: the galleries test/fixtures/lesson2/gallery/polish-spanish.md
# and polish-math.md, parsed and stored as an author's lesson would be (the page projects them with Lessons::StudentBody). On a phone and on a
# desktop: the column names of a stacked table carry their markup and the caption is the table's width, cases titles and choice options draw
# their markup with no control inside an option, a cases title and a mistakes group that mix words and markup read as one line of text, an
# ordering with long sentences fits and still moves by button and key, tiles say neutral words unless they build a sentence, a typed answer
# stays on the line of its formula. BANCO_SHOT_DIR keeps screenshots.
class LessonPolishSystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
  end

  teardown do
    begin
      page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "prefers-reduced-motion", value: "no-preference" } ])
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def gallery_body(name)
    findings = Validation::Findings.new
    body = Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/#{name}.md").read, findings).body
    assert_empty findings.errors.map(&:to_h), name
    body
  end

  def lesson_body = @gallery ? gallery_body(@gallery).merge("key" => TOPIC) : super

  def open_gallery(name, size, build: true)
    @gallery = name
    build_lesson2_world(name: nil, approve: false, release: false) if build
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 20)
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  def go(n)
    page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
    assert_selector "#scheda-#{n}", visible: :visible
    sleep 0.4 # the figures of the card are drawn
  end

  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "polish-#{name}.png"), full: true)
  def js(script) = page.evaluate_script(script)

  # every text of the card as it shows, without the formulas KaTeX drew (their MathML holds the TeX), the closed description and the measure probe
  def card_text(n) = js("(() => { const c = document.querySelector('#scheda-#{n}').cloneNode(true); c.querySelectorAll('.katex, .dg-desc, .dg-measure').forEach((k) => k.remove()); return c.textContent })()")

  # A title drawn with markup inside a flex head (a case's head beside its icon, a mistakes group's heading) is one line of text, not one
  # column per piece: the head holds one title span besides its icon, and in the title the first two pieces (words, then a word of another
  # language or a formula) sit on one line, a space apart, with the next piece starting on that line or below it, never above.
  def assert_titles_flow(n, head, title)
    report = js(<<~JS)
      [...document.querySelectorAll('#scheda-#{n} #{head}')].map((h) => {
        const others = [...h.childNodes].filter((c) => !(c.nodeType === 1 && c.matches('svg, .ic')) && !(c.nodeType === 3 && !c.nodeValue.trim()))
        const t = h.querySelector('#{title}')
        const pieces = t ? [...t.childNodes].filter((c) => (c.nodeType === 3 ? c.nodeValue.trim() : !c.matches('button'))) : []
        const boxes = (p) => { if (p.nodeType === 1) return p.getClientRects(); const r = document.createRange(); r.selectNodeContents(p); return r.getClientRects() }
        const rects = pieces.map((p) => [...boxes(p)].filter((x) => x.width > 0))
        const em = parseFloat(getComputedStyle(h).fontSize)
        let flows = true
        if (rects.length >= 2) {
          const a = rects[0][rects[0].length - 1], b = rects[1][0]
          flows = a.top < b.bottom && b.top < a.bottom && b.left - a.right >= -1 && b.left - a.right < 0.45 * em
          if (rects.length >= 3) flows = flows && rects[2][0].top >= b.top - 1
        }
        return { text: h.textContent.trim(), single: others.length === 1 && others[0] === t, pieces: pieces.length, flows }
      })
    JS
    assert_not_empty report, "#{head} on card #{n}"
    report.each do |r|
      assert r["single"], "one title span in the head: #{r.inspect}"
      assert r["flows"], "the title reads as one line of text: #{r.inspect}"
    end
    report
  end

  test "spanish on a phone: stacked column names, a full-width caption, cases titles, a mirror inside its boxes, options with their words" do
    open_gallery("polish-spanish", [ 390, 844 ])
    go 1
    labels = all("#scheda-1 .dg-table td .cell-label", visible: :visible)
    assert_equal 6, labels.size
    assert_equal "hablar:", labels.first.text.strip
    assert_selector "#scheda-1 .dg-table td .cell-label .lang[lang=es]", text: "hablar"
    widths = js("(() => { const t = document.querySelector('#scheda-1 .dg-table'); return [t.querySelector('caption').getBoundingClientRect().width, t.getBoundingClientRect().width] })()")
    assert_operator widths[0], :>=, widths[1] - 2, "the caption is as wide as the table (#{widths.inspect})"
    assert_no_match(/\[\[/, card_text(1))
    shot("spanish-table-390")

    go 2
    assert_selector "#scheda-2 .block-title .lang[lang=es]", text: "comer"
    assert_selector "#scheda-2 .case-head .case-title .lang[lang=es]", text: "comer"
    assert_selector "#scheda-2 .case-head .case-title .lang[lang=es]", text: "vivir"
    assert_no_match(/\[\[/, card_text(2))

    go 3
    # the verb's text stays inside its box: the box of each mirror text contains the text's own range
    inside = js(<<~JS)
      [...document.querySelectorAll('#scheda-3 .dg-mr-text')].every((label) => {
        const r = document.createRange(); r.selectNodeContents(label); const t = r.getBoundingClientRect()
        const cx = (t.left + t.right) / 2, cy = (t.top + t.bottom) / 2
        const box = [...document.querySelectorAll('#scheda-3 .dg-node')].map((n) => n.getBoundingClientRect()).find((b) => cx >= b.left && cx <= b.right && cy >= b.top && cy <= b.bottom)
        return !box || (t.left >= box.left + 2 && t.right <= box.right - 2)
      })
    JS
    assert inside, "every mirror text is inside its box"
    assert_selector "#scheda-3 .option .option-text .lang[lang=es]", text: "vivimos"
    assert_selector "#scheda-3 .option strong .lang[lang=es]", text: "viven"
    assert_no_selector "#scheda-3 .option button, #scheda-3 .option a"
    assert_no_match(/\[\[/, card_text(3))
    shot("spanish-mirror-390")
  end

  test "spanish on a phone and on a desktop: a cases title and a mistakes group with a Spanish word read as one line of text" do
    [ [ 390, 844 ], [ 1280, 900 ] ].each do |size|
      open_gallery("polish-spanish", size, build: size.first == 390)
      go 2
      titles = assert_titles_flow(2, ".case-head", ".case-title")
      assert_equal [ 3, 2, 2 ], titles.map { |t| t["pieces"] }, titles.inspect # the long title is words, a Spanish word, words
      shot("spanish-cases-#{size.first}")

      go 6
      groups = assert_titles_flow(6, ".mistakes-group", ".mistakes-group-title")
      assert_equal [ "La persona noi di vivir" ], groups.map { |g| g["text"] }
      assert_selector "#scheda-6 .mistakes-group .lang[lang=es]", text: "vivir"
      # inside each card's button the group is said in plain words: no markup printed as text, anywhere on the card
      assert_equal [ " (La persona noi di vivir)" ] * 2, js("[...document.querySelectorAll('#scheda-6 .mistake-wrong .sr-only')].map((s) => s.textContent)")
      assert_no_match(/\[\[/, card_text(6))
      shot("spanish-mistakes-#{size.first}")
    end
  end

  test "spanish on a phone: a long ordering fits and moves by button and by key; tiles say neutral words unless they build a sentence" do
    open_gallery("polish-spanish", [ 390, 844 ])
    go 4
    sizes = js("(() => { const l = document.querySelector('#scheda-4 .order-list'); return [l.scrollWidth, l.clientWidth, document.documentElement.scrollWidth, window.innerWidth] })()")
    assert_operator sizes[0], :<=, sizes[1] + 1, "the list fits its box (#{sizes.inspect})"
    assert_operator sizes[2], :<=, sizes[3] + 1, "the page fits the window (#{sizes.inspect})"
    items = -> { all("#scheda-4 .order-item .order-text").map(&:text) }
    before = items.call
    all("#scheda-4 .order-item")[0].find(".order-down").click
    assert_equal [ before[1], before[0], *before[2..] ], items.call
    # Alt with the down arrow on the first item moves it back down: the first order again
    page.execute_script("document.querySelector('#scheda-4 .order-item').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', altKey: true, bubbles: true }))")
    assert_equal before, items.call
    assert_no_match(/\[\[/, all("#scheda-4 .order-move").map { |b| b["aria-label"] }.join(" "))
    shot("spanish-ordering-390")

    go 5
    first, second = all("#scheda-5 .tiles").to_a
    assert_equal [ "La tua risposta", "Le tessere" ], first.all(".tiles-label").map(&:text)
    assert_equal "Tocca le tessere qui sotto.", first.find(".tiles-empty").text
    assert_equal [ "La tua frase", "Le parole" ], second.all(".tiles-label").map(&:text)
    assert_selector "#scheda-5 .howto", text: "Tocca le tessere nell'ordine giusto."
    shot("spanish-tiles-390")
  end

  test "maths on a phone and on a desktop: bar labels and table headers draw their formulas, quoted math draws, a typed answer stays with its formula" do
    [ [ 390, 844 ], [ 1280, 900 ] ].each do |size|
      open_gallery("polish-math", size, build: size.first == 390)
      go 1
      assert_selector "#scheda-1 .dg-label .katex", minimum: 4
      assert_no_match(/\$|\^/, card_text(1))
      # the hint of the box is above the line, and the formula and the box are on one line
      order = js("[...document.querySelector('#scheda-1 form.check').children].map((c) => c.className || c.tagName)")
      assert_operator order.index { |c| c.include?("hint") }, :<, order.index { |c| c.include?("check-row") }, order.inspect
      tops = js("(() => { const row = document.querySelector('#scheda-1 .check-row.is-around'); return [row.querySelector('.check-before').getBoundingClientRect(), row.querySelector('input').getBoundingClientRect()].map((r) => [r.top, r.bottom]) })()")
      assert_operator tops[0][0], :<, tops[1][1], "the formula and the box share a line (#{tops.inspect})"
      assert_operator tops[1][0], :<, tops[0][1], "the formula and the box share a line (#{tops.inspect})"
      shot("math-bar-#{size.first}")

      go 2
      assert_selector "#scheda-2 .dg-table thead th .katex", count: 3
      assert_selector "#scheda-2 .block-math .katex", count: 2
      assert_no_selector "#scheda-2 .katex-error"
      assert_no_match(/\$|\^|'|"/, card_text(2))
      assert_selector("#scheda-2 .dg-table td .cell-label .katex", minimum: 4) if size.first == 390
      shot("math-table-#{size.first}")

      go 3
      assert_selector "#scheda-3 .block-title .katex"
      assert_selector "#scheda-3 .case-head .case-title .katex", count: 3
      titles = assert_titles_flow(3, ".case-head", ".case-title")
      assert_equal [ 1, 1, 3 ], titles.map { |t| t["pieces"] }, titles.inspect # the long title is words, a formula, words
      assert_selector "#scheda-3 .option .option-text .katex", count: 3
      assert_no_match(/\$|\\role/, card_text(3))
      shot("math-cases-#{size.first}")
    end
  end
end
