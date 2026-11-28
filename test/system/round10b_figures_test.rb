require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# Round 10b (D-409), in Chrome at 390 px, on the student's lesson page: a bilingual english lesson whose cards draw (1) a mirror whose links cross, which the
# phone draws as two whole sentences in their own order with the two languages named; (2) a decode word_parts whose Italian gloss follows the card's
# «Traduzione» button; (3) a bar_model written with a decimal point («18.8»), which is printed with a point.
class Round10bFiguresSystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  LESSON = <<~MD.freeze
    ---
    schema: banco.lesson/2
    bilingual: true
    key: lezione.english.round10b-fixture
    kind: lezione
    subject: english
    title_en: "Word order and numbers"
    title_it: "L'ordine delle parole e i numeri"
    goals_en:
      - "**See** the order of the words"
    goals_it:
      - "**Vedere** l'ordine delle parole"
    skills: [english.modals-can]
    refs:
      - {source: gallery-2026, line: 1, fragment: "modals", role: taught_in}
    scope: studied
    minutes: 30
    calculator: false
    book_it: "Cerca «avverbi» sul libro."
    why_en: "The order of the words says what you mean."
    why_it: "L'ordine delle parole dice che cosa vuoi dire."
    ---

    ## The adverb {idea short="Order" short_it="Ordine" it="L'ordine" icon=equal id=order}

    ::: diagram mirror
    alt_en: "The Italian sentence Tom gioca spesso a tennis over the English one, Tom often plays tennis: often comes before the verb."
    alt_it: "La frase italiana Tom gioca spesso a tennis sopra quella inglese, Tom often plays tennis: often viene prima del verbo."
    rows:
      - pieces_it: ["Tom", "gioca", "spesso", "a tennis"]
        pieces_en: ["Tom", "often", "plays", "tennis"]
        links: [[0, 0, same], [1, 2, meaning], [2, 1, meaning], [3, 3, meaning]]
    :::

    ## Pieces of a word {idea short="Pieces" short_it="Pezzi" it="I pezzi di una parola" icon=hand-helping id=pieces}

    ::: diagram word_parts
    alt_en: "The word played split into two pieces: play and ed."
    alt_it: "La parola played divisa in due pezzi: play e ed."
    view: decode
    words:
      - form_en: 'play|ed'
        parts_it: ["giocare", "passato"]
        meaning_it: "giocò, ha giocato"
    :::

    ## Young people at work {idea short="Numbers" short_it="Numeri" it="I numeri" icon=equal id=numbers}

    ::: diagram bar_model
    alt_en: "One bar of a hundred percent: young people with a job are 18.8, the rest 81.2."
    alt_it: "Una barra del cento per cento: i giovani con un lavoro sono il 18,8, il resto l'81,2."
    view: parts
    total: {value: "100", label_en: "All", label_it: "Tutti"}
    bars:
      - label_en: "Young people"
        label_it: "Giovani"
        parts:
          - {value: 18.8, label_en: "with a job", label_it: "con un lavoro"}
          - {value: 81.2, label_en: "the rest", label_it: "il resto"}
    :::
  MD

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
  end

  teardown do
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def lesson_body
    findings = Validation::Findings.new
    body = Lessons::Parser2.call(LESSON, findings).body
    raise "fixture has findings: #{findings.errors.map(&:to_h)}" if findings.errors.any?

    body.merge("key" => TOPIC)
  end

  def open_lesson
    build_student_world(approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(390, 844)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 20)
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "round10b-#{name}.png"), full: true)

  # the texts of the labels that match +selector+, from the top of the figure to the bottom
  def texts_by_height(selector)
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(#{selector.to_json})).map((n) => [n.getBoundingClientRect().top, n.textContent.trim()]).sort((a, b) => a[0] - b[0]).map((x) => x[1])
    JS
  end

  def no_overflow!(where)
    over = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    assert_operator over, :<=, 1, "#{where}: the page is #{over} px wider than the window"
  end

  test "390 px: a mirror whose links cross draws each sentence whole in its own order, numbered by pair, with the two languages named" do
    open_lesson
    go(1)
    assert_selector "#scheda-1 .dg-mirror .dg-mr-text", minimum: 8
    assert_equal %w[Tom often plays tennis], texts_by_height("#scheda-1 .dg-mirror .dg-mr-text[lang=en]")
    assert_equal [ "Tom", "gioca", "spesso", "a tennis" ], texts_by_height("#scheda-1 .dg-mirror .dg-mr-text[lang=it]")
    assert_equal %w[Italian English], texts_by_height("#scheda-1 .dg-mirror .dg-mr-side")
    # «plays» is the pair 2 as «gioca» is: the same number on the two pieces
    assert_equal %w[1 2 3 4 1 3 2 4], texts_by_height("#scheda-1 .dg-mirror .dg-numlabel")
    assert_selector "#scheda-1 .dg-mirror .dg-mr-link", minimum: 8
    no_overflow!("crossed mirror")
    shot("mirror-crossed-390")
  end

  test "390 px: the Italian gloss of a word_parts follows the card's Traduzione button" do
    open_lesson
    go(2)
    assert_selector "#scheda-2 .dg-word_parts .dg-gloss", visible: :all, minimum: 3
    display = "Array.from(document.querySelectorAll('#scheda-2 .dg-word_parts .dg-gloss')).map((n) => getComputedStyle(n).display)"
    assert_equal [ "none" ], page.evaluate_script(display).uniq, "closed: the Italian meanings are not drawn"
    assert_selector "#scheda-2 .dg-word_parts .dg-label", text: "play", visible: :all
    shot("word-parts-closed-390")
    find("#scheda-2 .tr-toggle", match: :first).click
    assert_equal [ "block" ], page.evaluate_script(display).uniq, "open: they are"
    assert_selector "#scheda-2 .dg-gloss", text: "giocare"
    shot("word-parts-open-390")
    find("#scheda-2 .tr-toggle", match: :first).click
    assert_equal [ "none" ], page.evaluate_script(display).uniq, "closed again"
    no_overflow!("word_parts")
  end

  test "390 px: a bar_model written with a decimal point in an English lesson prints a point, in the bar and under it" do
    open_lesson
    go(3)
    assert_selector "#scheda-3 .dg-bar_model .dg-label", minimum: 3
    texts = page.evaluate_script("Array.from(document.querySelectorAll('#scheda-3 .dg-bar_model .dg-label')).map((n) => n.textContent.trim())").join(" | ")
    assert_match(/18\.8/, texts)
    assert_match(/81\.2/, texts)
    assert_no_match(/18,8|81,2/, texts)
    no_overflow!("bar_model")
    shot("bar-point-390")
  end
end
