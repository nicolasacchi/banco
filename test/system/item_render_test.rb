require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# X-02: every component is drawn by our templates on the app origin, and the page
# cannot reach another origin (the policy blocks it and says so).
class ItemRenderTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  setup do
    @rows = build_ui_subject
    release_diagnosis!
    sign_in_as :student
  end

  teardown { sign_out_env }

  def start_sitting
    visit "/diagnosis"
    click_button "Comincia"
    assert_text "Test d'ingresso · Matematica"
    click_button "Comincia"
    assert_selector "[data-sitting-target=heading]", text: /Matematica · Domanda 1/
  end

  def give_up
    n = page.find("[data-sitting-target=heading]").text[/Domanda (\d+)/, 1].to_i
    click_button "Non lo so"
    n
  end

  def wait_for_question(number)
    assert_selector "[data-sitting-target=heading]", text: /Domanda #{number}\z/
  end

  test "an external fetch from the page is refused and fires securitypolicyviolation" do
    start_sitting
    result = page.evaluate_async_script(<<~JS)
      var done = arguments[arguments.length - 1];
      var violations = [];
      document.addEventListener("securitypolicyviolation", function (e) { violations.push(e.violatedDirective + " " + e.blockedURI); });
      fetch("https://example.com/", { mode: "no-cors" }).then(
        function () { done({ rejected: false, violations: violations }); },
        function () { setTimeout(function () { done({ rejected: true, violations: violations }); }, 300); });
    JS
    assert result["rejected"], "the external fetch should have failed"
    assert(result["violations"].any? { |v| v.start_with?("connect-src") && v.include?("example.com") }, "no securitypolicyviolation: #{result}")
  end

  test "each component has its template, the formulas are rendered and nothing leaves the origin" do
    start_sitting
    seen = []
    number = 1
    COMPONENTS.size.times do
      wait_for_question(number)
      assert_selector "[data-sitting-target=itemBox] .item-body .answer"
      component = detect_component
      seen << component
      check_matching_exclusion if component == "matching"
      number = give_up + 1
      break if component == "short_answer"
    end
    assert_equal %w[number fraction choice ordering matching normalized_text expression testlet short_answer], seen
    outside = requested_urls.reject { |u| u.start_with?(origin) || u.start_with?("data:") || u.start_with?("about:") }
    assert_empty outside, "requests outside the app origin"
  end

  # D-086: an entry chosen in one select is disabled in the others, and free again once cleared.
  def check_matching_exclusion
    selects = page.all(".match-row select")
    assert_operator selects.size, :>=, 2
    value = selects[0].all("option").map { |o| o[:value] }.find { |v| v != "" }
    selects[0].find("option[value='#{value}']").select_option
    assert selects[1].find("option[value='#{value}']", visible: :all).disabled?
    refute selects[0].find("option[value='#{value}']").disabled?
    selects[0].find("option[value='']").select_option
    refute selects[1].find("option[value='#{value}']").disabled?
  end

  # Names the template on screen by what it draws.
  def detect_component
    page.evaluate_script(<<~JS)
      (function () {
        var box = document.querySelector("[data-sitting-target=itemBox]");
        if (box.querySelector(".testlet")) return "testlet";
        if (box.querySelector("math-field")) return "expression";
        if (box.querySelector("textarea")) return "short_answer";
        if (box.querySelector("fieldset.options")) return "choice";
        if (box.querySelector("ol.ordering")) return "ordering";
        if (box.querySelector(".match-row")) return "matching";
        if (box.querySelector(".fraction")) return "fraction";
        if (box.querySelector("input[type=text][lang]")) return "normalized_text";
        if (box.querySelector("input[inputmode=decimal]")) return "number";
        return "unknown";
      })()
    JS
  end
end
