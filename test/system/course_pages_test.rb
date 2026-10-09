require "application_system_test_case"
require_relative "../support/student_course_world"
require_relative "../support/student_session"

# The student's course pages in Chrome (A9, A12): a trial student goes from Oggi through the lesson to the
# practice and meets every kind of answer; the keyboard alone does the same; the official student sees
# nothing until release_course; the lesson at 390 px.
class CourseSystemTest < ApplicationSystemTestCase
  include StudentCourseWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  OFFICIAL_HEADERS = { "Remote-User" => "kid-a", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "kid-a=student,trial-x=prova-1"
  end

  teardown do
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def sign_in_trial
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
  end

  def sign_in_official
    sign_in_as :student
    page.driver.headers = OFFICIAL_HEADERS
  end

  def watch_csp
    page.execute_script("window.__csp = []; document.addEventListener('securitypolicyviolation', e => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI));")
  end

  def assert_csp_clean = assert_equal([], page.evaluate_script("window.__csp"))

  def open_practice
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_selector ".item-body input[inputmode=decimal]", wait: 30
    watch_csp
  end

  def serve_row = PracticeServe.order(:id).last

  def answer_of(serve) = JSON.parse(serve.item_instance.answer_json).to_s
  def slip_of(serve) = JSON.parse(serve.item_instance.errors_json).first["value"].to_s

  def type_answer(text)
    find(".item-body input[inputmode=decimal]").set(text)
    click_button "Controlla"
  end

  test "a trial student: Oggi, the topic, the lesson with its solution on request" do
    build_student_world(approve: false, release: false)
    sign_in_trial
    visit "/today"
    assert_selector "#trial-notice"
    assert_selector "#suggestions li.topic", count: 1
    click_link TOPIC_TITLE
    assert_selector "#draft-notice", text: "Bozza: il docente non l'ha ancora approvata."
    assert_selector "#programme li", text: "Dal programma, riga 7"
    click_link "Leggi la lezione"
    assert_selector "h2", text: "Perché ti serve"
    assert_selector "[data-lesson-markup] strong", text: "problema"
    assert_selector "[data-lesson-markup] .katex", minimum: 3
    assert_selector "#section-idea ul ul li", text: "lo fai anche all'altro"
    assert_selector "#section-mistakes ul li", count: 3
    assert_no_text SECRET_SOLUTION
    assert_no_text SECRET_FINAL
    within("#exercise-1") { click_button "Mostra la soluzione" }
    assert_selector "#solution-1", text: SECRET_SOLUTION
    assert_selector "#solution-1 ol li", count: 2
    assert_no_text SECRET_FINAL
    assert_equal 1, PracticeEvent.where(kind: "lesson_solution_shown").count
    assert_equal 1, PracticeEvent.where(kind: "lesson_opened").count
  end

  test "a question from the lesson goes to the teacher, keyboard closes the box" do
    build_student_world
    sign_in_trial
    visit "/topics/#{TOPIC}/lesson"
    within("#section-idea") do
      click_button "Non ho capito"
      fill_in "Che cosa non ti è chiaro? (facoltativo, una riga)", with: "La bilancia?"
      click_button "Invia"
      assert_text "Fatto: il docente lo vedrà."
    end
    q = StudentQuestion.last
    assert_equal [ "idea", "La bilancia?" ], [ q.section, q.text_it ]
    within("#section-why") do
      click_button "Non ho capito"
      assert_selector "input[type=text]"
      page.driver.browser.keyboard.type(:Escape)
      assert_no_selector "input[type=text]"
    end
  end

  test "practice: correct, typical error with Prova questo, unrecognised with hints, aided correct, show solution" do
    build_student_world
    sign_in_trial
    open_practice
    assert_text "Il procedimento sul foglio, qui solo il risultato."
    # a correct answer
    first = serve_row
    type_answer answer_of(first)
    assert_selector "#feedback", text: "Corretto."
    assert_selector "#solution h2", text: "Soluzione"
    assert_selector "#next-actions button", text: "Un altro esercizio"
    assert_selector "#next-actions a", text: "Torna all'argomento"
    assert_no_selector "#check", visible: true
    assert_selector "#skill-state", text: "In studio"
    # a typical error: the message of the catalogue, no solution, Prova questo
    click_button "Un altro esercizio"
    assert_selector ".item-body input[inputmode=decimal]"
    assert_no_selector "#solution h2"
    second = serve_row
    assert_not_equal first.id, second.id
    type_answer slip_of(second)
    assert_selector "#feedback", text: "Hai sbagliato un segno."
    assert_no_selector "#solution h2"
    click_button "Prova questo"
    assert_selector "#serve-reason", text: "Un esercizio simile, per lo stesso errore."
    third = serve_row
    assert_equal [ "prova_questo", "slip", second.id ], [ third.reason, third.error_code, third.parent_serve_id ]
    # unrecognised: the first hint comes with the message, then a retry
    type_answer "99999"
    assert_selector "#feedback", text: "Questa risposta non corrisponde a un errore che conosco"
    assert_selector "#hints li", text: "Che cosa guardi prima?"
    assert_selector "#hint-button", text: "Mostra un aiuto (2 di 3)"
    click_button "Mostra un aiuto (2 di 3)"
    assert_selector "#hints li", count: 2
    assert_no_text "Fai il primo passaggio."
    type_answer answer_of(third)
    assert_selector "#feedback", text: "Corretto, con un aiuto."
    # a fresh serve, the solution on request
    click_button "Un altro esercizio"
    assert_selector ".item-body input[inputmode=decimal]"
    click_button "Mostrami la soluzione"
    assert_selector "#solution li", text: "Passo."
    assert_selector "#next-actions button", text: "Prova un esercizio simile"
    click_button "Prova un esercizio simile"
    assert_selector ".item-body input[inputmode=decimal]"
    assert_equal "after_solution", serve_row.reason
    assert_csp_clean
    assert_equal 0, Attempt.count
    assert_empty page.evaluate_script("Object.keys(localStorage).filter(k => k.startsWith('banco.poutbox.'))")
  end

  test "a reload gets the same open serve back, with the hints already shown" do
    build_student_world
    sign_in_trial
    open_practice
    serve = serve_row
    type_answer "99999"
    assert_selector "#hints li", text: "Che cosa guardi prima?"
    visit current_path
    assert_selector ".item-body input[inputmode=decimal]", wait: 30
    assert_selector "#hints li", count: 1
    assert_equal serve.id, serve_row.id
    assert_equal 1, PracticeServe.count
  end

  test "keyboard only: type, Tab to Controlla, Enter; the focus goes to the next step; the feedback is a live region" do
    build_student_world
    sign_in_trial
    open_practice
    assert_equal "polite", find("#feedback")[:"aria-live"]
    assert_equal "status", find("#feedback")[:role]
    serve = serve_row
    focused = page.evaluate_script("document.activeElement.getAttribute('inputmode')")
    assert_equal "decimal", focused, "the input has the focus when the exercise appears"
    type_keys(*answer_of(serve).chars, :Tab)
    assert_equal "check", page.evaluate_script("document.activeElement.id")
    type_keys(:Enter)
    assert_selector "#feedback", text: "Corretto."
    assert_equal "Un altro esercizio", page.evaluate_script("document.activeElement.textContent")
    type_keys(:Enter)
    assert_selector ".item-body input[inputmode=decimal]"
    assert_not_equal serve.id, serve_row.id
    assert_equal "decimal", page.evaluate_script("document.activeElement.getAttribute('inputmode')")
    # the hint button and the solution are reachable by Tab, in order
    type_keys(:Tab, :Tab)
    assert_equal "hint-button", page.evaluate_script("document.activeElement.id")
    type_keys(:Enter)
    assert_selector "#hints li", text: "Che cosa guardi prima?"
  end

  test "an empty answer is told, not sent" do
    build_student_world
    sign_in_trial
    open_practice
    click_button "Controlla"
    assert_selector "#feedback", text: "Scrivi prima una risposta."
    assert_equal 0, PracticeAttempt.count
  end

  test "the official student sees nothing until the release, then the course" do
    build_student_world(release: false)
    sign_in_official
    visit "/today"
    assert_no_selector "#course-part"
    assert_no_selector "#suggestions"
    visit "/topics/#{TOPIC}"
    assert_no_text TOPIC_TITLE
    release_course!(@course)
    visit "/today"
    assert_selector "#suggestions li.topic", count: 1
    assert_no_selector "#draft-notice"
    visit "/diagnosis"
    assert_selector "#menu-subjects", text: "Materie"
  end

  test "the lesson at 390 px" do
    build_student_world
    sign_in_trial
    page.driver.resize(390, 844)
    visit "/topics/#{TOPIC}/lesson"
    assert_selector "[data-lesson-markup] .katex", minimum: 3
    width = page.evaluate_script("document.documentElement.scrollWidth")
    assert_operator width, :<=, 390, "the lesson does not scroll sideways"
    FileUtils.mkdir_p(SHOT_DIR)
    page.driver.save_screenshot(File.join(SHOT_DIR, "lesson-390.png"), full: true)
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_selector ".item-body input[inputmode=decimal]", wait: 30
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.driver.save_screenshot(File.join(SHOT_DIR, "practice-390.png"), full: true)
  end
end
