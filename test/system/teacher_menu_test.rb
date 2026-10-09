require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/student_session"

# D-243: the Materie panel opens with Enter, closes with Esc and gives the focus back; no hover; CSP clean.
class TeacherMenuSystemTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession

  setup do
    @world = build_ui_subject(approve: false)
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  test "Enter opens the panel, Esc closes it and the focus goes back to the button" do
    visit "/teacher/subjects/#{@world[:subject].key}/test"
    page.execute_script("window.__violations = []; document.addEventListener('securitypolicyviolation', (e) => window.__violations.push(e.violatedDirective))")
    assert_selector "#menu-subjects-panel", visible: :hidden
    button = find("#menu-subjects")
    page.execute_script("document.getElementById('menu-subjects').focus()")
    page.driver.browser.keyboard.type(:enter)
    assert_selector "#menu-subjects-panel", visible: :visible
    assert_equal "true", button[:"aria-expanded"]
    page.driver.browser.keyboard.type(:escape)
    assert_selector "#menu-subjects-panel", visible: :hidden
    assert_equal "false", button[:"aria-expanded"]
    assert_equal "menu-subjects", page.evaluate_script("document.activeElement.id")
    button.click
    assert_selector "#menu-subjects-panel", visible: :visible
    find("h1").click
    assert_selector "#menu-subjects-panel", visible: :hidden
    assert_empty page.evaluate_script("window.__violations")
  end
end
