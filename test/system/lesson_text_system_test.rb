require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# T2, the text layer and "Ascolta" in Chrome (D-281, D-282, WAVE2 1.11 and 4): language spans with their speaker, role spans of a language subject,
# code spans, the glossary (the popover and the list under the card), the card's "Ascolta" with a fake speechSynthesis, the listen check
# (the text behind "Mostra il testo", text_shown sent), mhchem, the voices of the settings page, and the shots for the look gate (BANCO_SHOT_DIR,
# text-*.png). The device is a stand-in with the voices of a Mac (Daniel, Alice, Monica, and a network voice that must never be used); the voices
# the operator accepts are put in by the test, as voices.yml will on the day.
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
  end

  def open_lesson(name = "text", size: [ 1366, 900 ], accept: false)
    build_lesson2_world(name: name, approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    device!
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    assert_selector "#lesson-root[data-ready='1']", wait: 20
    page.execute_script(MOCK)
    assert_selector ".l2-cover, .l2-card", wait: 10
    accept! if accept
  end

  def accept! = page.evaluate_async_script(ACCEPT)
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

  test "a network voice is never used, even when it is on the accepted list" do
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

  test "on a device with no accepted voice the listen check says so and still works by reading" do
    open_lesson
    go 2
    assert_no_selector "#scheda-2 .listen-play", visible: :visible
    assert_selector "#scheda-2 .listen-note", text: "Mostra il testo e leggilo."
    find("#scheda-2 .listen-show").click
    assert_selector "#scheda-2 .listen-text", visible: :visible
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
end
