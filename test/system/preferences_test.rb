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
    visit "/settings"
    assert_equal "20px", style("html", "fontSize")
    cream = style("body", "backgroundColor")
    choose "Scuro"
    choose "Molto grande"
    click_button "Salva"
    assert_selector "#settings-saved"
    assert_selector "html[data-theme=dark][data-size=larger]"
    assert_equal "28px", style("html", "fontSize")
    assert_not_equal cream, style("body", "backgroundColor")

    # The item is drawn in the same size and colours.
    visit "/diagnosis"
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
  # A browser that says it has a mouse (pointer: fine) or, with touch emulation, a finger (pointer: coarse); the headless one has no pointer at all.
  Capybara.register_driver(:ui_pointer) do |app|
    Capybara::Cuprite::Driver.new(app, browser_path: ENV["BROWSER_PATH"], ignore_default_browser_options: true, process_timeout: 60, timeout: 30, pending_connection_errors: false,
                                  window_size: [ 1160, 900 ],
                                  browser_options: CHROME_FLAGS.merge("blink-settings" => "primaryPointerType=4,availablePointerTypes=4,primaryHoverType=2,availableHoverTypes=2"))
  end

  def with_pointer(touch: false, size: [ 1160, 900 ])
    Capybara.current_driver = :ui_pointer
    sign_in_as :student
    page.driver.resize(*size)
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: touch, maxTouchPoints: 1)
  end

  def box(selector) = page.evaluate_script("(() => { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [r.width, r.height] })()")

  def choose_size(label)
    visit "/settings"
    choose label
    click_button "Salva"
    assert_selector "#settings-saved"
  end

  test "the settings offer six sizes, smallest first, and four themes" do
    visit "/settings"
    assert_equal %w[minimum smallest small normal large larger], all("input[name=size]").map(&:value)
    assert_equal %w[cream light dark auto], all("input[name=theme]").map(&:value)
    %w[Minimo Chiaro Automatico].each { |label| assert_selector "label", text: label }
  end

  test "the root size scales a button and a card, not only the text (D-350)" do
    choose_size "Minimo"
    assert_equal "14px", style("html", "fontSize")
    small = { button: box(".button-row .button"), card: box(".preferences .card"), padding: style(".preferences .card", "paddingTop") }
    choose_size "Molto grande"
    assert_equal "28px", style("html", "fontSize")
    large = { button: box(".button-row .button"), card: box(".preferences .card"), padding: style(".preferences .card", "paddingTop") }
    # the root is twice as large, so the button (its height, its padding, its label) is twice as tall and wide; the card is twice as tall
    assert_in_delta 2.0, large[:button][1].to_f / small[:button][1], 0.08, "the button's height follows the root size"
    assert_in_delta 2.0, large[:button][0].to_f / small[:button][0], 0.15, "the button's width follows the root size"
    assert_in_delta 2.0, large[:card][1].to_f / small[:card][1], 0.25, "the card's height follows the root size"
    assert_equal [ "14px", "28px" ], [ small[:padding], large[:padding] ], "the card's padding follows the root size"
  end

  test "Automatico follows the device: cream by day, dark by night, and again when the device changes" do
    visit "/settings"
    choose "Automatico"
    click_button "Salva"
    assert_selector "#settings-saved"
    assert_selector "html[data-theme-choice=auto]"
    emulate_scheme("light")
    assert_selector "html[data-theme=cream]"
    emulate_scheme("dark")
    assert_selector "html[data-theme=dark]"
    assert_equal "rgb(27, 26, 23)", style("body", "backgroundColor")
    visit "/settings"
    assert_selector "html[data-theme=dark][data-theme-choice=auto]"
    assert_selector "input[name=theme][value=auto][checked]"
    emulate_scheme("light")
    assert_selector "html[data-theme=cream]"
  ensure
    emulate_scheme("light")
  end

  test "Chiaro is white and neutral" do
    visit "/settings"
    choose "Chiaro"
    click_button "Salva"
    assert_selector "html[data-theme=light][data-theme-choice=light]"
    assert_equal "rgb(255, 255, 255)", style("body", "backgroundColor")
  end

  test "on a desktop window with a mouse the spacing is tighter; the phone keeps it (D-350)" do
    with_pointer
    visit "/settings"
    assert_equal "0.8rem", page.evaluate_script("getComputedStyle(document.body).getPropertyValue('--space-4').trim()")
    assert_equal "52rem", page.evaluate_script("getComputedStyle(document.body).getPropertyValue('--page-w').trim()")
    page.driver.resize(390, 844)
    assert_equal "1rem", page.evaluate_script("getComputedStyle(document.body).getPropertyValue('--space-4').trim()")
  end

  test "with a finger a button is 44 CSS px high at the smallest size" do
    with_pointer(touch: true, size: [ 390, 844 ])
    choose_size "Minimo"
    assert_equal "14px", style("html", "fontSize")
    assert_operator box(".button-row .button")[1], :>=, 44
    assert_operator box("label.choice")[1], :>=, 44
    visit "/settings"
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: false)
    assert_operator box(".button-row .button")[1], :<, 44, "with a mouse the button follows the size"
  end

  def emulate_scheme(value)
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "prefers-color-scheme", value: value } ])
  end
end
