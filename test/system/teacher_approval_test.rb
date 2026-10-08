require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/student_session"

# A subject from draft to approved through the teacher's screens, in Chrome: the graph,
# the gate that keeps "Approva il test" off until everything is done, a finding that
# needs a disposition, an item played as S, the whole test played as S, and the approval.
class TeacherApprovalTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession

  setup do
    @world = build_ui_subject(components: %w[number choice], approve: false)
    @subject = @world[:subject]
    @blueprint = @world[:blueprint]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    @session = AgentSession.create!(label: "rev", role: "reviewer", agent: "omp", model: "gpt-5.2")
    # What the agents did: an expert review and a blind solve on every pinned item, and a
    # major finding on the number item that the teacher has to decide on.
    @blueprint.pinned_item_revision_ids.each do |id|
      revision = ItemRevision.find(id)
      ItemReview.create!(item_revision: revision, agent_session: @session, checklist_json: [ { id: 1, result: "pass", evidence: "Chiave controllata a mano." } ].to_json)
      BlindSolve.create!(item_revision: revision, agent_session: @session, answers_json: "[]", results_json: [ { instance: 1, verdict: "correct" } ].to_json)
    end
    @number = @world[:revisions]["number"]
    @finding = ReviewFinding.create!(item_revision: @number, source: "review", severity: "major", field: "stem", quote: "Calcola e scrivi il risultato.",
                                     problem_it: "La consegna non dice l'unità.", fix_it: "Aggiungi l'unità.")
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  test "from draft to approved through the screens" do
    visit "/teacher"
    assert_selector "li.subject[data-subject=math] [data-waiting=graph_to_approve]"
    assert_selector "li.subject[data-subject=math] [data-waiting=findings]", text: "Rilievi da decidere: 1"

    # The graph first.
    click_link "Grafo"
    assert_selector "h1", text: "Grafo delle abilità · Matematica"
    assert_selector "article.skill", count: 2
    assert_selector "#graph-approve button:not([disabled])"
    click_button "Approva il grafo"
    assert_selector ".flash", text: "Grafo approvato."
    assert_selector "#graph-approve button[disabled]"
    assert Decision.exists?(kind: "approve_skill_graph", subject: @subject)

    # The test: the button is off and says why.
    visit "/teacher/subjects/math/test"
    assert_selector "#test-approve[data-approvable=false] button[disabled]"
    within("#test-approve-why") do
      assert_text "Il pulsante resta spento finché manca questo"
      assert_text "rilievi gravi senza una tua decisione"
      assert_text "Apri la schermata dell'abilità"
      assert_text "Gioca il test fino in fondo"
    end

    # One screen per skill: items side by side, then the finding gets its disposition.
    click_link "Abilità number"
    assert_selector "article.item-card", count: 1
    assert_selector "article.item-card .sample", count: 4
    assert_text "Chiave:"
    assert_selector "[data-finding='#{@finding.id}']"
    within("[data-finding='#{@finding.id}']") do
      fill_in "reason_it", with: "Il testo dice già l'unità."
      click_button "La domanda è giusta: scarta il rilievo"
    end
    assert_selector ".flash", text: "Decisione sul rilievo registrata."
    assert_selector "[data-finding='#{@finding.id}'][data-disposition=dismissed]"
    assert_equal "dismissed", ReviewFinding.dispositions[@finding.id]

    # An item played as S, with the student's own renderer.
    within("article.item-card") { click_link "Prova come S" }
    assert_selector ".banner", text: "Nessuna risposta viene salvata"
    assert_selector ".item-body .answer"
    find("input[inputmode=decimal]").set("8")
    click_button "Invia"
    assert_text "In questa prova la risposta non si salva."
    assert_equal 0, Attempt.count

    # The other skill's screen (opening it is what the gate wants).
    visit "/teacher/subjects/math/test/skills/math.choice"
    assert_selector "article.item-card .sample", count: 4

    # The whole test as S.
    visit "/teacher/subjects/math/test"
    assert_selector "#test-approve button[disabled]"
    assert_text "Gioca il test fino in fondo"
    click_button "Prova tutto il test come S"
    assert_text "Anteprima del docente"
    click_button "Comincia"
    answered = 0
    while answered < 12 && page.has_button?("Non lo so", wait: 6)
      click_button "Non lo so"
      answered += 1
      wait_until { Attempt.where(context: "teacher_preview").count == answered }
    end
    assert_text "Hai finito Matematica"

    # Now the gates are open and the approval goes through.
    visit "/teacher/subjects/math/test"
    assert_selector "#test-approve[data-approvable=true]"
    assert_selector "#test-approve button:not([disabled])", text: "Approva il test"
    click_button "Approva il test"
    assert_selector ".flash", text: "Test d'ingresso approvato."
    assert_text "Questa revisione è approvata."
    assert Decision.exists?(kind: "approve_blueprint", subject: @subject)

    visit "/teacher"
    assert_selector "li.subject[data-subject=math][data-stage=approved]"
    assert_selector "li.subject[data-subject=math] strong", text: "Approvata"
  end

  def wait_until(seconds = 15)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until yield
      flunk "the condition did not come true in #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.2
    end
  end

  test "the student's computer reads the screens but cannot decide" do
    visit "/teacher"
    page.driver.set_cookie(DecisionRecorder::DEVICE_COOKIE, "bogus")
    visit "/teacher/subjects/math/graph"
    assert_text "Questo è il computer di S"
    assert_selector "#graph-approve button[disabled]"
  end
end
