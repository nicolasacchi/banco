require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# The teacher walks the student's site in Chrome, from the teacher's own login (D-309): Oggi -> Materie -> a subject -> a topic ->
# the lesson (the cards and a figure are drawn, the events go to the preview student) -> a practice exercise graded, in the
# official view and in the drafts view. Any JavaScript error, console error, refused resource or CSP violation fails the test.
# With BANCO_SHOT_DIR set, it also takes screenshots of the banner and a lesson at 390 and 1280 px.
class TeacherPreviewTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  ROOT = "/teacher/preview".freeze

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
    ENV["BANCO_STUDENT_USERS"] = ""
    @problems = []
    @watch_id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: WATCH)["identifier"]
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

  def assert_clean(where)
    @problems.concat(Array(page.evaluate_script("window.__problems || []")))
    assert_empty @problems, "#{where}: the browser reported problems"
  rescue Ferrum::Error
    nil
  end

  def preview_student = Student.where(kind: "preview").order(:id).last

  def shot(name)
    dir = ENV["BANCO_SHOT_DIR"].presence or return
    FileUtils.mkdir_p(dir)
    [ [ 1280, 900, "1280" ], [ 390, 844, "390" ] ].each do |w, h, label|
      page.driver.resize(w, h)
      sleep 0.6
      page.driver.save_screenshot(File.join(dir, "#{name}-#{label}.png"), full: true)
    end
    page.driver.resize(1280, 900)
  end

  def shot_at(name, width)
    dir = ENV["BANCO_SHOT_DIR"].presence or return
    FileUtils.mkdir_p(dir)
    page.driver.resize(width, width == 390 ? 844 : 900)
    sleep 0.4
    page.driver.save_screenshot(File.join(dir, "#{name}-#{width}.png"), full: true)
  end

  def banner_height = page.evaluate_script("document.getElementById('preview-banner').getBoundingClientRect().height")

  # One row: the banner is no taller than its exit button and the padding around it (two rows would be twice the button).
  def one_row? = banner_height <= page.evaluate_script("document.getElementById('preview-exit').getBoundingClientRect().height") + 32

  def walk(draft:)
    visit ROOT
    assert_selector "#preview-banner", text: "Stai provando come studente"
    assert_selector "#preview-banner", text: draft ? "Vista: Con le bozze" : "Vista: Come lo vede S"
    shot("banner-#{draft ? 'drafts' : 'official'}") if draft == false
    find("#student-menu-open").click
    click_link "Materie"
    assert_selector "h1", text: "Materie"
    assert_selector "#preview-banner"
    click_link "Math"
    click_link TOPIC_TITLE
    assert_selector "h1", text: TOPIC_TITLE
    assert_selector "#draft-notice", count: draft ? 1 : 0
    assert_no_selector "[data-controller=question]"
    click_link "Leggi la lezione"
    wait_for_lesson_ready(wait: 30)
    assert_selector "#preview-banner"
    assert_selector ".l2-cover h1", text: "Equazioni di primo grado intere"
    assert_no_selector ".l2-commentbtn"
    find(".l2-start").click
    assert_selector "article.l2-card h2", text: "I pezzi di un'equazione"
    assert_selector "article.l2-card figure.dg .dg-stage svg", minimum: 1, wait: 20
    assert_no_selector "figure.dg[data-error]", visible: :all
    shot("lesson") if draft == false
    click_button(class: "l2-next")
    assert_selector ".l2-counter", text: "Scheda 2 di 11"
    assert_selector "#draft-notice", count: draft ? 1 : 0, visible: :all
    deadline = Time.current + 15
    sleep 0.2 until LessonEvent.where(student: preview_student).exists? || Time.current > deadline
    assert LessonEvent.where(student: preview_student).exists?, "the cards seen are recorded for the preview student"
    assert_clean "the lesson"
    visit "#{ROOT}/topics/#{TOPIC}"
    first("a.button", text: "Esercitati").click
    assert_selector ".item-body input[inputmode=decimal]", wait: 30
    serve = PracticeServe.order(:id).last
    assert_equal preview_student.id, serve.student_id
    find(".item-body input[inputmode=decimal]").set(JSON.parse(serve.item_instance.answer_json).to_s)
    click_button "Controlla"
    assert_selector "#feedback", text: "Corretto."
    assert_equal 1, PracticeAttempt.where(student: preview_student).count
    assert_clean "the practice page"
  end

  test "the teacher walks the released course as S sees it, and nothing is written on S" do
    build_lesson2_world(name: "equations", approve: true, release: true)
    sign_in_as :teacher
    walk(draft: false)
    assert_equal [ preview_student.id ], PracticeServe.pluck(:student_id).uniq
    assert_empty LessonEvent.where.not(student_id: preview_student.id)
    assert_equal 0, Comment.count
  end

  test "the banner is one row at 1280 and on a phone, where «Opzioni» opens the switch and the reset and «Esci» stays (D-315)" do
    build_lesson2_world(name: "equations", approve: true, release: true)
    sign_in_as :teacher
    visit ROOT
    assert_selector "#preview-switch", text: "Passa a: Con le bozze"
    assert_no_selector "#preview-more summary"
    assert one_row?, "one row at 1280 (#{banner_height} px)"
    find("#preview-reset summary").click
    assert_selector "#preview-reset-confirm", text: "Sì, ricomincia"
    shot_at("banner-reset-open", 1280)
    page.driver.resize(390, 844)
    assert_selector "#preview-more summary", text: "Opzioni"
    assert_selector "#preview-exit", text: "Esci", exact_text: true
    assert_no_selector "#preview-switch"
    assert one_row?, "one row at 390 (#{banner_height} px)"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390, "nothing wider than the phone"
    assert_equal "Esci dalla prova", find("#preview-exit")["aria-label"]
    shot_at("banner-phone-closed", 390)
    find("#preview-more summary").click
    assert_selector "#preview-switch", text: "Passa a: Con le bozze"
    assert_selector "#preview-reset-confirm", text: "Sì, ricomincia"
    assert one_row?, "the panel opens over the page, the row keeps its height (#{banner_height} px)"
    shot_at("banner-phone-menu", 390)
    click_button "Passa a: Con le bozze"
    assert_selector "#preview-banner", text: "Con le bozze"
    assert_no_selector "#preview-switch"
    assert_clean "the banner on a phone"
  ensure
    page.driver.resize(1280, 900)
  end

  test "the drafts view shows the unreleased course flagged; the official view shows nothing of it; the reset starts again" do
    build_lesson2_world(name: "equations", approve: false, release: false)
    sign_in_as :teacher
    visit "#{ROOT}/subjects"
    assert_selector "#course-closed"
    visit "#{ROOT}/topics/#{TOPIC}"
    assert_equal 404, page.status_code
    @problems.clear # the refused page is the point of the check
    visit ROOT
    click_button "Passa a: Con le bozze"
    assert_selector "#preview-banner", text: "Vista: Con le bozze"
    walk(draft: true)
    old = preview_student
    visit ROOT
    find("#preview-reset summary").click
    click_button "Sì, ricomincia"
    assert_selector "#preview-banner", text: "Ricominci da capo"
    assert_no_selector "#resume"
    assert_not_equal old.id, preview_student.id
    assert_equal 0, PracticeServe.where(student: preview_student).count
    assert_operator PracticeServe.where(student: old).count, :>=, 1
    click_link "Esci dalla prova"
    assert_equal "/teacher", URI(page.current_url).path
  end
end
