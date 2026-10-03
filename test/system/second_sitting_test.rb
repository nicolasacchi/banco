require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# The automatic second sitting (operator Q11): when a sitting uses up its time with
# the frontier still open, the student reads "C'è ancora una parte", no solutions,
# and the rest is for another day.
class SecondSittingTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  setup do
    @rows = build_ui_subject(components: %w[number choice ordering matching], sitting_minutes: 10)
    release_diagnosis!
    sign_in_as :student
    # An earlier day: one item served and answered, taking the whole budget.
    clock = Diagnosis::FakeClock.new(Time.current - 3 * 86_400)
    @run = Diagnosis::Conductor.run_for(@rows[:student], @rows[:subject])
    conductor = Diagnosis::Conductor.new(@run, clock: clock)
    step = conductor.step!
    clock.advance(650)
    Diagnosis::AnswerRecorder.new(student: @rows[:student], context: "diagnosis", clock: clock)
                             .call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: Grading::DONT_KNOW_RAW, source: "button")
  end

  teardown { sign_out_env }

  test "the sitting ends with C'è ancora una parte, then the subject waits for the next day" do
    visit "/diagnosis"
    assert_selector "li.subject[data-subject=math] .subject-state", text: "In pausa"
    click_button "Riprendi"
    assert_text "Test d'ingresso · Matematica"
    click_button "Riprendi"
    assert_selector "h1", text: "C'è ancora una parte"
    assert_text "Il resto di Matematica lo fai domani, in una seconda parte."
    assert_no_text "Soluzione"
    assert_no_text "Hai finito"
    assert_equal 1, @run.events.where(kind: "sitting_closed").count

    visit "/diagnosis"
    assert_selector "li.subject[data-subject=math] .subject-state", text: "Resta una parte da fare"
    assert_no_selector "li.subject[data-subject=math] form", wait: 1

    # A bookmarked page does not let the student start the second part today.
    visit "/diagnosis/runs/#{@run.id}"
    assert_text "Test d'ingresso · Matematica · seconda parte"
    click_button "Comincia"
    assert_selector "h1", text: "Per oggi basta così."
    assert_text "Puoi riprendere domani."
  end
end
