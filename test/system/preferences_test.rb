require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# The student's choice of theme and text size reaches the page and the item renderer in a
# real browser, and the vendored Atkinson Hyperlegible is the face that is loaded.
class PreferencesSystemTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  setup do
    @rows = build_ui_subject(components: %w[number choice])
    release_diagnosis!
    sign_in_as :student
  end

  teardown { sign_out_env }

  def style(selector, property) = page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).#{property}")

  test "dark theme and the largest size apply to the list and to the item, and the font is the vendored one" do
    visit "/diagnosis"
    assert_equal "20px", style("html", "fontSize")
    cream = style("body", "backgroundColor")
    choose "Scuro"
    choose "Molto grande"
    click_button "Salva"
    assert_selector "html[data-theme=dark][data-size=larger]"
    assert_equal "28px", style("html", "fontSize")
    assert_not_equal cream, style("body", "backgroundColor")

    # The item is drawn in the same size and colours.
    click_button "Comincia"
    click_button "Comincia"
    assert_selector "[data-sitting-target=itemBox] .item-body .answer"
    assert_equal "28px", style("html", "fontSize")
    assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.instance-stem, .prompt')).fontSize)"), :>=, 28
    assert_equal "rgb(27, 26, 23)", style("body", "backgroundColor")

    families = page.evaluate_script("getComputedStyle(document.body).fontFamily")
    assert_match(/Atkinson Hyperlegible/, families)
    loaded = page.evaluate_async_script("var done = arguments[arguments.length - 1]; document.fonts.ready.then(function () { done(Array.from(document.fonts).filter(function (f) { return f.status === 'loaded' && f.family.indexOf('Atkinson') >= 0; }).length); });")
    assert_operator loaded, :>=, 1
  end
end
