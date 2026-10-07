require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/student_session"

# The page of all the questions, in Chrome: every instance drawn by the student's templates
# and switched off, the answers behind "Mostra risposte", the confirmation, and the
# "Chiudi l'anteprima" button of the preview.
class AllQuestionsSystemTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession

  setup do
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @blueprint = @world[:blueprint]
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  test "the questions are drawn read-only, the answers appear with the toggle, the confirmation is recorded" do
    visit "/teacher/subjects/math/test/all"
    assert_selector "h1", text: "Tutte le domande · Matematica"
    assert_selector "article.q-item", count: @blueprint.pinned_item_revision_ids.size

    # The first instance of every item is drawn; the others wait in the folded part.
    assert_selector "article.q-item > .q-instance .item-body", count: @blueprint.pinned_item_revision_ids.size
    assert_selector "details.q-others:not([open])", count: @blueprint.pinned_item_revision_ids.size
    assert_selector "details.q-others .item-body", count: 0, visible: :all

    # Nothing takes input.
    assert_selector "article[data-component=number] input", visible: :all
    assert_equal 0, page.evaluate_script("document.querySelectorAll('.q-render input:not([disabled]), .q-render textarea:not([disabled]), .q-render button:not([disabled])').length")
    assert_selector "article[data-component=testlet] .passage", text: "brano"
    assert_selector "article[data-component=testlet] .sub-item", count: 10

    # The answers are hidden until the toggle.
    number = "article[data-component=number]"
    assert_no_text "adds_wrong"
    assert_no_selector "#{number} .q-answers", visible: :visible
    check "Mostra risposte"
    assert_selector "#{number} .q-instance .q-answers [data-key]", visible: :visible, minimum: 1
    assert_text "adds_wrong"
    assert_text "Una risposta."
    uncheck "Mostra risposte"
    assert_no_text "adds_wrong"

    # The other variants open, and are drawn.
    within(number) { find("details.q-others summary").click }
    assert_selector "#{number} details.q-others[open] .item-body", count: 4
    assert_equal 0, page.evaluate_script("document.querySelectorAll('.q-render input:not([disabled])').length")

    # Confirmation.
    assert_selector "#all-confirm button:not([disabled])"
    click_button "Ho visto tutte le domande di questa prova"
    assert_selector ".flash", text: "Registrato: hai visto tutte le domande di questa prova."
    assert_selector "#all-confirm[data-confirmed=true] button[disabled]"
    assert Decision.exists?(kind: "confirm_test_reviewed", subject: @subject)
    assert_equal 0, Attempt.count
  end

  test "Chiudi l'anteprima closes the preview run and returns to the test page" do
    visit "/teacher/subjects/math/test"
    click_button "Prova tutto il test come S"
    assert_text "Anteprima del docente"
    assert_selector "#preview-close", text: "Chiudi l'anteprima"
    run = DiagnosisRun.where(student: @world[:preview]).order(:id).last
    refute Diagnosis::Conductor.new(run).closed?
    click_button "Chiudi l'anteprima"
    assert_current_path "/teacher/subjects/math/test"
    assert_selector ".flash", text: "Anteprima chiusa."
    assert Diagnosis::Conductor.new(run.reload).closed?
    # Closing is not playing: the gate still wants a played test or the confirmation.
    assert_text "oppure apri «Tutte le domande»"
  end
end
