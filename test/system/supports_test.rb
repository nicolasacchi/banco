require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# D-216 in Chrome: the instructions on the start screen, the steps and the answer format on
# the item, the help box that follows the item and logs its opening, and the declared formula
# sheet: hidden when off, a button when on, one app event per opening.
class SupportsSystemTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  SHEET = "Area del rettangolo: $A = b \\cdot h$.\n\nPerimetro del quadrato: $P = 4 \\cdot l$.".freeze

  setup do
    @rows = build_ui_subject(components: %w[number], formula_sheet: SHEET)
    release_diagnosis!
    sign_in_as :student
  end

  teardown { sign_out_env }

  def switch_sheet!(enabled)
    Decision.create!(kind: "set_formula_sheet", subject: @rows[:subject], payload_json: { subject: "math", enabled: enabled }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "nik", groups: "banco-teacher", remote_addr: "127.0.0.1")
  end

  def start_sitting
    visit "/diagnosis"
    click_button "Comincia"
    assert_selector "section#how-it-works h2", text: "Come funziona"
    click_button "Comincia"
    assert_selector "[data-sitting-target=itemBox] .item-body .answer", wait: 30
  end

  test "the start screen explains how the test works, in short sentences" do
    visit "/diagnosis"
    click_button "Comincia"
    within "#how-it-works" do
      assert_text "Le domande cambiano in base alle tue risposte."
      assert_text "Il tempo in pausa non conta."
      assert_text "Vanno bene tutti e due. Non sono errori."
      assert_text "Dopo l'invio non puoi cambiarla."
      assert_selector "strong", text: "Pausa"
      assert_selector "strong", text: "Invia"
      assert_no_selector "em, i"
    end
    assert_no_selector "#intro-formula-sheet"
  end

  test "the item shows its steps above the input and its answer format under it" do
    start_sitting
    assert_selector ".item-body .do-steps li", count: 2
    assert_selector ".item-body .do-steps li", text: "Leggi il conto."
    assert_text "Cosa fare"
    assert_selector ".item-body .answer .answer-format", text: "Scrivi solo il numero, per esempio 12."
    order = page.evaluate_script(<<~JS)
      (() => {
        const steps = document.querySelector(".do-steps");
        const input = document.querySelector("input[inputmode=decimal]");
        return !!(steps.compareDocumentPosition(input) & Node.DOCUMENT_POSITION_FOLLOWING);
      })()
    JS
    assert order, "the steps come before the input"
  end

  test "the help box is closed, says how to answer this item and logs one app event per opening" do
    start_sitting
    assert_no_selector "details#answer-help[open]"
    assert_no_text "per esempio 0,75"
    before = [ DiagnosisEvent.count, Attempt.count ]
    find("details#answer-help summary").click
    assert_text "Per i decimali usa la virgola, per esempio 0,75."
    assert_text "Quando hai finito, premi Invia."
    assert_text "L'unità di misura è già scritta accanto alla casella."
    wait_until { AppEvent.where(kind: "help_opened").count == 1 }
    event = AppEvent.where(kind: "help_opened").sole
    assert_equal "number", JSON.parse(event.payload_json)["component"]
    assert_equal before, [ DiagnosisEvent.count, Attempt.count ], "the help changes nothing of the run"
    # Closing it logs nothing more; the box can still be used to answer.
    find("details#answer-help summary").click
    find("input[inputmode=decimal]").set(JSON.parse(ItemServed.last.item_instance.answer_json))
    click_button "Invia"
    assert_text "Risposta salvata", wait: 20
    assert_equal 1, AppEvent.where(kind: "help_opened").count
    assert_equal "correct", Attempt.last.gradings.last.verdict
  end

  test "with the sheet off there is no Formulario anywhere on the page" do
    start_sitting
    assert_no_button "Formulario"
    assert_no_selector "#formula-sheet:not([hidden])"
    assert_no_text "Area del rettangolo"
    assert_not page.html.include?("Area del rettangolo"), "the sheet's text is not in the page at all"
  end

  test "with the sheet on the button opens it read-only, and every opening is an event tied to the item" do
    switch_sheet!(true)
    visit "/diagnosis"
    click_button "Comincia"
    assert_selector "#intro-formula-sheet", text: "All'esame non c'è"
    click_button "Comincia"
    assert_selector "[data-sitting-target=itemBox] .item-body .answer", wait: 30
    assert_button "Formulario"
    assert_no_text "Area del rettangolo"
    click_button "Formulario"
    assert_selector "#formula-sheet h2", text: "Formulario"
    assert_text "Area del rettangolo"
    assert_selector "#formula-sheet .katex"
    assert_no_selector "#formula-sheet input, #formula-sheet textarea, #formula-sheet button"
    wait_until { AppEvent.where(kind: "formula_sheet_opened").count == 1 }
    click_button "Formulario"
    assert_no_selector "#formula-sheet:not([hidden])"
    click_button "Formulario"
    wait_until { AppEvent.where(kind: "formula_sheet_opened").count == 2 }
    served = ItemServed.sole
    assert served.formula_sheet_available
    assert_equal [ served.diagnosis_event_id ], AppEvent.where(kind: "formula_sheet_opened").map { |e| JSON.parse(e.payload_json)["served_event_id"] }.uniq

    find("input[inputmode=decimal]").set("6")
    click_button "Invia"
    assert_text "Risposta salvata", wait: 20
    skill = Diagnosis::Report.call(subject: @rows[:subject])[:subjects].sole[:skills].find { |s| s[:skill] == "math.number" }
    assert_equal({ attempts: 1, available: 1, opened: 1 }, skill[:formula_sheet])
  end

  def wait_until(seconds = 10)
    deadline = Time.now + seconds
    sleep 0.1 until yield || Time.now > deadline
    assert yield, "the condition did not hold in #{seconds} s"
  end
end
