require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# D-318: the results page says how each answer went, and the math field says, quietly, that words do not go in it.
class ResultsAndHintsTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  teardown { sign_out_env }

  def shot(name)
    dir = ENV["BANCO_SHOT_DIR"].presence or return
    FileUtils.mkdir_p(dir)
    page.save_screenshot(File.join(dir, "#{name}.png"), full: true)
  end

  test "the results page labels each answer and offers the flag only on a wrong one, on a phone" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    conductor = Diagnosis::Conductor.new(run)
    recorder = Diagnosis::AnswerRecorder.new(student: rows[:student], context: "diagnosis")
    5.times do
      step = conductor.step!
      break unless step.type == :item

      recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: "6", source: "text")
    end
    verdicts = %w[wrong correct dont_know nearly_correct short_answer]
    Attempt.order(:id).each_with_index do |attempt, i|
      AttemptGrading.create!(attempt: attempt, seq: attempt.gradings.maximum(:seq).to_i + 1, verdict: verdicts[i % verdicts.size], grader: "closed", grader_version: "t", source: "sync")
    end
    sign_in_as :student
    page.driver.resize(390, 800)
    visit "/diagnosis/runs/#{run.id}/results"
    assert_text "Hai finito Matematica."
    assert_selector "article.solution .solution-outcome .pill", count: Attempt.count
    assert_selector "article.solution[data-attempt='#{Attempt.order(:id).first.id}'] .solution-outcome", text: "Da rivedere"
    assert_selector "article.solution .flag-row", count: 1
    assert_selector "article.solution .flag-row button", text: "Penso che la mia risposta fosse giusta", count: 1
    wide = page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
    refute wide, "the page scrolls sideways at 390 px"
    shot("results-390")
    page.driver.resize(1280, 900)
    shot("results-1280")
  end

  test "words typed in the math field show one short line under it, and it goes with the words" do
    build_ui_subject
    release_diagnosis!
    sign_in_as :student
    visit "/diagnosis"
    click_button "Comincia"
    assert_text "Test d'ingresso · Matematica"
    click_button "Comincia"
    6.times do |n|
      assert_selector "[data-sitting-target=heading]", text: /Domanda #{n + 1}\z/
      assert_selector "[data-sitting-target=itemBox] .item-body .answer"
      click_button "Non lo so"
    end
    assert_selector "[data-sitting-target=heading]", text: /Domanda 7\z/
    find("math-field").click
    assert_no_selector ".words-hint p"
    type_keys(*"2x".chars)
    assert_no_selector ".words-hint p"
    type_keys(*"novalue".chars)
    assert_selector ".words-hint p", text: "Qui va solo l'espressione", count: 1
    assert_selector ".words-hint p", text: "premi «Non lo so»"
    shot("hint-1280")
    page.driver.resize(390, 800)
    shot("hint-390")
    # the hint does not block anything: the field still holds the text and the answer button is there
    assert_button "Invia"
    type_keys(*([ :backspace ] * 7))
    assert_no_selector ".words-hint p"
  end
end
