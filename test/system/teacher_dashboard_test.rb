require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/student_session"

# D-240: the open dashboard follows the ledger. A change made server-side shows after a short poll; a change
# announced from another window by BroadcastChannel shows at once; the scroll stays, the changed row says
# "aggiornato ora" for a while, and the page stays clean under the CSP.
class TeacherDashboardSystemTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession

  setup do
    @saved_poll = ENV["BANCO_DASHBOARD_POLL"]
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @session = AgentSession.create!(label: "rev", role: "reviewer", agent: "omp", model: "gpt-5.2")
    sign_in_as :teacher
  end

  teardown do
    @saved_poll ? ENV["BANCO_DASHBOARD_POLL"] = @saved_poll : ENV.delete("BANCO_DASHBOARD_POLL")
    sign_out_env
  end

  def add_finding!
    revision = @world[:revisions]["normalized_text"]
    ReviewFinding.create!(item_revision: revision, source: "blind_solve", blind_solve: BlindSolve.create!(item_revision: revision, agent_session: @session, answers_json: "[]", results_json: "[]"),
                          severity: "blocker", code: "E-BLIND-SOLVE-MISMATCH", instance: 1, field: "instances/1", quote: "x", problem_it: "Non torna.", fix_it: "Controlla.")
  end

  def tall!
    page.execute_script("document.body.style.minHeight = '4000px'; window.scrollTo(0, 300)")
    assert_operator page.evaluate_script("window.scrollY"), :>=, 250
  end

  test "a change made on the server shows after a short poll, keeps the scroll and says aggiornato ora" do
    ENV["BANCO_DASHBOARD_POLL"] = "1"
    visit "/teacher"
    assert_selector "#dashboard[data-controller=dashboard]"
    assert_text(/Aggiornato alle \d\d:\d\d/)
    assert_no_selector "li[data-todo=findings]"
    tall!
    page.execute_script("window.__violations = []; document.addEventListener('securitypolicyviolation', (e) => window.__violations.push(e.violatedDirective))")
    add_finding!
    assert_selector "li[data-todo=findings]", text: "Un rilievo da decidere."
    assert_selector "li[data-todo=findings] .updated-badge", text: "aggiornato ora"
    assert_selector "#dashboard-live", text: /Aggiornato: /, visible: :all
    assert_in_delta 300, page.evaluate_script("window.scrollY"), 60
    assert_empty page.evaluate_script("window.__violations")
    using_wait_time(20) { assert_no_selector ".updated-badge" }
  end

  test "another window announcing a decision updates the dashboard at once" do
    ENV["BANCO_DASHBOARD_POLL"] = "600"
    visit "/teacher"
    assert_selector "#dashboard-body"
    assert_no_selector "li[data-todo=findings]"
    other = open_new_window
    within_window(other) do
      visit "/teacher/subjects/math/graph"
      add_finding!
      page.execute_script("const c = new BroadcastChannel('banco'); c.postMessage({ type: 'decided' }); c.close()")
    end
    assert_selector "li[data-todo=findings]", text: "Un rilievo da decidere."
    other.close
  end

  test "the manual button refreshes, the toggle switches the new tabs off and is remembered" do
    visit "/teacher"
    assert_selector "#dashboard-body a[target=_blank]"
    uncheck "dashboard-newtab"
    assert_no_selector "#dashboard-body a[target=_blank]"
    visit "/teacher"
    assert_unchecked_field "dashboard-newtab"
    assert_no_selector "#dashboard-body a[target=_blank]"
    add_finding!
    click_button "Aggiorna"
    assert_selector "li[data-todo=findings]"
    assert_no_selector "#dashboard-body a[target=_blank]", wait: 1
    check "dashboard-newtab"
    assert_selector "#dashboard-body a[target=_blank]"
  end

  test "the dashboard has no inline script and no inline handler" do
    visit "/teacher"
    assert_selector "#dashboard-body"
    assert_equal 0, page.evaluate_script("document.querySelectorAll('script:not([src]):not([nonce])').length")
    assert_equal 0, page.evaluate_script("document.querySelectorAll('#dashboard [onclick], #dashboard [style]').length")
  end
end
