require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/student_session"

# D-218 in Chrome: the info button opens the native popover, Esc closes it, a link in it
# goes to the permalink page, and the page's policy blocks nothing (no inline handler).
class RefsSystemTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession

  setup do
    @world = build_ui_subject(approve: false)
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  test "the info button opens a popover, Esc closes it, the permalink link opens the card" do
    visit "/teacher/subjects/math/test/skills/math.number"
    button = find("h1 .ref-info")
    popover = "##{button['popovertarget']}"
    assert_no_selector popover, visible: :visible
    button.click
    assert_selector popover, visible: :visible
    assert_selector "#{popover} [data-ref-card=skill]", text: "Studiata"
    page.driver.browser.keyboard.type(:Escape)
    assert_no_selector popover, visible: :visible

    # The keyboard works too: Enter on the focused button opens it again.
    page.execute_script("document.querySelector('h1 .ref-info').focus()")
    page.driver.browser.keyboard.type(:Enter)
    assert_selector popover, visible: :visible
    within(popover) { click_link "Apri la scheda" }
    assert_current_path "/teacher/refs/math.number"
    assert_selector "h1", text: "Abilità number"
    assert_selector "[data-ref-card=skill]", text: "Domande nel test"
  end

  test "a popover on the list of all the questions follows its link to the block of the item" do
    visit "/teacher/subjects/math/test/all"
    rev = @world[:revisions]["number"]
    find("article#item-#{rev.id} h3 .ref-info").click
    assert_selector "div[popover]:popover-open a", text: "Pagina della domanda"
    page.driver.browser.keyboard.type(:Escape)
    assert_no_selector "div[popover]:popover-open"
    find("article#item-#{rev.id} h3 .ref-info").click
    click_link "Pagina della domanda"
    assert_current_path "/teacher/items/#{rev.id}"
    assert_selector "h2 .ref[data-ref=item]"
  end

  test "the pages raise no policy violation" do
    page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source:
      "window.__csp = []; document.addEventListener('securitypolicyviolation', e => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI));")
    visit "/teacher/subjects/math/graph"
    find("article.skill[data-skill='math.number'] .ref-info").click
    assert_selector "div[popover]:popover-open"
    assert_equal [], page.evaluate_script("window.__csp")
  end
end
