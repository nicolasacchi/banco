require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# Every way of answering in a lesson, in Chrome against the real endpoints, no stand-in (the trial student S, and the teacher in /teacher/preview):
# a word written, tiles, an ordering, spans touched, a matching, and the two exercises of «Prova tu» (a choice with a text solution, tiles with a
# solution in steps). Each is answered wrong, with the hint of that error, then right; the server counts the tries. The check kinds of the
# lesson page are tested alone, over a stand-in endpoint, in lesson_checks_system_test.rb; the walk of the whole page is lesson_flow_test.rb.
class LessonCheckKindsTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze

  WATCH = <<~JS.freeze
    (() => {
      window.__problems = [];
      const note = (kind, text) => window.__problems.push(kind + ": " + text);
      const consoleError = console.error.bind(console);
      console.error = (...args) => { note("console.error", args.map(String).join(" ")); consoleError(...args); };
      window.addEventListener("error", (e) => note("error", (e.message || "") + " " + (e.filename || "")));
      window.addEventListener("unhandledrejection", (e) => note("unhandledrejection", String(e.reason && e.reason.stack || e.reason)));
      document.addEventListener("securitypolicyviolation", (e) => note("csp", e.violatedDirective + " " + e.blockedURI));
    })();
  JS

  def lesson_body
    @check_kinds ||= Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/check_kinds.md").read, Validation::Findings.new).body.merge("key" => TOPIC)
  end

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    build_student_world(approve: true, release: true)
    @problems = []
    @watch_id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: WATCH)["identifier"]
    page.driver.browser.page.on("Log.entryAdded") do |params|
      entry = params["entry"] || {}
      @problems << "log #{entry['level']}: #{entry['text']} #{entry['url']}" if %w[error warning].include?(entry["level"]) && entry["source"] != "deprecation" && entry["text"].to_s !~ /favicon/
    end
    page.driver.resize(1280, 900)
  end

  teardown do
    begin
      page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: @watch_id) if @watch_id
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def assert_clean(where)
    @problems.concat(Array(page.evaluate_script("window.__problems || []")))
    assert_empty @problems, "#{where}: the browser reported problems"
  rescue Ferrum::Error
    nil
  end

  def card_of(component) = stored_body["cards"].find { |c| c["blocks"].any? { |b| b["component"] == component } }["n"]

  def go(card)
    page.execute_script("window.lessonApi.goTo(#{card}, { focus: false })")
    assert_selector "article#scheda-#{card}", wait: 10
  end

  # The ledger rows of one check of this student, in the order they were written: [[verdict, try], ...].
  def answers_of(student, card, **key)
    LessonEvent.where(student: student, kind: "check_answered", card: card).order(:id)
               .select { |r| r.payload.slice("step", "ex", "part").symbolize_keys == key }.map { |r| [ r.payload["verdict"], r.payload["try"] ] }
  end

  WRONG_THEN_RIGHT = [ [ "wrong", 1 ], [ "right", 2 ] ].freeze

  def check!(scope)
    within(scope) { click_button "Controlla" }
  end

  def tap_tiles(card, words)
    words.each { |w| find("#scheda-#{card} .tiles-bank .tile-bank:not(.is-used)", text: w, exact_text: true).click }
  end

  # Puts the items of an ordering in the given order with the Su buttons, by their text.
  def arrange(card, texts)
    texts.each_with_index do |text, at|
      loop do
        now = all("#scheda-#{card} .order-item .order-text").map(&:text)
        break if now.index(text) <= at

        all("#scheda-#{card} .order-item")[now.index(text)].find(".order-up").click
        assert_no_selector "#scheda-#{card} .order-item:nth-child(#{now.index(text) + 1}) .order-text", text: text, exact_text: true, wait: 3
      end
    end
  end

  # The chip of a matching row is a radio laid over its label: the radio takes the click.
  def pick(row, chip) = find(".match-row", text: row).find(".chip", text: chip, exact_text: true).find("input", visible: :all).click

  def walk(root, kind)
    visit "about:blank"
    visit "#{root}/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 30)
    student = kind == :preview ? Student.where(kind: "preview").order(:id).last : Student.find_by!(key: "prova-1")

    # a word written: the hint of the typical error, then the right word and its explanation
    card = card_of("normalized_text")
    go card
    within("#scheda-#{card}") do
      find("input[type=text]").set("nome")
      click_button "Controlla"
      assert_selector ".verdict-wrong", text: "Non ancora."
      assert_selector ".feedback", text: "Il nome dice chi o che cosa"
      find("input[type=text]").set("verbo")
      click_button "Controlla"
      assert_selector ".verdict-right", text: "Sì."
      assert_selector ".verdict-explain", text: "Il verbo dice che cosa succede"
    end
    assert_equal WRONG_THEN_RIGHT, answers_of(student, card)

    # tiles: the words in the wrong order, then in the right one
    card = card_of("tiles")
    go card
    tap_tiles(card, %w[legge Marco un libro])
    check!("#scheda-#{card}")
    assert_selector "#scheda-#{card} .verdict-wrong"
    assert_selector "#scheda-#{card} .feedback", text: "Il soggetto va prima del verbo"
    click_button "Svuota"
    tap_tiles(card, %w[Marco legge un libro])
    check!("#scheda-#{card}")
    assert_selector "#scheda-#{card} .verdict-right", text: "Sì."
    assert_selector "#scheda-#{card} .tile[disabled]", minimum: 1
    assert_equal WRONG_THEN_RIGHT, answers_of(student, card)

    # an ordering: the list as it is shown is not the key; then the key
    card = card_of("ordering")
    go card
    assert_selector "#scheda-#{card} .order-item", count: 3
    check!("#scheda-#{card}")
    assert_selector "#scheda-#{card} .verdict-wrong", text: "Non ancora."
    arrange(card, [ "Rita esce di casa.", "Rita arriva al cinema.", "Rita si siede." ])
    check!("#scheda-#{card}")
    assert_selector "#scheda-#{card} .verdict-right", text: "Sì."
    assert_equal WRONG_THEN_RIGHT, answers_of(student, card)

    # spans touched
    card = card_of("span_select")
    go card
    within("#scheda-#{card}") do
      find("button.span-chip", text: "La bambina", exact_text: true).click
      click_button "Controlla"
      assert_selector ".verdict-wrong"
      assert_selector ".feedback", text: "La bambina è chi fa l'azione"
      find("button.span-chip", text: "La bambina", exact_text: true).click
      find("button.span-chip", text: "canta", exact_text: true).click
      click_button "Controlla"
      assert_selector ".verdict-right", text: "Sì."
    end
    assert_equal WRONG_THEN_RIGHT, answers_of(student, card)

    # a matching: two rows swapped, then every row right
    card = card_of("matching")
    go card
    within("#scheda-#{card}") do
      { "Marco" => "predicato", "legge" => "soggetto", "un libro" => "oggetto" }.each { |row, chip| pick(row, chip) }
      click_button "Controlla"
      assert_selector ".verdict-wrong"
      assert_selector ".feedback", text: "Marco fa l'azione: è il soggetto."
      { "Marco" => "soggetto", "legge" => "predicato" }.each { |row, chip| pick(row, chip) }
      click_button "Controlla"
      assert_selector ".verdict-right", text: "Sì."
    end
    assert_equal WRONG_THEN_RIGHT, answers_of(student, card)

    # «Prova tu»: a choice, then its solution as a text; tiles, then their solution in steps
    card = stored_body["cards"].find { |c| c["role"] == "try" }["n"]
    go card
    within("#scheda-#{card} li.exercise.is-current") do
      find("label", text: "Arriva", exact_text: true).click
      click_button "Controlla"
      assert_selector ".verdict-wrong"
      assert_selector ".feedback", text: "è il predicato"
      find("label", text: "il treno", exact_text: true).click
      click_button "Controlla"
      assert_selector ".verdict-right", text: "Sì."
      click_button "Mostra la soluzione"
      assert_selector ".solution .solution-text", text: "Chi arriva? Il treno."
    end
    assert_equal WRONG_THEN_RIGHT, answers_of(student, card, ex: 1)
    find("#scheda-#{card} .try-dot", text: "2", exact_text: true).click
    within("#scheda-#{card} li.exercise.is-current") do
      %w[legge Paola].each { |w| find(".tiles-bank .tile-bank:not(.is-used)", text: w, exact_text: true).click }
      click_button "Controlla"
      assert_selector ".verdict-wrong", text: "Non ancora."
      click_button "Svuota"
      %w[Paola legge].each { |w| find(".tiles-bank .tile-bank:not(.is-used)", text: w, exact_text: true).click }
      find(".tiles-bank .tile-bank:not(.is-used)", text: "un fumetto", exact_text: true).click
      click_button "Controlla"
      assert_selector ".verdict-right", text: "Sì."
      click_button "Mostra la soluzione"
      assert_selector ".solution .solution-steps li", count: 2
      assert_selector ".solution", text: "Chi legge? Paola."
    end
    assert_equal WRONG_THEN_RIGHT, answers_of(student, card, ex: 2)
    assert_clean "the check kinds"
    student
  end

  test "S answers every kind of question of a lesson, wrong then right, and reads the solutions of «Prova tu»" do
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    walk("", :student)
  end

  test "the teacher answers them in the preview, and only the preview student is written" do
    sign_in_as :teacher
    student = walk("/teacher/preview", :preview)
    assert_equal "preview", student.kind
    assert_empty LessonEvent.where.not(student_id: student.id)
    assert_empty PracticeEvent.where(kind: "lesson_solution_shown").where.not(student_id: student.id)
  end
end
