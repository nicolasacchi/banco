require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# D-356: the student switches the language of the interface in Impostazioni, in a real browser. The next pages, and the texts that the
# scripts draw, are in it; <html lang> follows; and Italian is back with one more choice.
class LanguageSystemTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  setup do
    @rows = build_ui_subject(components: %w[number choice])
    release_diagnosis!
    sign_in_as :student
  end

  teardown { sign_out_env }

  test "choosing English in Impostazioni turns the pages and the scripts' texts English, and Italiano brings Italian back" do
    visit "/settings"
    assert_selector "html[lang=it]"
    assert_selector "legend", text: "Lingua dell'app"
    choose "English" # D-354: applies at once; the page is asked for again in the new language
    assert_selector "html[lang=en]"
    assert_selector "h1", text: "Settings"
    assert_selector "legend", text: "App language"
    assert page.find("input[name=language][value=en]", visible: :all).checked?
    assert_equal "en", Diagnosis::Preferences.language(Student.find_by!(key: "student"))

    visit "/today"
    assert_selector "html[lang=en]"
    assert_selector "#topbar-title", text: "Today"

    # a page whose text is drawn by a script
    visit "/diagnosis/warmup"
    assert_text "Task 1 of"
    assert_text "Choose an answer. What is 2 + 2?"

    visit "/settings"
    choose "Italiano"
    assert_selector "html[lang=it]"
    assert_selector "legend", text: "Lingua dell'app"
    visit "/diagnosis/warmup"
    assert_text "Compito 1 di"
    assert_text "Scegli una risposta. Quanto fa 2 + 2?"
  end
end
