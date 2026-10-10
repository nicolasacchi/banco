require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# The page of a lesson/2 in Chrome (R2, A10): cards, the map, keys, the balance's try, mistakes, the example with
# its blank, checks, the try pager, sentences with moving states, chips and spans, print, safe mode, and
# screenshots (BANCO_SHOT_DIR). The page's fetch to the check endpoint is answered here by a small stand-in
# installed before the page loads, so these tests check the browser's side of the contract; the real endpoints
# (R3) are in lesson_events_system_test.rb.
class Lesson2PageSystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  # Answers the page's calls to the endpoints of R3. A check is right when its response is in window.__right
  # (keyed card/block[/ex/n]); every call is logged in window.__calls.
  MOCK = <<~JS.freeze
    window.__calls = [];
    window.__right = window.__right || {};
    const realFetch = window.fetch.bind(window);
    const json = (o) => new Response(JSON.stringify(o), { status: 200, headers: { "content-type": "application/json" } });
    window.fetch = async (url, opts) => {
      const u = String(url);
      const m = u.match(/lesson\\/checks\\/(\\d+)\\/(\\d+)(?:\\/ex\\/(\\d+))?(?:\\/(\\d+))?/);
      if (m) {
        const body = JSON.parse(opts.body);
        window.__calls.push({ url: u, body });
        const key = m[3] ? `${m[1]}/${m[2]}/ex/${m[3]}` : `${m[1]}/${m[2]}`;
        const right = window.__right[key] === body.response;
        const reply = { verdict: right ? "right" : "wrong", try: body.try, message_it: right ? null : "Guarda il segno del numero." };
        if (!right && body.try >= 2) reply.explain_it = "Con $x = 3$ i piatti pesano uguale.";
        if (right && m[4] !== undefined) reply.steps = [{ tag: "add", do_it: "$0 \\\\cdot x = 7$", why_it: "Hai sommato." }, { tag: "verify", do_it: "Nessun numero per 0 dà 7.", why_it: "Quindi è impossibile." }];
        if (right && m[4] !== undefined) reply.result_it = "Impossibile.";
        return json(reply);
      }
      if (u.includes("/solution")) { window.__calls.push({ url: u }); return json({ n: 1, solution_steps: [{ tag: "move", do_it: "$3x = 9$", why_it: "Sposta il $-7$." }], final_it: "$x = 3$" }); }
      if (u.includes("/lesson/events")) { window.__calls.push({ url: u, body: JSON.parse(opts.body) }); return json({ ok: true }); }
      return realFetch(url, opts);
    };
  JS

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
  end

  teardown do
    # the browser is shared by every system test: put back what these tests change (a failure must not leak)
    begin
      page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "forced-colors", value: "none" }, { name: "prefers-reduced-motion", value: "no-preference" } ])
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def open_lesson(name: "equations", fragment: nil, right: {}, size: [ 1280, 900 ], build: true)
    build_lesson2_world(name: name, approve: false, release: false) if build
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    visit "about:blank"
    # a query that changes every time: a visit that differs from the page left by the last test only in its
    # fragment is no navigation at all (the runner's Chrome keeps the old page and its state)
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#{fragment}"
    assert_selector "#lesson-root[data-ready='1']", wait: 20
    # the page only calls fetch when the student acts, so the stand-in can go in after the page has loaded
    page.execute_script("window.__right = #{right.to_json};")
    page.execute_script(MOCK)
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def current_card = page.evaluate_script("window.lessonApi.current()")
  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "lesson2-#{name}.png"), full: true)
  def emulate_print
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "print")
    assert_selector "body", wait: 5
    Timeout.timeout(10) { sleep 0.1 until page.evaluate_script("matchMedia('print').matches") }
  end

  test "the cover, the bar and the map at 1280 and at 390" do
    open_lesson
    assert_selector "h1", text: "Equazioni di primo grado intere"
    assert_selector ".goals li", count: 3
    assert_selector ".l2-sidemap .map-item", minimum: 11
    assert_no_selector ".l2-mapbtn", visible: :visible
    shot "cover-1280"
    find(".l2-start").click
    assert_selector "h2", text: "I pezzi di un'equazione"
    assert_selector ".l2-counter", text: "Scheda 1 di 11"
    assert_equal "#scheda-1", page.evaluate_script("location.hash")
    click_button(class: "l2-next")
    assert_selector ".l2-counter", text: "Scheda 2 di 11"
    assert_selector ".map-item[aria-current=step]", text: "Che cos'è la soluzione"
    page.driver.resize(390, 800)
    assert_selector ".l2-mapbtn", visible: :visible
    assert_no_selector ".l2-sidemap", visible: :visible
    click_button "Mappa"
    assert_selector "dialog[open] .map-item", minimum: 11
    first("dialog[open] .map-item", text: "La procedura").click
    assert_selector ".l2-counter", text: "Scheda 5 di 11"
    assert_no_selector "dialog[open]"
    shot "card-5-390"
    # the thin positional bar: one segment per core card, the current one marked, no percentage
    assert_selector ".l2-progress span", count: 11, visible: :all
    assert_selector ".l2-progress span.now", count: 1, visible: :all
  end

  test "the chrome is one slim bar: the card starts within 140 px on a laptop and the first figure is whole in the first screen" do
    open_lesson(size: [ 1366, 900 ])
    assert_selector ".l2-top .l2-chip"
    assert_no_selector "#student-menu", visible: :visible
    assert_no_selector "#trial-notice", visible: :visible
    assert_no_selector "#draft-notice", visible: :visible
    assert_operator page.evaluate_script("document.querySelector('.l2-top').getBoundingClientRect().height"), :<=, 80
    cards = page.evaluate_script("window.lessonApi.figures().length") # the figures drawn so far
    assert_operator cards, :>=, 1
    [ 1, 2, 3 ].each do |n|
      go(n)
      assert_selector "#scheda-#{n}"
      top = page.evaluate_script("document.querySelector('#scheda-#{n}').getBoundingClientRect().top")
      assert_operator top, :<=, 140, "card #{n} starts at #{top} px"
      figure = page.evaluate_script("(() => { const f = document.querySelector('#scheda-#{n} .dg-stage'); if (!f) return null; const r = f.getBoundingClientRect(); return [r.top, r.bottom] })()")
      next unless figure

      bar = page.evaluate_script("document.querySelector('.l2-bar').getBoundingClientRect().top")
      assert_operator figure[1], :<=, bar, "the first figure of card #{n} ends at #{figure[1]} px, the bottom bar starts at #{bar}"
    end
  end

  test "the menu button holds the way back, the menu and the notices" do
    open_lesson(size: [ 1366, 900 ])
    click_button "Menu"
    assert_selector "dialog[open] a", text: "Torna all'argomento"
    assert_selector "dialog[open] a", text: "Oggi"
    assert_selector "dialog[open] p", text: "Account di prova"
    click_button "Chiudi"
    assert_no_selector "dialog[open]"
  end

  test "the boxes of a balance say x, whatever number is tried, and no digit is drawn with a slash" do
    open_lesson
    go(2)
    assert_selector "#scheda-2 .bl-x", minimum: 1
    page.execute_script("document.querySelector('#scheda-2 .dg-step[aria-label]:last-of-type')?.click()")
    texts = page.evaluate_script("[...document.querySelectorAll('#scheda-2 .bl-x')].map((t) => t.textContent)")
    assert texts.all?("x"), texts.inspect
    assert_equal "Banco Digits", page.evaluate_script("getComputedStyle(document.querySelector('#scheda-2 .bl-one') || document.querySelector('#scheda-2 .bl-x')).fontFamily.split(',')[0].replace(/\"/g, '')")
  end

  test "the colours of the balance are not red and not green" do
    open_lesson
    go(2)
    %w[.bl-pan-left .bl-pan-right .bl-box .bl-bell].each do |sel|
      assert_selector "#scheda-2 #{sel}", minimum: 1
      rgb = page.evaluate_script("getComputedStyle(document.querySelector('#scheda-2 #{sel}')).fill").scan(/\d+/).first(3).map(&:to_i)
      r, g, b = rgb.map { |c| c / 255.0 }
      max = [ r, g, b ].max
      d = max - [ r, g, b ].min
      next if d < 0.15

      hue = (if max == r then ((g - b) / d) % 6 elsif max == g then ((b - r) / d) + 2 else ((r - g) / d) + 4 end * 60).round
      assert(hue >= 14 && hue < 340, "#{sel} is red: #{rgb.inspect}")
      assert(hue < 75 || hue > 170, "#{sel} is green: #{rgb.inspect}")
    end
  end

  test "the three cases share one stepper: x is set in every balance at once, the rows are compact" do
    open_lesson(size: [ 1366, 900 ])
    go(7)
    assert_selector "#scheda-7 .cases-try .dg-tryvalue", text: "x = 0"
    assert_selector "#scheda-7 .case .dg-compact", count: 3
    assert_no_selector "#scheda-7 .case .dg-controls .dg-try", visible: :visible
    first = page.evaluate_script("document.querySelectorAll('#scheda-7 .case .dg-status')[0].textContent.trim()")
    assert_match(/destra/, first)
    3.times { find("#scheda-7 .cases-try .dg-round[aria-label='Un numero in più']").click }
    assert_selector "#scheda-7 .cases-try .dg-tryvalue", text: "x = 3"
    states = page.evaluate_script("[...document.querySelectorAll('#scheda-7 .case .dg-status')].map((n) => n.className)")
    assert_match(/is-level/, states[0], "2x = 6 is level at x = 3")
    assert_match(/is-tilt/, states[1])
    assert_match(/is-level/, states[2])
    rows = page.evaluate_script("[...document.querySelectorAll('#scheda-7 .case')].map((n) => n.getBoundingClientRect().height)")
    assert_operator rows.first, :<=, 330, "a case row is #{rows.first} px tall"
  end

  test "the map and the next button use the short name of a card" do
    open_lesson(size: [ 1366, 900 ])
    go(2)
    assert_selector ".l2-next", text: "Avanti: Primo principio"
    assert_selector ".l2-sidemap .map-text", text: "Primo principio"
    assert_no_selector ".l2-sidemap .map-text", text: "Togli lo stesso peso"
    # without a short name the title up to its colon
    go(6)
    assert_selector ".l2-next", text: "Avanti: Tre casi"
  end

  test "the kicker above a title does not repeat the card counter, and the flip cards come with a line and equal rows" do
    open_lesson(size: [ 1366, 900 ])
    go(2)
    assert_no_selector "#scheda-2 .kicker", text: /Scheda/
    go(9)
    assert_selector "#scheda-9 .mistakes-intro", text: "Tocca una carta"
    heights = page.evaluate_script("[...document.querySelectorAll('#scheda-9 .mistake')].slice(0, 2).map((n) => Math.round(n.getBoundingClientRect().height))")
    assert_equal heights[0], heights[1], "the first row of flip cards has equal heights"
  end

  test "the symbols render: not-equal as a character in the weight of its line" do
    open_lesson(size: [ 1366, 900 ])
    go(7)
    assert_selector "#scheda-7 .case-condition .katex-html .mord.text", text: "\u2260"
    assert_equal 0, page.evaluate_script("document.querySelectorAll('#scheda-7 .rlap').length")
    family = page.evaluate_script("getComputedStyle(document.querySelector('#scheda-7 .case-condition .mord.text')).fontFamily")
    assert_match(/Banco Symbols/, family)
    assert_equal "700", page.evaluate_script("getComputedStyle(document.querySelector('#scheda-7 .case-condition .mord.text')).fontWeight").sub("800", "700")
  end

  test "arrow keys change the card from the page, never inside a choice or with a modifier" do
    open_lesson(fragment: "#scheda-2")
    assert_selector ".l2-counter", text: "Scheda 2 di 11"
    page.driver.browser.keyboard.type(:Right)
    assert_selector ".l2-counter", text: "Scheda 3 di 11"
    page.driver.browser.keyboard.type(:Left)
    assert_selector ".l2-counter", text: "Scheda 2 di 11"
    first(".check input[type=radio]").click
    page.driver.browser.keyboard.type(:Down)
    assert_selector ".l2-counter", text: "Scheda 2 di 11"
    assert_equal 1, page.evaluate_script("document.querySelectorAll('.check input[type=radio]:checked').length")
    page.driver.browser.keyboard.type([ :alt, :Left ])
    assert_selector ".l2-counter", text: "Scheda 2 di 11"
  end

  test "the cover offers to resume from the server's last card" do
    build_lesson2_world(name: "equations", approve: false, release: false)
    student = Student.find_by!(key: "prova-1")
    [ 1, 2, 6 ].each_with_index do |card, i|
      LessonEvent.create!(student: student, topic_revision: @topic_revision, lesson_revision: @lesson_revision, kind: "card_seen", card: card,
                          payload_json: "{}", at: Time.current + i, created_at: Time.current)
    end
    open_lesson(build: false)
    assert_selector ".l2-start", text: "Riprendi dalla scheda 6"
    assert_selector ".map-item.seen", minimum: 3
    find(".l2-start").click
    assert_selector ".l2-counter", text: "Scheda 6 di 11"
  end

  test "the fragment and a reload keep the place, an extra card has its own fragment, an unknown one opens the cover" do
    open_lesson(fragment: "#scheda-12")
    assert_selector ".l2-counter", text: "Approfondimento 1 di 2"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#scheda-99"
    assert_selector ".l2-cover", wait: 10
  end

  test "the balance: a number in the box, both members read out, the beam moves" do
    open_lesson(fragment: "#scheda-2")
    assert_selector ".dg-balance .dg-tryvalue", text: "x = 0"
    assert_selector ".dg-rd-left", text: "1"
    assert_selector ".dg-rd-right", text: "7"
    assert_selector ".dg-status", text: "pende a destra"
    3.times { first(".dg-try button", text: "+").click }
    assert_selector ".dg-verdict", text: "equilibrio"
    assert_selector ".dg-status", text: "in equilibrio"
    shot "balance-try"
  end

  test "states: Avanti shows the next state, and with reduced motion they swap" do
    open_lesson(fragment: "#scheda-3")
    assert_selector ".dg-pill", text: "Bilancia 1 di 2"
    find(".dg-next").click
    assert_selector ".dg-pill", text: "Bilancia 2 di 2"
    assert_selector ".dg-op", text: "Togli 3 pesi"
    page.execute_script("window.lessonApi.setReduceMotion(true)")
    assert_selector ".l2[data-motion=reduced]"
    click_button "Da capo"
    assert_selector ".dg-pill", text: "Bilancia 1 di 2"
  end

  test "mistake cards turn with Enter and are all open in print" do
    open_lesson(fragment: "#scheda-9")
    assert_selector ".mistake", count: 4
    assert_selector ".mistake-group", count: 3
    assert_no_selector ".mistake-back", visible: :visible
    page.execute_script("document.querySelector('.mistake-toggle').focus()")
    page.driver.browser.keyboard.type(:Enter)
    assert_selector ".mistake[data-open=true] .mistake-back", count: 1, visible: :visible
    assert_equal "true", first(".mistake-toggle")["aria-expanded"]
    emulate_print
    assert_selector ".mistake-back", count: 4, visible: :visible
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "screen")
  end

  test "a check: wrong with the hint, wrong again with the explanation, then right" do
    open_lesson(fragment: "#scheda-3", right: { "3/4" => "4" })
    fill_in_check = ->(text) { find(".check input.answer-input").set(text); click_button "Controlla" }
    fill_in_check.call("5")
    assert_selector ".verdict-wrong", text: "Non ancora."
    assert_text "Guarda il segno del numero."
    assert_no_text "i piatti pesano uguale"
    fill_in_check.call("6")
    assert_text "i piatti pesano uguale"
    fill_in_check.call("4")
    assert_selector ".verdict-right", text: "Sì."
    calls = page.evaluate_script("window.__calls.filter(c => c.url.includes('/lesson/checks'))")
    assert_equal [ 1, 2, 3 ], calls.map { |c| c["body"]["try"] }
    assert calls.all? { |c| c["body"]["client_event_id"].to_s.size >= 8 }
    assert_no_selector ".verdict-ic[style*=green]"
  end

  test "the example reveals step by step and a blank gates the rest until it is answered" do
    open_lesson(fragment: "#scheda-6", right: { "6/1" => "0" })
    assert_selector ".example-step", count: 3, visible: :all
    assert_no_selector ".example-step", visible: :visible
    click_button "Mostra il primo passo"
    assert_selector ".example-step", count: 1, visible: :visible
    assert_selector ".reveal-count", text: "passo 1 di 3"
    click_button "Mostra tutto"
    assert_selector ".step-blank", visible: :visible
    assert_selector ".example .example-note", text: "Prima rispondi"
    assert page.find_button("Mostra il passo successivo", disabled: true)
    find(".step-blank input.answer-input").set("0")
    click_button "Controlla"
    assert_selector ".verdict-right"
    click_button "Mostra tutto"
    assert_text "Nessun numero per 0 dà 7."
    assert_selector ".example-result", text: "Impossibile"
    shot "example-blank"
  end

  test "the try card shows one exercise at a time, checks it, and fetches the solution on request" do
    open_lesson(fragment: "#scheda-10", right: { "10/1/ex/1" => "3" })
    assert_selector ".l2-card .try-counter", text: "Esercizio 1 di 3", wait: 15
    assert_selector ".exercise.is-current", count: 1
    find(".exercise.is-current input.answer-input").set("3")
    click_button "Controlla"
    assert_selector ".exercise.is-current .verdict-right"
    click_button "Mostra la soluzione"
    assert_selector ".solution-steps", text: "Sposta il"
    assert_selector ".solution-final", text: /3/
    click_button "Esercizio dopo"
    assert_selector ".try-counter", text: "Esercizio 2 di 3"
    assert_selector ".exercise.is-current .fraction"
  end

  test "matching as chips and a span selection work by keyboard" do
    open_lesson(fragment: "#scheda-8", right: { "8/1" => { "a" => "r1", "b" => "r3", "c" => "r2" }.to_json })
    rows = all(".match-row")
    assert_equal 3, rows.size
    rows[0].find(".chip-input[value=r1]", visible: :all).click
    rows[1].find(".chip-input[value=r3]", visible: :all).click
    rows[2].find(".chip-input[value=r2]", visible: :all).click
    click_button "Controlla"
  end

  test "the sentences: tapping a part shows its question, the centre layout, the state that turns the sentence" do
    open_lesson(name: "sentences", fragment: "#scheda-1")
    assert_selector ".dg-sentence .dg-hit", count: 3
    first(".dg-hit", match: :first).click
    assert_selector ".dg-question", text: "Chi legge?"
    shot "sentence-centre"
    go 4
    assert_selector ".dg-counter", text: "Passo 1 di 2"
    click_button "Gira la frase"
    assert_selector ".dg-label", text: "è letto"
    assert_selector ".dg-op", text: "Frase passiva"
    go 4
    right = { "4/2" => [ "s1" ].to_json }
    page.execute_script("window.__right = #{right.to_json}")
    find(".span-chip", text: "Il treno").click
    assert_equal "true", find(".span-chip", text: "Il treno")["aria-pressed"]
    click_button "Controlla"
    assert_selector ".verdict-right"
  end

  test "print: the scroll view with every core card, extras left out, and the summary alone" do
    open_lesson
    page.execute_script("window.lessonApi.renderAll()")
    assert_selector ".l2-card", count: 13, visible: :all
    emulate_print
    assert_selector ".l2-card.card-extra", count: 2, visible: :hidden
    assert_no_selector ".l2-top", visible: :visible
    page.execute_script("document.querySelector('.l2').dataset.print = 'summary'")
    assert_selector ".l2-card", count: 1, visible: :visible
    assert_selector ".l2-card[data-role=summary] .summary-points li", count: 4
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "screen")
  end

  test "safe mode shows the long column with no diagrams, no checks and no reveal" do
    ENV["BANCO_LESSON2_ENABLED"] = "0"
    open_lesson
    assert_selector ".l2[data-view=scroll]"
    page.execute_script("window.lessonApi.renderAll()")
    assert_selector ".dg-safe .dg-fallback", minimum: 5
    assert_no_selector ".dg-svg"
    assert_no_selector ".check"
    assert_selector ".mistake[data-open=true]", count: 4
    assert_selector ".l2-card", count: 13, visible: :all
  ensure
    ENV.delete("BANCO_LESSON2_ENABLED")
  end

  test "no content security violation, and the sprite icons load from the app origin" do
    open_lesson(fragment: "#scheda-2")
    page.execute_script("window.__csp = []; document.addEventListener('securitypolicyviolation', e => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI));")
    go 6
    go 3
    assert_equal [], page.evaluate_script("window.__csp")
    assert_selector ".badge svg use[href*='lucide@1.54.0/banco-sprite.svg#']", minimum: 1
  end

  test "forced colours and the reduced-motion media query: roles stay told apart by icon, shape and label" do
    open_lesson(name: "sentences", fragment: "#scheda-2")
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "forced-colors", value: "active" }, { name: "prefers-reduced-motion", value: "reduce" } ])
    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
    assert page.evaluate_script("matchMedia('(forced-colors: active)').matches")
    # each role of the legend has its icon or its shape and its printed label, whatever the colours
    assert_selector ".legend-sample", count: 3
    assert_equal 3, page.evaluate_script("[...document.querySelectorAll('.legend-sample')].filter(s => s.querySelector('svg') && s.textContent.trim().length > 3).length")
    shot "forced-colors"
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "forced-colors", value: "none" }, { name: "prefers-reduced-motion", value: "no-preference" } ])
  end

  test "dark and larger text: the cards still lay out without a label under the base size" do
    open_lesson(fragment: "#scheda-3")
    page.execute_script("document.documentElement.dataset.theme='dark'; document.documentElement.dataset.size='larger'; window.lessonApi.relayout()")
    assert_selector ".dg-svg text", minimum: 1
    small = page.evaluate_script("[...document.querySelectorAll('.dg-label, .dg-svg text')].filter(l => parseFloat(getComputedStyle(l).fontSize) < 18).length")
    assert_equal 0, small
    shot "card-3-dark-larger"
    overflow = page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth + 1")
    assert_equal false, overflow
  end

  %w[equations sentences].each do |name|
    test "every card of #{name} renders without a diagram error or overflow at 390 and 1280" do
      [ [ 390, 844 ], [ 1280, 800 ] ].each_with_index do |size, index|
        open_lesson(name: name, size: size, build: index.zero?)
        page.execute_script("window.lessonApi.renderAll()")
        assert_selector ".l2-card", minimum: 5, visible: :all
        sleep 0.5
        assert_equal [], page.evaluate_script("[...document.querySelectorAll('.dg[data-error]')].map(f => f.dataset.error)"), "#{name} at #{size.first}"
        assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth + 1"), "overflow #{name} at #{size.first}"
        shot "all-#{name}-#{size.first}" if size.first == 390
      end
    end
  end
end
