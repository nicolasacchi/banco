require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# The check components of T1 in Chrome (WAVE2 2.11, A1 to A10): tiles and ordering in a real lesson page (the keyboard, the how-to line on the
# first use only, "Come si risponde", the answer the page sends), select over a probe figure (no available figure type offers targets yet),
# the stylesheet at 1366 and 390, and screenshots for the look gate (BANCO_SHOT_DIR). The check endpoint is answered by a stand-in that logs
# what the page sends, so these tests are about the browser's side; Lessons::Checks and the endpoint are in test/lib and test/integration.
class LessonChecksSystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  MOCK = <<~JS.freeze
    window.__calls = [];
    window.__right = window.__right || {};
    const realFetch = window.fetch.bind(window);
    const json = (o) => new Response(JSON.stringify(o), { status: 200, headers: { "content-type": "application/json" } });
    window.fetch = async (url, opts) => {
      const u = String(url);
      const m = u.match(/lesson\\/checks\\/(\\d+)\\/(\\d+)/);
      if (m) {
        const body = JSON.parse(opts.body);
        window.__calls.push({ url: u, body });
        const right = window.__right[m[1] + "/" + m[2]] === body.response;
        return json({ verdict: right ? "right" : "wrong", try: body.try, message_it: right ? null : "Guarda l'ordine delle parole." });
      }
      if (u.includes("/lesson/events")) return json({ ok: true });
      return realFetch(url, opts);
    };
  JS

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

  def open_lesson(size: [ 1366, 900 ])
    build_lesson2_world(name: "checks", approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 20)
    page.execute_script(MOCK)
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  # screenshots are taken with reduced motion: a card's entrance animation restarts when the driver resizes the page for a full-height shot
  def reduce_motion! = page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def shot(name)
    sleep 0.7 # the card transition (300 ms) and the figure redraw are over
    page.driver.save_screenshot(File.join(SHOT_DIR, "checks-#{name}.png"), full: true)
  end

  def calls = page.evaluate_script("window.__calls")
  def line_text = all("#scheda-2 .tiles-line .tile-built").map(&:text)

  def tap_tile(text, card: 2) = find("#scheda-#{card} .tiles-bank .tile-bank:not(.is-used)", text: text, exact_text: true).click

  test "tiles: a tap puts a word in the line, a tap on it takes it back, the bank keeps its place, Svuota empties" do
    open_lesson
    go 2
    assert_selector "#scheda-2 .tiles"
    assert_equal [], line_text
    assert_selector "#scheda-2 .tiles-empty", visible: :visible
    %w[If it rains,].each { |w| tap_tile(w) }
    assert_equal %w[If it rains,], line_text
    assert_selector "#scheda-2 .tile-bank.is-used", count: 3
    assert_selector "#scheda-2 .tiles-bank .tile-bank", count: 9, wait: 1
    find("#scheda-2 .tile-built", text: "it", exact_text: true).click
    assert_equal %w[If rains,], line_text
    assert_selector "#scheda-2 .tile-bank.is-used", count: 2
    click_button "Svuota"
    assert_equal [], line_text
    assert_selector "#scheda-2 .tile-bank.is-used", count: 0
    assert_selector "#scheda-2 button.tiles-clear[disabled]"
  end

  test "tiles: the answer the page sends is the list of shown ids in the line (as JSON text, which the endpoint reads as data)" do
    open_lesson
    go 2
    ids = page.evaluate_script("[...document.querySelectorAll('#scheda-2 .tiles-bank .tile-bank')].map((b) => [b.dataset.id, b.textContent])").to_h { |id, text| [ text, id ] }
    page.execute_script("window.__right['2/2'] = #{%w[If it rains, I will stay home].map { |w| ids.fetch(w) }.to_json.to_json}")
    %w[I will stay home].each { |w| tap_tile(w) }
    click_button "Controlla"
    assert_selector "#scheda-2 .verdict-wrong", wait: 5
    sent = calls.last["body"]
    assert_equal %w[I will stay home].map { |w| ids.fetch(w) }, JSON.parse(sent["response"])
    assert_equal "Guarda l'ordine delle parole.", find("#scheda-2 .verdict-text").text
    click_button "Svuota"
    %w[If it rains, I will stay home].each { |w| tap_tile(w) }
    click_button "Controlla"
    assert_selector "#scheda-2 .verdict-right", wait: 5
    assert_selector "#scheda-2 .tile[disabled]", minimum: 1
  end

  test "tiles: the keyboard builds the sentence, the arrows move a tile, Delete is not needed" do
    open_lesson
    go 2
    assert_selector "#scheda-2 .tiles-bank .tile-bank", count: 9
    bank = all("#scheda-2 .tiles-bank .tile-bank").map(&:text)
    next_after = ->(word, taken) { (bank.drop(bank.index(word) + 1) - taken).first }
    # a keyboard activation of a button is a click on the focused button (the key synthesis of the driver can fire it twice)
    press = ->(word) { page.evaluate_script("(() => { const b = [...document.querySelectorAll('#scheda-2 .tile-bank')].find((x) => x.textContent === #{word.to_json}); b.focus(); b.click(); return document.activeElement.textContent })()") }
    # the focus moved to the next free tile of the bank (the bank is in the student's shuffled order)
    assert_equal next_after.call("If", [ "If" ]), press.call("If")
    press.call("it")
    assert_equal [ "If", "it" ], line_text
    page.execute_script("const t = [...document.querySelectorAll('#scheda-2 .tile-built')].find((x) => x.textContent === 'it'); t.focus(); t.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }))")
    assert_equal %w[it If], line_text
    assert_equal "it", page.evaluate_script("document.activeElement.textContent"), "the moved tile keeps the focus"
    assert_equal "Ora è al posto 1 di 2.", find("#scheda-2 .tiles [role=status]", visible: :all).text(:all)
  end

  test "the how-to line is printed on the first use of a component in the lesson only; 'Come si risponde' is under every use" do
    open_lesson
    go 2
    assert_selector "#scheda-2 .howto", text: "Tocca le parole nell'ordine giusto. Per toglierne una, toccala di nuovo."
    go 3
    assert_selector "#scheda-3 .howto", text: "Usa Su e Giù per mettere le voci in ordine, poi premi Controlla."
    go 4
    assert_selector "#scheda-4 .tiles"
    assert_no_selector "#scheda-4 .howto"
    assert_selector "#scheda-4 details.howto-help summary", text: "Come si risponde"
    find("#scheda-4 details.howto-help summary").click
    assert_selector "#scheda-4 .howto-help li", minimum: 3
    assert_selector "#scheda-4 .howto-example", text: "Esempio:"
  end

  test "ordering: Su and Giù move an item, the ends are disabled, the answer is the list of ids in the new order" do
    open_lesson
    go 3
    assert_selector "#scheda-3 .order-item", count: 4
    texts = -> { all("#scheda-3 .order-item .order-text").map(&:text) }
    before = texts.call
    assert_equal 4, before.size
    assert_selector "#scheda-3 .order-item:first-child .order-up[disabled]"
    assert_selector "#scheda-3 .order-item:last-child .order-down[disabled]"
    first("#scheda-3 .order-item .order-down:not([disabled])").click
    after = texts.call
    assert_equal [ before[1], before[0] ], after.first(2)
    assert_equal "Ora è al posto 2 di 4.", find("#scheda-3 .ordering [role=status]", visible: :all).text(:all)
    click_button "Controlla"
    assert_selector "#scheda-3 .feedback .verdict", wait: 5
    sent = JSON.parse(calls.last["body"]["response"])
    assert_equal 4, sent.size
    assert_equal 4, sent.uniq.size
  end

  test "ordering with the keyboard: Alt and the arrows on an item" do
    open_lesson
    go 3
    assert_selector "#scheda-3 .order-item", count: 4
    before = all("#scheda-3 .order-item .order-text").map(&:text)
    page.execute_script("document.querySelector('#scheda-3 .order-item .order-down').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', altKey: true, bubbles: true }))")
    assert_equal [ before[1], before[0] ], all("#scheda-3 .order-item .order-text").map(&:text).first(2)
  end

  # A figure type that offers targets, only for this test: no available type has any yet (each track adds its own). Eight identical zones in
  # two rows (four columns, three on a phone); the select check is built by the page's own renderCheck, the same code the lesson uses.
  PROBE = <<~JS.freeze
    (async () => {
      const reg = await import("lesson/diagrams/registry")
      const checks = await import("lesson/checks/registry")
      const { renderCheck } = await import("lesson/blocks/check")
      await checks.load("select")
      const zone = (i, width) => {
        const cols = width < 420 ? 3 : 4
        const w = Math.floor((width - 16 - (cols - 1) * 12) / cols)
        const h = 74
        return { x: 8 + (i % cols) * (w + 12), y: 8 + Math.floor(i / cols) * (h + 12), w, h }
      }
      reg.TYPES.probe = {
        layout: (data, ctx) => {
          const boxes = data.zones.map((_, i) => zone(i, ctx.width))
          const rows = Math.ceil(boxes.length / (ctx.width < 420 ? 3 : 4))
          return { width: ctx.width, height: 16 + rows * 86, labels: [], shapes: boxes.map((b, i) => ({ kind: "rect", x: b.x, y: b.y, w: b.w, h: b.h, r: 12, cls: "dg-cell", key: "zone:" + i, target: "t" + (i + 1) })) }
        },
        describe: () => "Otto zone uguali, in due file.",
        targets: (data) => data.zones.map((_, i) => ({ key: "z" + (i + 1), bbox: zone(i, 360), neutral_it: i < 4 ? "nella fila in alto" : "nella fila in basso" }))
      }
      const root = document.getElementById("lesson-root")
      const labels = JSON.parse(root.dataset.lesson2LabelsValue)
      const mounts = []
      const ctx = {
        subject: "english", t: labels, items: {}, safe: false, teacher: false, preview: false, firstUse: new Map(), unavailableTopics: [],
        fontPx: () => parseFloat(getComputedStyle(root).fontSize) || 20, reduced: () => false, mount: (fn) => mounts.push(fn), track: () => {},
        postCheck: async (loc, payload) => { (window.__calls ||= []).push({ body: payload }); return { verdict: "wrong", try: 1, message_it: "Guarda bene la figura." } }, cardNumber: () => 1
      }
      const spec = { component: "select", pick: "many", prompt_it: "Tocca le zone nella fila in alto.", targets: "zones", diagram: { type: "probe", alt_it: "Otto zone uguali, in due file, da toccare.", zones: Array.from({ length: 8 }, (_, i) => i) } }
      const { locKey } = await import("lesson/checks/howto")
      ctx.firstUse.set("select", locKey({ card: 1, block: 1 }))
      const host = document.createElement("article")
      host.className = "l2-card"
      host.id = "probe-card"
      host.style.cssText = "max-width:46em;margin:1em auto"
      host.appendChild(renderCheck(spec, ctx, { card: 1, block: 1 }).element)
      document.querySelector(".l2-stage").prepend(host)
      mounts.forEach((fn) => fn())
      window.__probeReady = true
    })().catch((e) => { window.__probeError = String(e && e.stack || e) })
  JS

  def open_probe(size: [ 1366, 900 ])
    open_lesson(size: size)
    page.execute_script(PROBE)
    begin
      assert_selector "#probe-card .dg-target", count: 8, wait: 10
    rescue Capybara::ExpectationNotMet
      raise "the probe did not draw: #{page.evaluate_script('window.__probeError')}"
    end
  end

  def tab_stops = page.evaluate_script(%q(document.querySelectorAll('#probe-card .dg-target[tabindex="0"]').length))
  def zones_on = all("#probe-card .dg-target.is-on").map { |b| b["data-target"] }

  test "select: tap targets toggle, a live line counts them, the answer is the sorted list of tN, a check button is there" do
    open_probe
    assert_selector "#probe-card .howto", text: "Tocca le zone giuste, poi premi Controlla."
    assert_equal "Nessuna zona selezionata.", find("#probe-card .select-live").text
    find("#probe-card .dg-target[data-target='t3']").click
    find("#probe-card .dg-target[data-target='t1']").click
    assert_equal %w[t1 t3], zones_on
    assert_equal "Selezionate: 2", find("#probe-card .select-live").text
    assert_equal "true", find("#probe-card .dg-target[data-target='t3']")["aria-pressed"]
    find("#probe-card .dg-target[data-target='t3']").click
    assert_equal %w[t1], zones_on
    find("#probe-card .dg-target[data-target='t2']").click
    click_button "Controlla"
    assert_selector "#probe-card .verdict-wrong", wait: 5
    assert_equal %w[t1 t2], JSON.parse(calls.last["body"]["response"])
    assert_equal "Guarda bene la figura.", find("#probe-card .verdict-text").text
  end

  test "select: every zone is named 'zona n di N' with the neutral description, never a name; one tab stop; arrows go to the nearest zone" do
    open_probe
    labels = all("#probe-card .dg-target").map { |b| b["aria-label"] }
    assert_equal "zona 1 di 8, nella fila in alto", labels.first
    assert_equal "zona 8 di 8, nella fila in basso", labels.last
    assert_equal 1, tab_stops
    page.execute_script(%q(document.querySelector('#probe-card .dg-target[tabindex="0"]').focus()))
    key = ->(name) { page.execute_script("document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: '#{name}', bubbles: true }))") }
    active = -> { page.evaluate_script("document.activeElement.dataset.target") }
    assert_equal "t1", active.call
    key.call("ArrowRight")
    assert_equal "t2", active.call
    key.call("ArrowDown")
    assert_equal "t6", active.call
    key.call("ArrowLeft")
    assert_equal "t5", active.call
    key.call("ArrowUp")
    assert_equal "t1", active.call
    key.call("ArrowUp")
    assert_equal "t1", active.call, "nothing above: the focus stays"
    key.call("End")
    assert_equal "t8", active.call
    assert_equal 1, tab_stops
  end

  test "select: the zones are alike before the student taps, and at least 24 px at 390" do
    open_probe(size: [ 390, 844 ])
    styles = page.evaluate_script("[...document.querySelectorAll('#probe-card .dg-stage rect')].map((r) => { const s = getComputedStyle(r); return [s.fill, s.stroke, r.getAttribute('class')].join('|') })")
    assert_equal 1, styles.uniq.size, "every candidate has the same style: #{styles.uniq.inspect}"
    sizes = page.evaluate_script("[...document.querySelectorAll('#probe-card .dg-target')].map((b) => { const r = b.getBoundingClientRect(); return [r.width, r.height] })")
    assert sizes.all? { |w, h| w >= 24 && h >= 24 }, sizes.inspect
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth + 1")
  end

  test "targets are at least 24 px and the controls fit at 390 px" do
    open_lesson(size: [ 390, 844 ])
    go 2
    sizes = page.evaluate_script("[...document.querySelectorAll('#scheda-2 .tile, #scheda-2 .tiles-clear')].map((b) => { const r = b.getBoundingClientRect(); return [r.width, r.height] })")
    assert sizes.all? { |w, h| w >= 24 && h >= 24 }, sizes.inspect
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth + 1")
    go 3
    sizes = page.evaluate_script("[...document.querySelectorAll('#scheda-3 .order-move')].map((b) => { const r = b.getBoundingClientRect(); return [r.width, r.height] })")
    assert sizes.all? { |w, h| w >= 24 && h >= 24 }, sizes.inspect
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth + 1")
  end

  test "screenshots for the look gate: tiles and ordering, cream at 1366 and 390, dark at 1366" do
    reduce_motion!
    open_lesson
    go 2
    %w[If it rains, I will].each { |w| tap_tile(w) }
    shot "tiles-1366"
    go 3
    first("#scheda-3 .order-item .order-down:not([disabled])").click
    shot "ordering-1366"
    page.execute_script("document.querySelector('#lesson-root').closest('[data-theme]')?.setAttribute('data-theme', 'dark'); document.documentElement.dataset.theme = 'dark'")
    shot "ordering-dark-1366"
    go 2
    shot "tiles-dark-1366"
    page.execute_script("document.documentElement.dataset.theme = 'cream'")
    page.driver.resize(390, 844)
    go 2
    shot "tiles-390"
    go 3
    shot "ordering-390"
    go 1
    shot "sentence-english-390"
  end

  test "screenshots for the look gate: select, cream at 1366 and 390, dark at 1366" do
    reduce_motion!
    open_probe
    find("#probe-card .dg-target[data-target='t2']").click
    find("#probe-card .dg-target[data-target='t6']").click
    find("#probe-card .dg-target[data-target='t6']").send_keys(:tab) # the focus ring on a neighbour
    shot "select-1366"
    page.execute_script("document.documentElement.dataset.theme = 'dark'")
    shot "select-dark-1366"
    page.execute_script("document.documentElement.dataset.theme = 'cream'")
    page.driver.resize(390, 844)
    sleep 0.5
    shot "select-390"
  end
end

# The teacher's box in teacher mode: a tiles, an ordering and a select answer is read by its words and names (WAVE2 5.4), never by e1 or tN.
require_relative "../support/decision_world"
require_relative "../support/topic_world"

class LessonChecksTeacherBoxTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession
  include TopicWorld

  def full_body
    body = JSON.parse(File.read(Rails.root.join("test/fixtures/lesson2/served/checks.json")))
    tiles = body["cards"][1]["blocks"][1]
    tiles.merge!("answer" => %w[a b c d e f g], "accept" => [ %w[d e f g a b c] ],
                 "errors" => [ { "answer" => %w[a b h d e f g], "code" => "en_past_in_if", "message_it" => "Dopo if serve il presente." } ], "explain_it" => "Dopo if il verbo sta al presente.")
    ordering = body["cards"][2]["blocks"][1]
    ordering.merge!("answer" => %w[p q r s], "errors" => [ { "answer" => %w[q p r s], "message_it" => "Prima il soggetto." } ])
    body
  end

  def lesson_revision_with_body!(key, skill)
    lesson = Lesson.find_by(key: key) || Lesson.create!(subject: Subject.find_by!(key: key.split(".", 3)[1]), key: key, kind: "ripasso")
    md = "---\nkey: #{key}\n---\n"
    LessonRevision.create!(lesson: lesson, seq: 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(full_body.merge("key" => key, "skills" => [ skill ])),
                           rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  setup do
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  test "Modalità docente: the built sentence, the accepted order, the coded error and the ordering, by their words" do
    page.driver.resize(1280, 1000)
    visit "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}"
    assert_selector ".l2-box [data-ready='1']", wait: 20
    check "Modalità docente"
    assert_no_selector "[data-lesson2-preview-target=status]", text: "non sono disponibili"
    find(".l2-box .l2-start").click
    # card 2 (tiles) and card 3 (ordering)
    click_button(class: "l2-next")
    assert_selector ".l2-box #scheda-2 .teacher-notes", wait: 10
    notes = find(".l2-box #scheda-2 .teacher-notes").text
    assert_includes notes, "If it rains, I will stay home"
    assert_includes notes, "Dopo if serve il presente."
    assert_includes notes, "en_past_in_if"
    assert_no_match(/\be\d\b/, notes, "no shown id in the teacher's notes")
    click_button(class: "l2-next")
    assert_selector ".l2-box #scheda-3 .teacher-notes", wait: 10
    notes = find(".l2-box #scheda-3 .teacher-notes").text
    assert_includes notes, "Scegli il soggetto → Scegli il verbo → Aggiungi il resto → Rileggi la frase"
    assert_includes notes, "Prima il soggetto."
  end
end
