require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# The student's journey end to end, in Chrome: Oggi -> Materie -> a subject -> a topic -> the lesson (cards and a figure are
# drawn) -> a practice exercise answered. Walked as the official student (released course, approved topic) and as a trial
# student (D-217), who also meets a draft topic of a course that is not released. Any JavaScript error, console error,
# unhandled rejection, refused resource or CSP violation on the way fails the test (the report of the production bug of
# 2026-10-16, "non vedo le lezioni").
class StudentJourneyTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  HEADERS = {
    official: { "Remote-User" => "kid-a", "Remote-Groups" => "banco-student" },
    trial: { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }
  }.freeze

  # Installed in every document the browser opens from now on; collects what a student's console would show red.
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
    ENV["BANCO_STUDENT_USERS"] = "kid-a=student,trial-x=prova-1"
    @problems = []
    @watch_id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: WATCH)["identifier"]
    # resources the browser could not load (a 404 or a 403 of an asset) are in the log, not in the console API
    page.driver.browser.page.on("Log.entryAdded") do |params|
      entry = params["entry"] || {}
      @problems << "log #{entry['level']}: #{entry['text']} #{entry['url']}" if %w[error warning].include?(entry["level"]) && entry["source"] != "deprecation" && entry["text"].to_s !~ /favicon/
    end
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

  def sign_in(who)
    sign_in_as :student
    page.driver.headers = HEADERS.fetch(who)
  end

  def collect_problems
    @problems.concat(Array(page.evaluate_script("window.__problems || []")))
  rescue Ferrum::Error
    nil
  end

  def assert_clean(where)
    collect_problems
    assert_empty @problems, "#{where}: the browser reported problems"
  end

  def walk_to_topic(who)
    visit "/today"
    assert_selector "#trial-notice" if who == :trial
    find("#student-menu-open").click # the links are in the menu dialog (D-307)
    click_link "Materie"
    assert_selector "h1", text: "Materie"
    click_link "Math"
    assert_selector "li", text: TOPIC_TITLE
    click_link TOPIC_TITLE
    assert_selector "h1", text: TOPIC_TITLE
    assert_clean "Oggi, Materie, the subject and the topic"
  end

  def read_lesson(draft:)
    click_link "Leggi la lezione"
    wait_for_lesson_ready(wait: 30)
    assert_selector "#draft-notice", visible: :all, count: draft ? 1 : 0
    assert_selector ".l2-cover h1", text: "Equazioni di primo grado intere"
    assert_selector ".goals li", count: 3
    find(".l2-start").click
    assert_selector "article.l2-card h2", text: "I pezzi di un'equazione"
    # a figure is drawn, not just the text of the card
    assert_selector "article.l2-card figure.dg .dg-stage svg", minimum: 1, wait: 20
    assert_no_selector "figure.dg[data-error]", visible: :all
    assert_selector ".l2-counter", text: "Scheda 1 di 11"
    click_button(class: "l2-next")
    assert_selector ".l2-counter", text: "Scheda 2 di 11"
    assert_clean "the lesson"
  end

  def practise
    visit "/topics/#{TOPIC}"
    first("a.button", text: "Esercitati").click
    assert_selector ".item-body input[inputmode=decimal]", wait: 30
    serve = PracticeServe.order(:id).last
    find(".item-body input[inputmode=decimal]").set(JSON.parse(serve.item_instance.answer_json).to_s)
    click_button "Controlla"
    assert_selector "#feedback", text: "Corretto."
    assert_clean "the practice page"
  end

  def walk(who, draft:)
    sign_in who
    walk_to_topic(who)
    read_lesson(draft: draft)
    practise
  end

  test "the official student walks the released course: Oggi, Materie, the subject, the topic, the lesson, an exercise" do
    build_lesson2_world(name: "equations", approve: true, release: true)
    walk(:official, draft: false)
  end

  test "a trial student walks the same course" do
    build_lesson2_world(name: "equations", approve: true, release: true)
    walk(:trial, draft: false)
  end

  test "a trial student who came back: saved preferences (dark, large, one column), cards already seen, a resume point" do
    build_lesson2_world(name: "equations", approve: true, release: true)
    Diagnosis::Preferences.record(@trial, theme: "dark", size: "larger", lesson_view: "scroll", reduce_motion: true)
    [ 1, 2, 3 ].each do |card|
      LessonEvent.create!(student: @trial, topic_revision: @topic_revision, lesson_revision: @lesson_revision, kind: "card_seen", card: card,
                          payload_json: "{}", client_event_id: "seen-#{card}", at: Time.current, created_at: Time.current)
    end
    sign_in :trial
    visit "/topics/#{TOPIC}/lesson"
    wait_for_lesson_ready(wait: 30)
    assert_selector "#lesson-root[data-view='scroll']"
    # one column: every card has its place (the ones far down are drawn when they come near)
    assert_selector ".l2-cover h1", text: "Equazioni di primo grado intere"
    assert_selector ".l2-placeholder, article.l2-card", minimum: 11, visible: :all
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    assert_selector "article.l2-card", minimum: 3, wait: 20
    assert_clean "the lesson of a returning trial student"
  end

  test "a trial student reads the draft lesson of a course that is not released, the official student sees nothing" do
    build_lesson2_world(name: "equations", approve: false, release: false)
    walk(:trial, draft: true)
    sign_in :official
    visit "/topics/#{TOPIC}/lesson"
    assert_equal 404, page.status_code
    visit "/subjects/math"
    assert_equal 404, page.status_code
  end
end
