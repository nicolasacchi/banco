require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# T2, the text layer and "Ascolta" in Chrome (D-282, D-283, WAVE2 1.11 and 4): language spans with their speaker, role spans of a language subject,
# code spans, the glossary (the popover and the list under the card), the card's "Ascolta" with a fake speechSynthesis, the listen check
# (the text behind "Mostra il testo", text_shown sent), mhchem, the voices of the settings page, and the shots for the look gate (BANCO_SHOT_DIR,
# text-*.png). The device is a stand-in with the voices of a Mac (Daniel, Alice, Monica, and a network voice that must never be used); the voices
# the operator accepts are put in by the test, as voices.yml will on the day. The server's clips (D-359) are played by a stand-in <audio> that records
# what it was given (window.__clips) and lets the test end or fail a clip; a test says `server: true` to have the server voices (the page's own
# voices.server), and by default they are off, so that the tests of the device voices stay about the device voices.
class LessonTextSystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  DEVICE = <<~JS.freeze
    (() => {
      const voice = (name, lang, localService = true) => ({ name, lang, localService, default: false, voiceURI: name })
      const voices = [voice("Daniel", "en-GB"), voice("Samantha", "en-US"), voice("Alice", "it-IT"), voice("Monica", "es-ES"), voice("Google UK English Female", "en-GB", false)]
      window.__spoken = []
      window.__cancels = 0
      class Utterance { constructor(text) { this.text = text } }
      const fake = {
        getVoices: () => voices, addEventListener() {}, removeEventListener() {},
        cancel() { window.__cancels += 1 },
        speak(u) { window.__spoken.push({ text: u.text, voice: u.voice && u.voice.name, lang: u.lang, rate: u.rate }); window.__utterance = u }
      }
      Object.defineProperty(window, "speechSynthesis", { value: fake, configurable: true })
      window.SpeechSynthesisUtterance = Utterance
    })();
  JS

  MOCK = <<~JS.freeze
    window.__calls = [];
    const realFetch = window.fetch.bind(window);
    const json = (o) => new Response(JSON.stringify(o), { status: 200, headers: { "content-type": "application/json" } });
    window.fetch = async (url, opts) => {
      const u = String(url);
      if (u.match(/lesson\\/checks\\/(\\d+)\\/(\\d+)/)) {
        const body = JSON.parse(opts.body);
        window.__calls.push({ url: u, body });
        return json({ verdict: "wrong", try: body.try, message_it: "Ancora un tentativo." });
      }
      if (u.includes("/lesson/events") || u.includes("/diagnosis/preferences")) { window.__calls.push({ url: u, body: opts && opts.body }); return json({ ok: true }); }
      return realFetch(url, opts);
    };
  JS

  # the <audio> that plays the clips: records the source and the rate when a clip starts; window.__clipFail makes every clip fail to load
  AUDIO = <<~JS.freeze
    (() => {
      window.__clips = []
      class FakeAudio {
        constructor() { this.paused = true; this.playbackRate = 1; this.src = "" }
        play() {
          window.__clips.push({ src: this.src, rate: this.playbackRate })
          window.__audio = this
          this.paused = false
          if (window.__clipFail) setTimeout(() => this.onerror && this.onerror(), 0)
          return Promise.resolve()
        }
        pause() { this.paused = true }
        removeAttribute(name) { if (name === "src") this.src = "" }
      }
      window.Audio = FakeAudio
    })();
  JS

  SERVER = YAML.load_file(Rails.root.join("config/banco/voices.yml")).fetch("server").freeze

  SERVER_OFF = "import('lesson/voices').then((v) => { v.default.server = null; return import('lesson/speech_device') }).then((m) => { m.configure({}); arguments[0](true) })".freeze

  ACCEPT = "import('lesson/speech_device').then((m) => { m.configure({ accepted: { it: ['Alice'], en: ['Daniel', 'Google UK English Female'], es: ['Monica'] } }); arguments[0](true) })".freeze

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

  def device!
    page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: DEVICE)
    page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: AUDIO)
  end

  def open_lesson(name = "text", size: [ 1366, 900 ], accept: false, server: false)
    build_lesson2_world(name: name, approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    device!
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 20)
    page.execute_script(MOCK)
    assert_selector ".l2-cover, .l2-card", wait: 10
    server_off! unless server
    accept! if accept
  end

  def accept! = page.evaluate_async_script(ACCEPT)
  def server_off! = page.evaluate_async_script(SERVER_OFF)
  def clips = page.evaluate_script("window.__clips")
  def end_clip = page.execute_script("window.__audio.onended()")
  def fail_clips! = page.execute_script("window.__clipFail = true")
  def wait_for_clips(n) = Timeout.timeout(5) { sleep 0.05 until clips.size >= n }
  def clip_url(voice, text) = "#{SERVER['clip_path']}/#{Digest::SHA256.hexdigest("#{SERVER['engine']}|#{voice}|#{text}")}.#{SERVER['format']}"
  def server_voice(lang, n = 1) = SERVER["voices"].fetch(lang).then { |list| list[(n - 1) % list.size] }
  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def spoken = page.evaluate_script("window.__spoken")
  def end_utterance = page.execute_script("window.__utterance.onend()")
  def reduce_motion! = page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
  def shot(name)
    sleep 0.7
    page.driver.save_screenshot(File.join(SHOT_DIR, "text-#{name}.png"), full: true)
  end

  test "a word of another language is marked with its lang and the target ink; a speaker shows only once the device has an accepted voice" do
    open_lesson
    go 1
    assert_selector "#scheda-1 .lang-en[lang='en']", text: "When I arrive, I will call you."
    assert_selector "#scheda-1 .role-time.lang-en[lang='en']", text: "when I arrive"
    assert_selector "#scheda-1 .role-time[lang='it']", text: "momento"
    assert_no_selector "#scheda-1 .speak", visible: :visible
    assert_no_selector "#scheda-1 .card-listen", visible: :visible
    accept!
    assert_selector "#scheda-1 .card-body .block .speak-inline", count: 1
    assert_selector "#scheda-1 .card-glossary .speak-inline", count: 1, text: "", wait: 2 # the example of a glossary word is English too
    assert_selector "#scheda-1 .card-listen .speak-card", text: "Ascolta"
  end

  test "a code span is literal text in the body font, with no markup inside" do
    open_lesson
    go 1
    assert_selector "#scheda-1 code.code-span", text: "Do While k < 40"
    assert_selector "#scheda-1 code.code-span", text: "soldi = soldi + 8"
    assert_equal page.evaluate_script("getComputedStyle(document.querySelector('#scheda-1 code.code-span').parentElement).fontFamily"),
                 page.evaluate_script("getComputedStyle(document.querySelector('#scheda-1 code.code-span')).fontFamily"), "the font of the text around it, not a monospace one"
  end

  test "tapping the speaker of a span says that span with the English voice, stops on a second tap, and takes the slower speed" do
    open_lesson(accept: true)
    go 1
    find("#scheda-1 .card-body .block .speak-inline").click
    assert_equal [ { "text" => "When I arrive, I will call you.", "voice" => "Daniel", "lang" => "en-GB", "rate" => 1 } ], spoken
    assert_selector "#scheda-1 .block .speak-inline[aria-pressed='true']"
    assert_selector "#scheda-1 .block .lang-en.speaking"
    end_utterance
    assert_selector "#scheda-1 .block .speak-inline[aria-pressed='false']"
    assert_no_selector "#scheda-1 .block .speaking"
    find("#scheda-1 .speak-slower").click
    find("#scheda-1 .card-body .block .speak-inline").click
    assert_equal 0.75, spoken.last["rate"], "English slowed is 0.75"
    find("#scheda-1 .card-body .block .speak-inline").click
    assert_operator page.evaluate_script("window.__cancels"), :>=, 1
  end

  test "a network voice is never used, even when it is on the accepted list (the server voices off here: with them on, the speaker shows for its clip)" do
    open_lesson
    page.evaluate_async_script("import('lesson/speech_device').then((m) => { m.configure({ accepted: { it: ['Alice'], en: ['Google UK English Female'], es: [] } }); arguments[0](true) })")
    go 1
    assert_no_selector "#scheda-1 .speak-inline", visible: :visible
    assert_selector "#scheda-1 .card-listen .speak-card"
  end

  test "the card's Ascolta reads the visible card in order, one voice per language, and what is not open stays unread" do
    open_lesson(accept: true)
    go 1
    find("#scheda-1 .speak-card").click
    texts = [ spoken.first ]
    assert_equal "Alice", spoken.first["voice"]
    assert_match(/\ADopo when il verbo sta al presente/, spoken.first["text"])
    assert_selector "#scheda-1 .speak-card[aria-pressed='true']"
    # the segments follow one another as each utterance ends
    guard = 0
    while guard < 30 && page.evaluate_script("window.__spoken.length") > texts.size - 1 && page.evaluate_script("document.querySelector('#scheda-1 .speak-card').getAttribute('aria-pressed')") == "true"
      end_utterance
      sleep 0.05
      guard += 1
    end
    all_spoken = spoken
    assert_includes all_spoken.map { |s| [ s["lang"], s["voice"] ] }, [ "en-GB", "Daniel" ]
    joined = all_spoken.map { |s| s["text"] }.join(" | ")
    assert_includes joined, "When I arrive, I will call you."
    assert_includes joined, "Do While k minore di 40", "a code span is read with the names of its symbols"
    assert_equal 1, joined.scan("Una parte della frase che non sta in piedi da sola").size, "once, from the list under the card; the popover nobody opened is not read (L10)"
    assert_selector "#scheda-1 .speak-card[aria-pressed='false']", wait: 5
  end

  test "what is behind a card that turns is read only once it is turned (L10): a reveal and a mistake" do
    open_lesson
    go 4
    read = "import('lesson/speech').then((m) => arguments[0](m.speechOf(document.querySelector('#scheda-4')).map((s) => s.text).join(' | ')))"
    before = page.evaluate_async_script(read)
    assert_includes before, "Dopo when, il verbo sta al futuro?"
    assert_includes before, "When I will arrive, I will call you."
    assert_not_includes before, "sta al presente, anche se parla del futuro"
    assert_not_includes before, "When I arrive, I will call you."
    assert_not_includes before, "Tocca per girare", "the hint is for screen readers, not for the voice"
    page.execute_script("document.querySelectorAll('#scheda-4 [aria-expanded]').forEach((b) => b.click())")
    after = page.evaluate_async_script(read)
    assert_includes after, "No: sta al presente, anche se parla del futuro."
    assert_includes after, "When I arrive, I will call you."
  end

  test "the voice stops on a card change and on Escape, and another speaker stops the one before" do
    open_lesson(accept: true)
    go 1
    find("#scheda-1 .speak-card").click
    cancels = page.evaluate_script("window.__cancels")
    go 2
    assert_operator page.evaluate_script("window.__cancels"), :>, cancels
    go 1
    find("#scheda-1 .speak-card").click
    assert_selector "#scheda-1 .speak-card[aria-pressed='true']"
    page.send_keys(:escape)
    assert_selector "#scheda-1 .speak-card[aria-pressed='false']", wait: 5
    find("#scheda-1 .speak-card").click
    find("#scheda-1 .card-body .block .speak-inline").click
    assert_selector "#scheda-1 .speak-card[aria-pressed='false']", wait: 5
    assert_selector "#scheda-1 .block .speak-inline[aria-pressed='true']"
  end

  test "a glossary word opens its definition on a tap, closes on Escape, and the card lists its words anyway" do
    open_lesson
    go 1
    assert_selector "#scheda-1 .card-glossary h3", text: "Parole di questa scheda"
    assert_selector "#scheda-1 .card-glossary-list dt", count: 3
    assert_selector "#scheda-1 .card-glossary-list dd", text: "Il tempo del verbo che dice che cosa succede adesso."
    assert_no_selector "#scheda-1 .gloss-pop", visible: :visible
    first("#scheda-1 .gloss-btn").click
    assert_selector "#scheda-1 .gloss-pop", text: "Una parte della frase che non sta in piedi da sola.", visible: :visible
    assert_equal "true", first("#scheda-1 .gloss-btn")["aria-expanded"]
    assert_operator page.evaluate_script("document.querySelector('.gloss-btn').getBoundingClientRect().width"), :>=, 24
    page.send_keys(:escape)
    assert_no_selector "#scheda-1 .gloss-pop", visible: :visible
    # the open definition is read after its word, and only when open
    first("#scheda-1 .gloss-btn").click
    speech = page.evaluate_async_script("import('lesson/speech').then((m) => arguments[0](m.speechOf(document.querySelector('#scheda-1')).map((s) => s.text).join(' ')))")
    assert_includes speech, "Una parte della frase che non sta in piedi da sola."
  end

  test "A1 the keyboard: the glossary button and the card's Ascolta are real buttons that Enter and Space work, Escape closes the bubble and gives the focus back" do
    open_lesson(accept: true)
    go 1
    # a keyboard activation of a button is a click on the focused button (the driver's key synthesis can fire it twice)
    page.execute_script("document.querySelector('#scheda-1 .gloss-btn').focus()")
    assert_equal "BUTTON", page.evaluate_script("document.activeElement.tagName"), "the word's button takes the focus"
    page.execute_script("document.activeElement.click()")
    assert_selector "#scheda-1 .gloss-pop", visible: :visible
    page.send_keys(:escape)
    assert_no_selector "#scheda-1 .gloss-pop", visible: :visible
    assert_equal "gloss-btn", page.evaluate_script("document.activeElement.className.split(' ')[0]"), "the focus is back on the word's button"
    page.execute_script("document.querySelector('#scheda-1 .speak-card').focus()")
    assert_equal "speak-card", page.evaluate_script("document.activeElement.className.split(' ').find((c) => c === 'speak-card')")
    page.execute_script("document.activeElement.click()")
    assert_selector "#scheda-1 .speak-card[aria-pressed='true']"
    assert_equal "BUTTON", page.evaluate_script("document.querySelector('#scheda-1 .speak-card').tagName")
    speaker = find("#scheda-1 .card-body .block .speak-inline")
    assert_equal "BUTTON", speaker.evaluate_script("this.tagName")
    assert_operator speaker.evaluate_script("this.getBoundingClientRect().width"), :>=, 24
  end

  test "A3 and A4 at the largest text size on a phone, and with forced colours: nothing overflows and the controls keep a border" do
    open_lesson(accept: true, size: [ 390, 844 ])
    page.execute_script("document.documentElement.dataset.size = 'larger'")
    go 1
    assert_selector "#scheda-1 .speak-card"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 391, "no sideways scroll at the largest size"
    first("#scheda-1 .gloss-btn").click
    rects = page.evaluate_script("(() => { const r = document.querySelector('#scheda-1 .gloss-pop').getBoundingClientRect(); const c = document.querySelector('#scheda-1').getBoundingClientRect(); return { pop: [r.left, r.right], card: [c.left, c.right] } })()")
    assert rects["pop"][0] >= rects["card"][0] - 1 && rects["pop"][1] <= rects["card"][1] + 1, "the bubble stays inside the card: #{rects.inspect}"
    page.send_keys(:escape)
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "forced-colors", value: "active" } ])
    go 2
    assert_selector "#scheda-2 .listen-play"
    assert_not_equal "0px", page.evaluate_script("getComputedStyle(document.querySelector('#scheda-2 .listen-play')).borderTopWidth")
    shot "forced-colors-390"
  end

  # D-335: a mark that follows a formula (a full stop, «?)», a comma) is drawn with it in one span.nowrap, so it never starts a line. The text
  # layer draws sentences that end in a formula (and one with a bracket before it) in boxes from 170 to 360 px wide, in the page's own styles;
  # a mark that is the first thing on its line is a failure, and so is a box that the wrapper makes wider than it was.
  PUNCT_SWEEP = <<~'JS'.freeze
    const done = arguments[0];
    import('lesson/text').then(({ renderRich }) => {
      const texts = ['Il risultato e $x=\\frac{1}{2}$.', 'Quindi il perimetro misura $2p=14$?)', 'Calcola ($3+4$), poi $a$.', 'Il valore di $a + b + c = d + e + f + g + h = 12345$.', 'La reazione $\\ce{2H2 + O2 -> 2H2O}$, completa.']
      const ctx = { subject: 'math', t: {}, safe: true, noSpeech: true }
      const host = document.querySelector('.l2')
      const bad = []
      let wrapped = 0
      for (let w = 170; w <= 360; w += 1) for (const [i, text] of texts.entries()) {
        const box = document.createElement('div')
        box.style.cssText = 'width:' + w + 'px;position:absolute;left:0;top:0;visibility:hidden'
        box.appendChild(renderRich(text, ctx))
        box.querySelector('p').style.margin = '0'
        host.appendChild(box)
        wrapped += box.querySelectorAll('.nowrap').length
        const walker = document.createTreeWalker(box, NodeFilter.SHOW_TEXT)
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
          if (!/^[.,;:!?)]/.test(n.nodeValue) || n.parentElement.closest('.katex')) continue
          const r = document.createRange(); r.setStart(n, 0); r.setEnd(n, 1)
          if (r.getBoundingClientRect().left <= box.getBoundingClientRect().left + 1) bad.push('alone:' + i + ':' + w)
        }
        // a formula wider than the box (the \ce one at the narrowest widths) scrolls or overflows as it always did; the wrapper adds nothing to it
        const grown = box.scrollWidth
        box.querySelectorAll('.nowrap').forEach((e) => { e.className = 'plain' })
        if (grown > box.scrollWidth + 1) bad.push('overflow:' + i + ':' + w + ':' + grown + ' vs ' + box.scrollWidth)
        host.removeChild(box)
      }
      done({ bad, wrapped })
    }).catch((e) => done({ error: String(e) }));
  JS

  test "a mark after a formula never starts a line on a phone, and the wrapper keeps the page from overflowing" do
    open_lesson(size: [ 390, 844 ])
    result = page.evaluate_async_script(PUNCT_SWEEP)
    assert_nil result["error"]
    assert_operator result["wrapped"], :>, 900, "the marks are drawn with their formulas"
    assert_empty result["bad"], "a lone mark or an overflow: #{result['bad'].first(10).inspect}"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 391
  end

  # D-335: the diagram layout measures its labels, so a formula and its mark are not glued there: a flow node «$\\Delta < 0$?» with a «sì» edge
  # was measured wider than it was drawn and the layout refused it (E-DIAGRAM-LAYOUT, two labels overlap).
  FLOW_MOUNT = <<~'JS'.freeze
    const done = arguments[0];
    (async () => {
      const { mountDiagram } = await import('lesson/diagrams/draw')
      const { load } = await import('lesson/diagrams/registry')
      await load('flow')
      const ctx = { subject: 'math', t: { description: 'Descrizione' }, fontPx: () => 20, reduced: () => false, mount: (fn) => setTimeout(fn, 0), track: () => {} }
      const out = []
      for (const label of ['$\\Delta < 0$?', '$b = c = 0$?', 'Il discriminante $\\Delta < 0$?', 'Vale $x$.']) for (let width = 200; width <= 760; width += 80) {
        const data = { type: 'flow', alt_it: 'Schema: una domanda con due risposte.',
          nodes: [{ id: 'q', kind: 'decision', text_it: label }, { id: 's', kind: 'end', text_it: 'Due soluzioni' }, { id: 'n', kind: 'end', text_it: 'Nessuna soluzione' }],
          edges: [['q', 's', 'sì'], ['q', 'n', 'no']] }
        const holder = document.createElement('div')
        holder.className = 'l2'
        holder.style.cssText = 'width:' + width + 'px;position:absolute;left:0;top:0'
        document.body.appendChild(holder)
        const api = mountDiagram(data, ctx, {})
        holder.appendChild(api.element)
        ctx.mount(api.mounted)
        await new Promise((resolve) => setTimeout(resolve, 150))
        out.push({ label, width, error: api.element.dataset.error || null, glued: api.element.querySelectorAll('.nowrap').length })
        document.body.removeChild(holder)
      }
      done(out)
    })().catch((e) => done([{ error: String(e && e.stack || e) }]));
  JS

  test "a diagram label that ends in a formula and a mark is laid out with no overlap, and is not glued" do
    open_lesson(size: [ 390, 844 ])
    results = page.evaluate_async_script(FLOW_MOUNT)
    assert_equal 32, results.size, results.inspect
    errors = results.filter_map { |r| "#{r['label']} at #{r['width']}: #{r['error']}" if r["error"] }
    assert_empty errors
    assert_equal [ 0 ], results.map { |r| r["glued"] }.uniq, "a diagram label is not glued"
  end

  test "P6 print: no speaker, no button, no bubble; the list of words under the card and the text of a heard check are on the paper" do
    open_lesson(accept: true)
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "print")
    Timeout.timeout(10) { sleep 0.1 until page.evaluate_script("matchMedia('print').matches") }
    page.execute_script("window.lessonApi.renderAll()")
    assert_selector "#scheda-1 .card-glossary", visible: :visible, wait: 10
    assert_no_selector ".speak, .gloss-btn, .gloss-pop, .card-listen", visible: :visible
    assert_selector "#scheda-2 .listen-text", visible: :visible, text: "I will call you when I get home."
  end

  test "the listen check keeps its text behind Mostra il testo, plays it with the English voice, and tells the server when the text was looked at" do
    open_lesson(accept: true)
    go 2
    assert_selector "#scheda-2 .check-listen .listen-lead", text: "Una frase da ascoltare"
    assert_selector "#scheda-2 .listen-text", visible: :hidden, text: "I will call you when I get home."
    find("#scheda-2 .listen-play").click
    assert_equal({ "text" => "I will call you when I get home.", "voice" => "Daniel", "lang" => "en-GB", "rate" => 1 }, spoken.last)
    end_utterance
    choose "Domani mattina"
    click_button "Controlla"
    assert_selector "#scheda-2 .verdict-wrong", wait: 5
    assert_not page.evaluate_script("window.__calls").last["body"].key?("text_shown"), "answered by ear"
    find("#scheda-2 .listen-show").click
    assert_selector "#scheda-2 .listen-text", text: "I will call you when I get home.", visible: :visible
    click_button "Controlla"
    assert_selector "#scheda-2 .verdict-wrong", wait: 5
    sleep 0.3
    assert_equal true, page.evaluate_script("window.__calls.filter((c) => c.url.includes('checks')).pop().body.text_shown")
  end

  test "with no server voice and no accepted device voice the listen check says so and still works by reading" do
    open_lesson
    go 2
    assert_no_selector "#scheda-2 .listen-play", visible: :visible
    assert_selector "#scheda-2 .listen-note", text: "Mostra il testo e leggilo."
    find("#scheda-2 .listen-show").click
    assert_selector "#scheda-2 .listen-text", visible: :visible
  end

  test "with server voices a speaker shows for English with no accepted device voice, fetches nothing before the tap, and plays the clip at the card's rate" do
    open_lesson(server: true)
    go 1
    assert_selector "#scheda-1 .card-body .block .speak-inline", count: 1, wait: 5
    assert_selector "#scheda-1 .card-listen .speak-card"
    assert_equal [], clips, "nothing is loaded until a speaker is pressed"
    find("#scheda-1 .card-body .block .speak-inline").click
    assert_equal [ { "src" => clip_url(server_voice("en"), "When I arrive, I will call you."), "rate" => 1 } ], clips
    assert_equal [], spoken, "the device's voice is not used when the clip plays"
    assert_selector "#scheda-1 .block .speak-inline[aria-pressed='true']"
    assert_selector "#scheda-1 .block .lang-en.speaking"
    end_clip
    assert_selector "#scheda-1 .block .speak-inline[aria-pressed='false']"
    find("#scheda-1 .speak-slower").click
    find("#scheda-1 .card-body .block .speak-inline").click
    assert_equal 0.75, clips.last["rate"], "English slowed is 0.75"
    find("#scheda-1 .card-body .block .speak-inline").click # a second tap stops it
    assert_equal true, page.evaluate_script("window.__audio.paused")
    assert_selector "#scheda-1 .block .speak-inline[aria-pressed='false']"
  end

  test "the card's Ascolta plays the clip of each visible segment in order, and the key of the page is the key of Ruby" do
    open_lesson(server: true)
    go 1
    segments = page.evaluate_async_script("import('lesson/speech').then((m) => arguments[0](m.speechOf(document.querySelector('#scheda-1')).map((s) => ({ lang: s.lang, text: s.text, voice: s.voice || 1 }))))")
    assert_operator segments.size, :>=, 3
    find("#scheda-1 .speak-card").click
    segments.size.times do |i|
      wait_for_clips(i + 1)
      end_clip
    end
    assert_equal segments.map { |s| clip_url(server_voice(s["lang"], s["voice"]), s["text"]) }, clips.map { |c| c["src"] }
    assert_selector "#scheda-1 .speak-card[aria-pressed='false']", wait: 5
    assert_equal [], spoken
  end

  test "a clip that is missing is said by the accepted device voice, and with none the segment is skipped; a network voice is never used" do
    open_lesson(server: true, accept: true)
    fail_clips!
    go 1
    find("#scheda-1 .card-body .block .speak-inline").click
    Timeout.timeout(5) { sleep 0.05 until spoken.size >= 1 }
    assert_equal [ { "text" => "When I arrive, I will call you.", "voice" => "Daniel", "lang" => "en-GB", "rate" => 1 } ], spoken
    end_utterance
    assert_selector "#scheda-1 .block .speak-inline[aria-pressed='false']"
    # only the network voice is accepted: the clip fails and nothing is said at all
    page.evaluate_async_script("import('lesson/speech_device').then((m) => { m.configure({ accepted: { it: [], en: ['Google UK English Female'], es: [] } }); arguments[0](true) })")
    find("#scheda-1 .card-body .block .speak-inline").click
    wait_for_clips(2)
    assert_selector "#scheda-1 .block .speak-inline[aria-pressed='false']", wait: 5
    assert_equal 1, spoken.size, "the network voice said nothing"
  end

  test "the listen check plays its clip with the first English voice; with no server voice and no accepted device voice it says so" do
    open_lesson(server: true)
    go 2
    assert_selector "#scheda-2 .listen-play", visible: :visible, wait: 5
    assert_no_selector "#scheda-2 .listen-note", visible: :visible
    find("#scheda-2 .listen-play").click
    assert_equal [ { "src" => clip_url(server_voice("en"), "I will call you when I get home."), "rate" => 1 } ], clips
    assert_equal [], spoken
    end_clip
    page.evaluate_async_script("import('lesson/voices').then((v) => { v.default.server = { ...v.default.server, voices: { it: [], en: [], es: [] } }; return import('lesson/speech_device') }).then((m) => { m.configure({}); arguments[0](true) })")
    assert_no_selector "#scheda-2 .listen-play", visible: :visible, wait: 5
    assert_selector "#scheda-2 .listen-note", text: "Mostra il testo e leggilo."
  end

  test "Prova le voci also offers each server voice with its sample clip, and a missing clip says so instead of using the device voice" do
    build_lesson2_world(name: "text", approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    device!
    visit "about:blank"
    visit "/settings"
    assert_selector "#voci .voice-server", count: 5, wait: 10
    assert_equal SERVER["voices"].values.flatten.map { |id| SERVER.dig("names", id, "it") }, all("#voci .voice-server .voice-name").map(&:text), "friendly names, never the ids (D-378)"
    assert_equal [], clips
    find("#voci .voice-server", text: SERVER.dig("names", SERVER["voices"]["en"][1], "it")).click_button "Prova"
    assert_equal [ { "src" => clip_url(SERVER["voices"]["en"][1], "Hello, this is my voice."), "rate" => 1 } ], clips
    end_clip
    find("#voci .voice-server", text: SERVER.dig("names", SERVER["voices"]["it"][0], "it")).click_button "Prova"
    assert_equal clip_url(SERVER["voices"]["it"][0], "Ciao, questa è la mia voce."), clips.last["src"]
    end_clip
    fail_clips!
    row = find("#voci .voice-server", text: SERVER.dig("names", SERVER["voices"]["es"][1], "it"))
    row.click_button "Prova"
    assert_selector "#voci .voice-server .voice-status", text: "non è ancora pronta", wait: 5
    assert_equal [], spoken
  end

  test "a cloze keeps its cue in the prompt and an English word in the prompt reads as English" do
    open_lesson
    go 3
    assert_selector "#scheda-3 .check-prompt .lang-en", text: "When I ___ (get) home, I will call you."
  end

  test "chemistry: \\ce and \\pu are drawn by KaTeX with mhchem, and a formula is read by its atoms" do
    open_lesson("text_chemistry")
    go 1
    assert_selector "#scheda-1 .katex", minimum: 4, wait: 10
    assert_no_selector "#scheda-1 .katex-error"
    assert_includes page.evaluate_script("document.querySelector('#scheda-1 .katex').textContent"), "H"
    speech = page.evaluate_async_script("import('lesson/speech').then((m) => arguments[0](m.speechOf(document.querySelector('#scheda-1')).map((s) => s.text).join(' | ')))")
    assert_includes speech, "tre molecole: 6 atomi di idrogeno e 3 di ossigeno"
    assert_includes speech, "25 kJ su mol"
    shot "chemistry-1366"
  end

  test "Prova le voci: each local voice of the device has its name, whether it is accepted, and a button that says a fixed sentence with that voice" do
    build_lesson2_world(name: "text", approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    device!
    visit "about:blank"
    visit "/settings"
    assert_selector "#voci h2", text: "Prova le voci"
    assert_selector "#voci .voice-row", minimum: 4, wait: 10
    server_off! # this case is about the device's voices: the server's are in the next one
    assert_selector "#voci .voice-row", count: 4, wait: 10 # the network voice is not offered
    assert_no_selector "#voci .voice-name", text: "Google UK English Female"
    row = find("#voci .voice-row", text: "Daniel")
    assert_includes row.text, "non ancora scelta"
    row.click_button "Prova"
    assert_equal "Daniel", spoken.last["voice"]
    assert_equal "Hello, this is my voice. When I arrive, I will call you.", spoken.last["text"]
    find("#voci .voice-row", text: "Monica").click_button "Prova"
    assert_equal "Hola, esta es mi voz. Cuando llegue, te llamaré.", spoken.last["text"]
  end

  test "the settings dialog of a lesson has the Ascolta switch and the way to the voices, and the choices go to the server" do
    open_lesson(accept: true)
    find(".l2-settingsbtn").click
    assert_selector ".l2-settingsdialog [type=checkbox]", minimum: 2
    assert_selector ".l2-settingsdialog a[href='/settings#voci']", text: "Prova le voci"
    find(".l2-settingsdialog label", text: "Ascolta con la voce del dispositivo").click
    sleep 0.2
    assert_includes page.evaluate_script("window.__calls.map((c) => String(c.body))").join(" "), "listen=false"
    click_button "Chiudi"
    go 1
    assert_no_selector "#scheda-1 .speak-card", visible: :visible
  end

  test "screenshots for the look gate: the english card with speakers, a glossary word open, the listen check; cream at 1366 and 390, dark at 1366" do
    open_lesson(accept: true)
    reduce_motion!
    go 1
    assert_selector "#scheda-1 .block .speak-inline"
    shot "english-1366"
    first("#scheda-1 .gloss-btn").click
    shot "gloss-open-1366"
    page.send_keys(:escape)
    go 2
    find("#scheda-2 .listen-show").click
    shot "listen-1366"
    page.execute_script("document.documentElement.dataset.theme = 'dark'")
    shot "listen-dark-1366"
    go 1
    shot "english-dark-1366"
    page.execute_script("document.documentElement.dataset.theme = 'cream'")
    page.driver.resize(390, 844)
    go 1
    shot "english-390"
    first("#scheda-1 .gloss-btn").click
    shot "gloss-open-390"
    page.send_keys(:escape)
    go 2
    shot "listen-390"
    go 3
    shot "cloze-390"
  end

  test "D-335 a language span in the filled first box of a flow keeps the box's own ink, in every theme" do
    open_lesson("text_flow", size: [ 1280, 900 ])
    go 1
    assert_selector "#scheda-1 .dg-start", wait: 20
    assert_selector "#scheda-1 .dg-starttext .lang-en[lang='en']", text: "Have you ever been to London?"
    probe = <<~JS
      (() => {
        const span = document.querySelector("#scheda-1 .dg-starttext .lang-en")
        return { span: getComputedStyle(span).color, text: getComputedStyle(span.closest(".dg-starttext")).color, fill: getComputedStyle(document.querySelector("#scheda-1 .dg-start")).fill, weight: getComputedStyle(span).fontWeight }
      })()
    JS
    %w[cream dark].each do |theme|
      page.execute_script("document.documentElement.dataset.theme = '#{theme}'")
      got = page.evaluate_script(probe)
      assert_equal got["text"], got["span"], "#{theme}: the span takes the box's ink"
      assert_not_equal got["fill"], got["span"], "#{theme}: the span is not the colour of the fill"
      assert_operator got["weight"].to_i, :>=, 650, "#{theme}: the span keeps its weight"
    end
    page.execute_script("document.documentElement.dataset.theme = 'cream'")
  end
end
