require "application_system_test_case"
require_relative "../support/lesson_links_world"
require_relative "../support/student_session"

# The lesson page walked in Chrome against the real endpoints, no stand-in (the trial student S and the teacher's preview, which runs the
# same page on /teacher/preview): a check answered wrong then right (what the page says, the tries the server counts), a blank of a worked
# example, the solution of a «Prova tu» exercise (steps, and a plain text one), the links to other topics inside the text (one opens, one
# reads «non ancora disponibile»), and card navigation with the resume offered after a reload. Any JavaScript error, console error, refused
# resource or CSP violation fails the test. Whatever the preview does reaches the preview student only.
class LessonFlowTest < ApplicationSystemTestCase
  include LessonLinksWorld
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

  def open_lesson(root, fragment = "")
    visit "about:blank"
    visit "#{root}/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#{fragment}"
    wait_for_lesson_ready(wait: 30)
    assert_selector ".l2-cover, .l2-card", wait: 15
  end

  def acting(kind) = kind == :preview ? Student.where(kind: "preview").order(:id).last : Student.find_by!(key: "prova-1")

  # The ledger rows of one check of this student, in the order they were written: [[verdict, try], ...].
  def answers_of(student, card, block, **key)
    LessonEvent.where(student: student, kind: "check_answered", card: card, block: block).order(:id)
               .select { |r| r.payload.slice("step", "ex", "part").symbolize_keys == key }.map { |r| [ r.payload["verdict"], r.payload["try"] ] }
  end

  # The whole walk, as S (root "") or as the teacher's preview (root "/teacher/preview").
  def walk(root, kind)
    open_lesson(root, "#scheda-1")
    student = acting(kind)
    assert_selector "article#scheda-1"

    # the links in the text: the open one goes to the topic page of the same side of the site, the closed one is not an address
    assert_selector "article#scheda-1 a.lesson-link[href='#{root}/topics/#{TOPIC}']", text: OPEN_LINK_TEXT
    assert_selector "article#scheda-1 .unavailable", text: "#{CLOSED_LINK_TEXT} (non ancora disponibile)"
    assert_no_selector "article#scheda-1 a[href*='#{CLOSED_KEY}']"

    # a check: wrong (the message of that error), then right (the explanation); the server counts the tries
    card, block, check = find_block { |_, b| b["type"] == "check" && b["component"] == "choice" }
    shown = ->(stored) { shown_id(student, card, block, stored) }
    within("article#scheda-#{card} .block-check") do
      find("input[type=radio][value='#{shown.call('a')}']").click
      click_button "Controlla"
      assert_selector ".verdict-wrong", text: "Non ancora."
      assert_selector ".feedback", text: "il primo membro vale 13"
      assert_no_selector ".verdict-explain"
      find("input[type=radio][value='#{shown.call(check['answer'])}']").click
      click_button "Controlla"
      assert_selector ".verdict-right", text: "Sì."
      assert_selector ".verdict-explain", text: "I piatti sono uguali"
      assert_selector "form.check.is-done"
    end
    assert_equal [ %w[wrong 1], %w[right 2] ].map { |v, t| [ v, t.to_i ] }, answers_of(student, card, block)

    # a blank of a worked example: wrong, then right; the rest of the example and its result come from the server
    ex_card, ex_block, example = find_block { |_, b| b["type"] == "example" }
    blank = example["steps"].find { |s| s["blank"] }["blank"]
    step = example["steps"].index { |s| s["blank"] } + 1
    page.execute_script("window.lessonApi.goTo(#{ex_card}, { focus: false })")
    within("article#scheda-#{ex_card} .example") do
      click_button "Mostra tutto"
      assert_selector ".example-note", text: "Prima rispondi"
      find(".step-blank input.answer-input").set("7")
      click_button "Controlla"
      assert_selector ".verdict-wrong", text: "Non ancora."
      find(".step-blank input.answer-input").set(blank["answer"])
      click_button "Controlla"
      assert_selector ".verdict-right"
      assert_selector ".example-result", text: example["result_it"][0, 12]
    end
    assert_equal [ [ "wrong", 1 ], [ "right", 2 ] ], answers_of(student, ex_card, ex_block, step: step)

    # «Prova tu»: an exercise's check wrong then right, then its solution as steps; a last exercise whose error has its message, and its
    # solution as a text
    try_card, try_block, try = find_block { |_, b| b["type"] == "try" }
    page.execute_script("window.lessonApi.goTo(#{try_card}, { focus: false })")
    within("article#scheda-#{try_card} li.exercise.is-current") do
      find("input.answer-input").set("5")
      click_button "Controlla"
      assert_selector ".verdict-wrong", text: "Non ancora."
      find("input.answer-input").set("3")
      click_button "Controlla"
      assert_selector ".verdict-right", text: "Sì."
      click_button "Mostra la soluzione"
      assert_selector ".solution .solution-steps li", count: 3
      assert_selector ".solution", text: "Sposta"
    end
    assert_equal [ [ "wrong", 1 ], [ "right", 2 ] ], answers_of(student, try_card, try_block, ex: 1)
    last = try["exercises"].last["n"]
    find("article#scheda-#{try_card} .try-dot", text: last.to_s, exact_text: true).click
    within("article#scheda-#{try_card} li.exercise.is-current") do
      find("input.answer-input").set("4")
      click_button "Controlla"
      assert_selector ".verdict-wrong", text: "Non ancora."
      assert_selector ".feedback", text: "invece di dividere per 3"
      find("input.answer-input").set("7/3")
      click_button "Controlla"
      assert_selector ".verdict-right", text: "Sì."
      click_button "Mostra la soluzione"
      assert_selector ".solution .solution-text", text: "Dividi per 3 i due membri"
    end
    assert_equal [ [ "wrong", 1 ], [ "right", 2 ] ], answers_of(student, try_card, try_block, ex: last)
    assert_equal [ 1, last ], PracticeEvent.where(student: student, kind: "lesson_solution_shown").order(:id).map { |e| JSON.parse(e.payload_json)["n"] }

    # card navigation: Avanti and Indietro, then a reload with no card in the address offers to resume where the last card seen was
    page.execute_script("window.lessonApi.goTo(2, { focus: false })")
    assert_selector ".l2-counter .cn-l", text: /Scheda 2 di/
    click_button class: "l2-next"
    assert_selector ".l2-counter .cn-l", text: /Scheda 3 di/
    click_button class: "l2-prev"
    assert_selector ".l2-counter .cn-l", text: /Scheda 2 di/
    Timeout.timeout(20) { sleep 0.2 until LessonEvent.where(student: student, kind: "card_seen", card: 2).exists? }
    open_lesson(root)
    assert_selector ".l2-start", text: "Riprendi dalla scheda 2"
    find(".l2-start").click
    assert_selector ".l2-counter .cn-l", text: /Scheda 2 di/

    # the link in the text opens the topic page, on the same side of the site
    page.execute_script("window.lessonApi.goTo(1, { focus: false })")
    find("article#scheda-1 a.lesson-link", text: OPEN_LINK_TEXT).click
    assert_selector "h1", text: TOPIC_TITLE, wait: 15
    assert_equal "#{root}/topics/#{TOPIC}", URI(page.current_url).path
    assert_equal 200, page.status_code
    assert_clean "the lesson walk"
    student
  end

  test "S walks a lesson: a check wrong then right, an example's blank, a «Prova tu» solution, the links in the text, the cards and the resume" do
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    walk("", :student)
  end

  test "the teacher walks the same lesson in the preview, on the preview addresses, and only the preview student is written" do
    sign_in_as :teacher
    student = walk("/teacher/preview", :preview)
    assert_equal "preview", student.kind
    assert_empty LessonEvent.where.not(student_id: student.id)
    assert_empty PracticeEvent.where(kind: "lesson_solution_shown").where.not(student_id: student.id)
    assert_equal 0, StudentQuestion.count
  end
end
