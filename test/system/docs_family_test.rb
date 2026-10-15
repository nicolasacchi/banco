require "application_system_test_case"
require_relative "../support/docs_family_world"
require_relative "../support/student_session"

# The docs family in Chrome (T8): the gallery lesson of the family drawn by the student's page. The invoice in its two views, the legal
# source with its switch, the reveal as a flip card and as a crossroads, the oral with its outline, and the flip card of a mistake that now
# shares its turning with the reveal. Screenshots go to BANCO_SHOT_DIR (docs-<card>-<width>.png) for the look gate.
class DocsFamilySystemTest < ApplicationSystemTestCase
  include DocsFamilyWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))
  CARDS = { 1 => "fattura", 2 => "cascata", 3 => "legge", 4 => "bivio", 5 => "errore", 6 => "esempio", 7 => "orale", 8 => "errori", 9 => "prova", 10 => "sintesi" }.freeze
  SIZES = { "1366" => [ 1366, 900 ], "390" => [ 390, 844 ] }.freeze

  # The page's calls to the check endpoint, answered here: the oral's outline is right when it is o1..o4 in the shown order of the key.
  MOCK = <<~JS.freeze
    window.__calls = [];
    const realFetch = window.fetch.bind(window);
    const json = (o) => new Response(JSON.stringify(o), { status: 200, headers: { "content-type": "application/json" } });
    window.fetch = async (url, opts) => {
      const u = String(url);
      const m = u.match(/lesson\\/checks\\/(\\d+)\\/(\\d+)/);
      if (m) {
        const body = JSON.parse(opts.body);
        window.__calls.push({ url: u, body });
        if (m[1] === "7") {
          const right = JSON.stringify(body.response) === JSON.stringify(window.__oralKey);
          const reply = { verdict: right ? "right" : "wrong", try: body.try };
          if (!right) reply.message_it = "Prima si toglie lo sconto, poi si aggiungono le spese.";
          if (right || body.try >= 2) reply.model_it = "Parto dal lordo. Poi tolgo gli sconti.";
          return json(reply);
        }
        return json({ verdict: "wrong", try: body.try });
      }
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

  def open_gallery(size: [ 1366, 900 ])
    build_lesson2_world(approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 20)
    page.execute_script(MOCK)
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "docs-#{name}.png"), full: true)

  def no_overflow!(where)
    over = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    assert_operator over, :<=, 1, "#{where}: the page is #{over} px wider than the window"
  end

  SIZES.each do |label, size|
    test "every card of the gallery is drawn at #{label} px with no finding of the layout, and looks calm (shots)" do
      open_gallery(size: size)
      CARDS.each do |n, name|
        go(n)
        assert_selector "#scheda-#{n}"
        assert_no_selector "#scheda-#{n} .dg-failed"
        assert_no_selector "#scheda-#{n} .block-unavailable"
        no_overflow!("card #{n}")
        shot("#{n}-#{name}-#{label}")
      end
    end
  end

  test "the cards of the family in the dark theme (shots): nothing disappears and the page does not overflow" do
    open_gallery
    page.execute_script("document.documentElement.setAttribute('data-theme', 'dark')")
    [ 1, 3, 4, 5, 7 ].each do |n|
      go(n)
      assert_selector "#scheda-#{n}"
      no_overflow!("dark card #{n}")
      shot("#{n}-#{CARDS.fetch(n)}-dark")
    end
    go(2)
    4.times { find("#scheda-2 .dg-next").click }
    shot("2-cascata-last-dark")
  end

  test "the invoice: the sheet draws the rows with their amounts and the hidden ones as boxes that say nothing" do
    open_gallery
    go(1)
    assert_selector "#scheda-1 .dg-document .dg-label", text: "€ 2.319,20"
    assert_selector "#scheda-1 .dg-document .dg-label", text: "Imponibile"
    go(5)
    assert_selector "#scheda-5 .dg-document .dg-doc-q", text: "?", count: 2
    texts = page.evaluate_script("document.querySelector('#scheda-5 .dg-document').textContent")
    assert_no_match(/259,20|329,28/, texts)
    details = page.evaluate_script("document.querySelector('#scheda-5 .dg-desc p').textContent")
    assert_match(/da calcolare/, details)
    assert_no_match(/329,28/, details)
  end

  SIZES.each do |label, size|
    test "the cascade at its last step shows the whole waterfall at #{label} px (shot)" do
      open_gallery(size: size)
      go(2)
      4.times { find("#scheda-2 .dg-next").click }
      assert_no_selector "#scheda-2 .dg-failed", wait: 3
      assert_selector "#scheda-2 .dg-op", text: "Aggiungi le spese anticipate"
      assert_selector "#scheda-2 .dg-doc-bar", count: 8
      assert_selector "#scheda-2 .dg-doc-fence"
      no_overflow!("cascade last step")
      shot("2-cascata-last-#{label}")
    end
  end

  test "the cascade moves with Avanti and the fence appears with the imponibile" do
    open_gallery
    go(2)
    assert_selector "#scheda-2 .dg-document"
    assert_selector "#scheda-2 .dg-counter", text: "1 di 5"
    assert_no_selector "#scheda-2 .dg-doc-fence"
    3.times { find("#scheda-2 .dg-next").click }
    assert_selector "#scheda-2 .dg-doc-fence"
    assert_selector "#scheda-2 .dg-op", text: "Calcola l'IVA"
  end

  test "the source opens on the plain words; the switch shows the law's words; the guide lists the spans" do
    open_gallery
    go(3)
    assert_selector "#scheda-3 .source-plain", visible: :visible, count: 2
    assert_selector "#scheda-3 .source-plain", text: "Il venditore porta la merce", visible: :visible
    assert_no_selector "#scheda-3 .source-original", visible: :visible
    assert_selector "#scheda-3 .source-switch[aria-pressed=true]", text: "In parole semplici"
    click_button "Testo della legge"
    assert_selector "#scheda-3 .source-original", visible: :visible, count: 2
    assert_no_selector "#scheda-3 .source-plain", visible: :visible
    assert_selector "#scheda-3 .source-mark.role-creditor", text: "Il venditore"
    assert_selector "#scheda-3 .source-no", text: "2"
    shot("3-legge-original")
    find("#scheda-3 .source-guide summary").click
    assert_selector "#scheda-3 .source-guide-list li", text: "a spese del compratore"
  end

  test "a plain reveal is a flip card: the answer is behind it until the card is touched" do
    open_gallery
    go(5)
    assert_selector "#scheda-5 .reveal-toggle[aria-expanded=false]"
    assert_no_selector "#scheda-5 .reveal-back", visible: :visible
    find("#scheda-5 .reveal-toggle").click
    assert_selector "#scheda-5 .reveal-toggle[aria-expanded=true]"
    assert_selector "#scheda-5 .reveal-back", text: "Sono spese del cliente", visible: :visible
  end

  test "the crossroads: pick a road, see what comes of it, then turn to what really happened; the real road is marked in words" do
    open_gallery
    go(4)
    assert_selector "#scheda-4 .reveal-option", count: 3
    assert page.evaluate_script("document.querySelector('#scheda-4 .reveal-flip').disabled")
    assert_selector "#scheda-4 .reveal-need", text: "Prima scegli una strada."
    assert_no_selector "#scheda-4 .reveal-back", visible: :visible
    click_button "Non consegno più nulla, senza avvisare"
    assert_selector "#scheda-4 .reveal-then", text: "Rischi di non rispettare il contratto."
    assert_selector "#scheda-4 .reveal-option[aria-pressed=true]", count: 1
    click_button "Gli scrivo e chiedo di pagare"
    assert_selector "#scheda-4 .reveal-then", text: "Il cliente sa che aspetti."
    assert_no_selector "#scheda-4 .reveal-then", text: "Rischi di non rispettare"
    shot("4-bivio-chosen")
    find("#scheda-4 .reveal-flip").click
    assert_selector "#scheda-4 .reveal-back", text: "Di solito il venditore manda prima un sollecito scritto.", visible: :visible
    assert_selector "#scheda-4 .reveal-back", text: "Le altre strade sono ipotesi", visible: :visible
    assert_selector "#scheda-4 .reveal-option[data-real=true] .reveal-real-mark", text: "È andata così", visible: :visible
    shot("4-bivio-real")
  end

  test "a mistake still turns: its flip is the shared one" do
    open_gallery
    go(8)
    assert_selector "#scheda-8 .mistake.flip", count: 3
    assert_no_selector "#scheda-8 .mistake-back", visible: :visible
    first("#scheda-8 .mistake-toggle").click
    assert_selector "#scheda-8 .mistake[data-open=true] .mistake-back", visible: :visible, count: 1
    assert_selector "#scheda-8 .mistake-toggle[aria-expanded=true]", count: 1
  end

  test "the oral: the outline moves with su and giù, a wrong order gets a hint, the right one shows the model answer and the private line" do
    open_gallery
    go(7)
    assert_selector "#scheda-7 .oral-tile", count: 4
    assert_no_selector "#scheda-7 .oral-model-text"
    assert_no_selector "#scheda-7 .oral-model-title"
    # the key in the page's own ids: o1..o4 are shown as e1..e4 in a shuffled order
    page.execute_script("window.__oralKey = null")
    key = page.evaluate_script(<<~JS)
      [...document.querySelectorAll('#scheda-7 .oral-tile')].map((li) => li.dataset.id)
    JS
    assert_equal key.sort, %w[e1 e2 e3 e4]
    texts = page.evaluate_script("[...document.querySelectorAll('#scheda-7 .oral-tile-text')].map((n) => n.textContent)")
    wanted = [ "Parto dal lordo della merce", "Tolgo gli sconti e ho il netto", "Aggiungo le spese del venditore: ecco l'imponibile", "Calcolo l'IVA e aggiungo le spese anticipate" ]
    ids = wanted.map { |t| key[texts.index(t)] }
    page.execute_script("window.__oralKey = #{ids.to_json}")
    click_button "Controlla"
    assert_selector "#scheda-7 .verdict-wrong"
    assert_selector "#scheda-7 .oral-model-text", count: 0
    # put them right with the buttons: each tile moves up until it is where it belongs
    wanted.each_with_index do |text, target|
      loop do
        now = page.evaluate_script("[...document.querySelectorAll('#scheda-7 .oral-tile-text')].map((n) => n.textContent)")
        at = now.index(text)
        break if at <= target

        find("#scheda-7 .oral-tile:nth-child(#{at + 1}) [data-dir=up]").click
      end
    end
    assert_equal wanted, page.evaluate_script("[...document.querySelectorAll('#scheda-7 .oral-tile-text')].map((n) => n.textContent)")
    click_button "Controlla"
    assert_selector "#scheda-7 .verdict-right"
    assert_selector "#scheda-7 .oral-model-text", text: "Parto dal lordo"
    assert_selector "#scheda-7 .oral-private", text: "Nessuno ti ascolta e non registriamo niente."
    assert_selector "#scheda-7 .oral-self input[type=checkbox]", count: 4
    shot("7-orale-model")
  end

  test "print shows both texts of the source, every road of the crossroads and the backs of the flip cards" do
    open_gallery
    page.execute_script("window.lessonApi.renderAll()")
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "print")
    Timeout.timeout(10) { sleep 0.1 until page.evaluate_script("matchMedia('print').matches") }
    assert_selector "#scheda-3 .source-plain", visible: :visible, count: 2
    assert_selector "#scheda-3 .source-original", visible: :visible, count: 2
    assert_selector "#scheda-4 .reveal-back", visible: :visible
    assert_selector "#scheda-5 .reveal-back", visible: :visible
    assert_no_selector "#scheda-3 .source-switchbox", visible: :visible
  end

  test "safe mode shows the source with both texts, the crossroads with every road, the flip cards open and the oral as a plain outline" do
    ENV["BANCO_LESSON2_ENABLED"] = "0"
    open_gallery
    page.execute_script("window.lessonApi.renderAll()")
    assert_selector "#scheda-3 .source-plain", visible: :visible, count: 2
    assert_selector "#scheda-3 .source-original", visible: :visible, count: 2
    assert_selector "#scheda-4 .reveal-then-print", visible: :visible, count: 3
    assert_selector "#scheda-5 .reveal-back", visible: :visible
    assert_selector "#scheda-7 .oral-outline-plain li", count: 4, visible: :visible
    assert_no_selector "#scheda-7 .oral-form"
    assert_no_selector "#scheda-7 .oral-model-text"
  ensure
    ENV.delete("BANCO_LESSON2_ENABLED")
  end

  test "the reveal and the oral keep the keyboard: every control is a button reached with Tab and pressed with Enter" do
    open_gallery
    go(5)
    page.execute_script("document.querySelector('#scheda-5 .reveal-toggle').focus()")
    page.driver.browser.keyboard.type(:Enter)
    assert_selector "#scheda-5 .reveal-toggle[aria-expanded=true]"
    go(3)
    page.execute_script("document.querySelector('#scheda-3 .source-switch:last-of-type').focus()")
    page.driver.browser.keyboard.type(:Enter)
    assert_selector "#scheda-3 .source-original", visible: :visible, count: 2
  end
end
