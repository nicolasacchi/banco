require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/student_session"

# The evening screen in Chrome (B-06, operator G): a short answer with the grader's
# proposal and the quotes marked in the student's text, edited and confirmed; another one
# rejected; a one-letter slip resolved. Each click is a decision of the teacher, and the
# engine reads it as it already does.
class EveningConfirmationsTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession

  TEXT = "La causa fu la crisi del raccolto. Il re perse l'appoggio dei nobili.".freeze

  setup do
    build_decision_world
    @short_attempt = serve_and_answer(2, @short.instances.order(:id).second, TEXT)
    AttemptGrading.create!(attempt: @short_attempt, seq: 1, verdict: "short_answer", grader: "closed", grader_version: "t", source: "sync")
    @proposal = GradeProposal.create!(attempt: @short_attempt, agent_session: @session, total: 1, max_total: 2, threshold: 0.6, meets_threshold: false, missing_it: "Manca la conseguenza.",
                                      points_json: JSON.generate([ { point_id: "a", score: 1, quote: "La causa fu la crisi del raccolto", rationale_it: "Dice la causa." },
                                                                   { point_id: "b", score: 0, quote: nil, rationale_it: "Non dice la conseguenza." } ]))
    # A second short answer whose proposal the teacher will reject.
    @second = serve_and_answer(3, @short.instances.order(:id).third, "Non so.")
    AttemptGrading.create!(attempt: @second, seq: 1, verdict: "short_answer", grader: "closed", grader_version: "t", source: "sync")
    @second_proposal = GradeProposal.create!(attempt: @second, agent_session: @session, total: 2, max_total: 2, threshold: 0.6, meets_threshold: true,
                                             points_json: JSON.generate([ { point_id: "a", score: 1, quote: "Non so", rationale_it: "Sì." }, { point_id: "b", score: 1, quote: "Non so", rationale_it: "Sì." } ]))
    # A one-letter slip in a written word: pending until the teacher says so.
    text_revision = build_ui_revision(@subject, AgentSession.find_by!(label: "ui-author"), "normalized_text", skill_key("math", "normalized_text"))
    @slip = serve_and_answer(4, text_revision.instances.order(:id).first, "csa")
    AttemptGrading.create!(attempt: @slip, seq: 1, verdict: "near_miss", grader: "closed", grader_version: "t", source: "sync")
    @attempt_ids = [ @attempt.id, @short_attempt.id, @second.id, @slip.id ]
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  def serve_and_answer(seq, instance, raw)
    event = DiagnosisEvent.create!(diagnosis_run: @run, seq: seq, kind: "item_served", at: Time.current)
    ItemServed.create!(diagnosis_event: event, item_instance: instance, skill_key: JSON.parse(instance.item_revision.body_json)["skill"])
    Attempt.create!(student: @student, context: "diagnosis", served_event: event, client_attempt_id: "c-#{seq}-#{SecureRandom.hex(3)}", item_instance: instance,
                    raw: raw, source: "text", answered_at: Time.current)
  end

  test "the evening screen: quotes marked, edit and confirm, reject with a reason, resolve a slip" do
    visit "/teacher"
    assert_selector "#waiting-summary a", text: /correzion/
    click_link "Correzioni"
    assert_selector "h1", text: "Correzioni"
    assert_selector "#corrections-summary", text: "Verdetti incerti: 1"

    # The quote is marked in the student's own text.
    within("article.short[data-attempt='#{@short_attempt.id}']") do
      assert_selector "[data-student-text] mark", text: "La causa fu la crisi del raccolto"
      assert_text "La proposta dà 1 su 2: sotto la soglia."
      assert_text "Non dice la conseguenza."
      # Edit: the teacher gives the second point too.
      find("summary", text: "Modifica i punteggi").click
      find("input[name='scores[b]']").set("1")
      fill_in "reason_it", with: "La conseguenza c'è, in fondo al testo.", match: :first
      click_button "Conferma con le mie modifiche"
    end
    assert_selector ".flash", text: "Voto confermato."
    decision = Decision.where(kind: "confirm_grade").sole
    payload = JSON.parse(decision.payload_json)
    assert_equal [ @short_attempt.id, true, 2, true ], [ payload["attempt_id"], payload["edited"], payload["total"], payload["passed"] ]
    assert_equal({ "a" => 1, "b" => 1 }, payload["scores"])
    assert_no_selector "article.short[data-attempt='#{@short_attempt.id}']"

    # Reject the other proposal, with a reason.
    within("article.short[data-attempt='#{@second.id}']") do
      assert_selector "mark", text: "Non so"
      within("form[action$='/reject']") do
        fill_in "reason_it", with: "Non cita il testo."
        click_button "Respingi"
      end
    end
    assert_selector ".flash", text: "Proposta respinta."
    within("article.short[data-attempt='#{@second.id}']") { assert_text "L'agente non ha ancora fatto una proposta." }
    assert_equal "Non cita il testo.", JSON.parse(Decision.where(kind: "reject_grade").sole.payload_json)["reason_it"]

    # The slip: one click, with the default reason.
    within("article.verdict[data-attempt='#{@slip.id}']") do
      assert_text "quasi giusta"
      assert_selector "[data-given]", text: "csa"
      click_button "Giusta"
    end
    assert_selector ".flash", text: "Risposta risolta."
    assert_no_selector "article.verdict"
    resolved = JSON.parse(Decision.where(kind: "resolve_attempt").sole.payload_json)
    assert_equal [ @slip.id, "correct" ], [ resolved["attempt_id"], resolved["verdict"] ]
    assert_text "Nessun verdetto incerto aspetta."

    # What the engine reads: the edited confirmation and the resolution.
    events = Diagnosis::EventLoader.for_run(@run)
    assert_includes events.map { |e| e[:kind].to_s }, "confirm_grade"
  end

  test "a decision with no reason is refused with a sentence, and nothing is written" do
    visit "/teacher/corrections"
    within("article.short[data-attempt='#{@second.id}']") do
      within("form[action$='/reject']") do
        page.execute_script("document.getElementById('reject-reason-#{@second.id}').removeAttribute('required')")
        click_button "Respingi"
      end
    end
    assert_selector ".flash.alert", text: /Scrivi il motivo/
    assert_equal 0, Decision.where(kind: "reject_grade").count
  end
end
