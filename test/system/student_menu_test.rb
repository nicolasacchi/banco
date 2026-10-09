require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# D-240 in Chrome: the menu is on every page, reachable and operable with the keyboard, reduced to one "Pausa"
# item in a sitting (with a one-line confirm for an answer typed and not sent), and it stays readable at the
# largest text size on a phone. Screenshots go to BANCO_SHOT_DIR when it is set.
class StudentMenuSystemTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  SHOT_DIR = ENV["BANCO_SHOT_DIR"]

  setup do
    @rows = build_ui_subject(components: %w[number choice])
    release_diagnosis!
    sign_in_as :student
    page.driver.resize(1366, 900)
  end

  teardown { sign_out_env }

  def shot(name)
    return unless SHOT_DIR

    FileUtils.mkdir_p(SHOT_DIR)
    page.driver.save_screenshot(File.join(SHOT_DIR, "#{name}.png"), full: true)
  end

  def menu_overflow = page.evaluate_script("document.documentElement.scrollWidth")

  test "the bare address lands on Oggi with the menu and the current page marked" do
    visit "/"
    assert_current_path "/today"
    within("nav.student-menu") do
      assert_selector "a[aria-current=page]", text: "Oggi"
      assert_link "Test d'ingresso"
      assert_link "Impostazioni"
    end
    assert_selector "#entry-next", text: "Comincia"
    shot "today-desktop"
  end

  test "the keyboard reaches every item, shows the focus and follows a link with Enter" do
    visit "/today"
    ids = page.evaluate_script("Array.from(document.querySelectorAll('nav.student-menu a')).map(function (a) { return a.id })")
    assert_equal %w[menu-today menu-diagnosis menu-settings], ids
    seen = []
    ids.size.times do
      type_keys(:Tab)
      seen << page.evaluate_script("document.activeElement.id")
    end
    assert_equal ids, seen.first(ids.size)
    outline = page.evaluate_script("getComputedStyle(document.activeElement).outlineStyle")
    assert_not_equal "none", outline
    type_keys(:Shift, :Tab) # back to the second item
    type_keys(:Enter)
    assert_current_path "/diagnosis"
    assert_selector "nav.student-menu a[aria-current=page]", text: "Test d'ingresso"
    assert_selector "h1", text: "Test d'ingresso"
  end

  test "targets are large and the menu fits a phone at the largest size" do
    visit "/settings"
    choose "Molto grande"
    click_button "Salva"
    assert_selector "html[data-size=larger]"
    page.driver.resize(390, 844)
    visit "/today"
    heights = page.evaluate_script("Array.from(document.querySelectorAll('nav.student-menu a')).map(function (a) { return a.getBoundingClientRect().height })")
    assert heights.all? { |h| h >= 44 }, heights.inspect
    assert_operator menu_overflow, :<=, 390, "no sideways scroll"
    labels = page.evaluate_script("Array.from(document.querySelectorAll('nav.student-menu a')).map(function (a) { return a.scrollWidth <= a.clientWidth + 1 })")
    assert labels.all?, "every label is fully visible"
    shot "today-phone-larger"
    visit "/settings"
    shot "settings-phone-larger"
    visit "/diagnosis"
    shot "diagnosis-phone-larger"
    page.driver.resize(1366, 900)
    visit "/today"
    shot "today-desktop-larger"
  end

  test "in a sitting the menu is one item; leaving pauses and goes to Oggi" do
    visit "/today"
    click_button "Comincia"
    assert_selector "nav.student-menu a", count: 1, text: "Pausa: torna a Oggi"
    shot "sitting-intro-desktop"
    click_button "Comincia"
    assert_selector "[data-sitting-target=itemBox] .item-body .answer"
    assert_selector "nav.student-menu a", count: 1
    shot "sitting-item-desktop"
    click_link "Pausa: torna a Oggi"
    assert_current_path "/today"
    assert_selector "#entry-next", text: "Riprendi"
    run = DiagnosisRun.find_by!(student: @rows[:student])
    assert run.events.exists?(kind: "paused"), "the pause is recorded"
  end

  test "an answer typed and not sent asks one line first; staying keeps it, leaving goes to Oggi" do
    visit "/diagnosis"
    click_button "Comincia"
    click_button "Comincia"
    assert_selector "[data-sitting-target=itemBox] .item-body .answer"
    field = first("input, textarea", minimum: 1, visible: true)
    if field.nil? || field[:type] == "radio"
      first("[role=radio], input[type=radio], .option-text").click
    else
      field.set("7")
    end
    click_link "Pausa: torna a Oggi"
    assert_selector "#leave-confirm", text: "non l'hai ancora inviata"
    assert_current_path %r{/diagnosis/runs/\d+}
    shot "sitting-leave-confirm-desktop"
    click_button "Resta qui"
    assert_no_selector "#leave-confirm", visible: true
    click_link "Pausa: torna a Oggi"
    click_button "Esci senza inviare"
    assert_current_path "/today"
    assert_equal 0, Attempt.count
  end

  test "an empty field leaves at once, without a question" do
    visit "/diagnosis"
    click_button "Comincia"
    click_button "Comincia"
    assert_selector "[data-sitting-target=itemBox] .item-body .answer"
    click_link "Pausa: torna a Oggi"
    assert_current_path "/today"
  end

  test "the teacher's preview shows no student menu and keeps Chiudi l'anteprima" do
    sign_in_as :teacher
    visit "/teacher/preview"
    assert_no_selector "nav.student-menu"
    click_button "Prova Matematica"
    assert_no_selector "nav.student-menu"
    assert_selector "#preview-close"
  end

  test "settings, tablet and phone views for the record" do
    visit "/today"
    shot "today-desktop-normal"
    page.driver.resize(390, 844)
    visit "/today"
    shot "today-phone-normal"
    visit "/settings"
    assert_selector "nav.student-menu a[aria-current=page]", text: "Impostazioni"
    shot "settings-phone-normal"
  end
end
