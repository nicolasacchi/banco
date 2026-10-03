require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# E-10: an answer never gets lost. It is written to the local outbox before it is
# posted, leaves only when the server says "recorded", and is resent after a login.
class OutboxTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  setup do
    SessionExpiry.reset!
    @rows = build_ui_subject
    release_diagnosis!
    sign_in_as :student
    visit "/diagnosis"
    click_button "Comincia"
    click_button "Comincia"
    assert_selector "input[inputmode=decimal]"
  end

  teardown do
    SessionExpiry.reset!
    sign_out_env
  end

  def queued = page.evaluate_script("Object.keys(localStorage).filter(function (k) { return k.indexOf('banco.outbox.') === 0 })")

  def type_answer(text)
    find("input[inputmode=decimal]").set(text)
    click_button "Invia"
  end

  def signed_in_again
    SessionExpiry.mode = nil
    click_button "Accedi di nuovo"
  end

  test "an answer survives a session-expiry redirect and is recorded once" do
    SessionExpiry.mode = :redirect
    type_answer("6")
    assert_text "La tua risposta è salvata su questo computer. Accedi di nuovo e continua."
    assert_button "Accedi di nuovo"
    assert_equal 0, Attempt.count
    assert_equal 1, queued.size
    assert_operator SessionExpiry.hits, :>=, 1

    signed_in_again
    # After the login the page loads again and resends what is queued.
    assert_text "Test d'ingresso · Matematica"
    Timeout.timeout(20) { sleep 0.2 until Attempt.count == 1 }
    assert_equal 1, Attempt.count
    assert_equal "6", Attempt.first.raw
    assert_equal 1, AttemptGrading.count
    Timeout.timeout(10) { sleep 0.2 until queued.empty? }
    assert_empty queued

    # And the sitting goes on from the next item.
    click_button "Riprendi"
    assert_selector "[data-sitting-target=heading]", text: /Domanda 2/
  end

  test "a login page that answers 200 is not taken for a reply" do
    SessionExpiry.mode = :html
    type_answer("7")
    assert_text "La tua risposta è salvata su questo computer."
    assert_equal 0, Attempt.count
    assert_equal 1, queued.size
  end

  test "a 401 keeps the answer queued" do
    SessionExpiry.mode = :unauthorized
    type_answer("8")
    assert_text "La tua risposta è salvata su questo computer."
    assert_equal 1, queued.size
    assert_equal 0, Attempt.count
  end

  test "an answer whose reply was lost is sent again and still recorded once" do
    SessionExpiry.mode = :lose_reply
    type_answer("9")
    assert_text "La tua risposta è salvata su questo computer."
    assert_equal 1, Attempt.count, "the server did record it the first time"
    signed_in_again
    assert_text "Test d'ingresso · Matematica"
    Timeout.timeout(10) { sleep 0.2 until queued.empty? }
    assert_equal 1, Attempt.count
    assert_equal 1, AttemptGrading.count
  end

  test "the queue survives a reload while the session is still expired" do
    SessionExpiry.mode = :redirect
    type_answer("5")
    assert_text "La tua risposta è salvata su questo computer."
    visit current_path # the login did not happen yet: the page loads, the answer stays queued
    sleep 1
    assert_equal 1, queued.size
    assert_equal 0, Attempt.count
    SessionExpiry.mode = nil
    visit current_path
    Timeout.timeout(20) { sleep 0.2 until Attempt.count == 1 }
    assert_equal 1, Attempt.count
  end
end
