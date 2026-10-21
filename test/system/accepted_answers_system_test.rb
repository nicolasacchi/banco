require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# D-317: an answer the program cannot read is not refused in the sitting. It is saved, S reads a short neutral line and goes
# on to the next question; the teacher finds it on the corrections page. Screenshots go to BANCO_SHOT_DIR (390 and 1280 px wide).
class AcceptedAnswersSystemTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))
  LINE = "Risposta salvata. La guarderà il docente.".freeze

  setup do
    @rows = build_ui_subject(components: %w[number fraction])
    release_diagnosis!
    sign_in_as :student
  end

  teardown { sign_out_env }

  def shot(name, width)
    FileUtils.mkdir_p(SHOT_DIR)
    page.driver.resize(width, 900)
    page.driver.save_screenshot(File.join(SHOT_DIR, "#{name}-#{width}.png"), full: true)
  end

  test "an unreadable number is saved with a neutral line, the sitting goes on, and the teacher sees it" do
    visit "/diagnosis"
    click_button "Comincia"
    click_button "Comincia"
    assert_selector "input[inputmode=decimal]"
    find("input[inputmode=decimal]").set("n = m = 2")
    click_button "Invia"
    assert_text LINE
    shot("sitting-saved-line", 390)
    shot("sitting-saved-line", 1280)
    assert_no_text "Non riesco a leggere"
    assert_selector "[data-sitting-target=heading]", text: /Domanda 2/
    assert_equal "n = m = 2", Attempt.sole.raw
    assert_equal "undetermined", Attempt.sole.gradings.sole.verdict

    sign_in_as :teacher
    visit "/teacher/corrections"
    assert_selector "article.verdict [data-unreadable]", text: "Risposta non leggibile dal programma"
    assert_selector "article.verdict [data-given]", text: "n = m = 2"
    shot("corrections-unreadable", 390)
    shot("corrections-unreadable", 1280)
  end
end
