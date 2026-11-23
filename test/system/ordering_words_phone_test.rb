require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# D-392, in Chrome on a 390 px phone: an ordering exercise with long words («Gerusalemme», «costantinopolitano») draws each word whole on one line,
# never cut in the middle (a broken word reads as two words), and the page does not scroll sideways. A word moves to the next line whole; only a word
# longer than the whole line may break, and none of these is.
class OrderingWordsPhoneTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  TEXTS = [ "Gerusalemme", "costantinopolitano", "Urbano II chiama alla crociata", "I crociati conquistano Gerusalemme" ].freeze
  LONG_WORDS = %w[Gerusalemme costantinopolitano].freeze

  # The ordering of the synthetic subject has numbers; here its rows are the words under test.
  def ui_instance_spec(component, i)
    spec = super
    return spec unless component == "ordering"

    spec[:display] = { elements: TEXTS.each_with_index.map { |text, n| { id: "e#{n + 1}", text: text } } }
    spec
  end

  setup do
    build_ui_subject(components: %w[ordering])
    release_diagnosis!
    sign_in_as :student
    page.driver.resize(390, 844)
  end

  teardown do
    begin
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
  end

  # How many line boxes each word of each row takes: a word on one line has one client rect, a word cut over two lines has two.
  WORD_RECTS = <<~JS.freeze
    (function () {
      var out = [];
      document.querySelectorAll("[data-sitting-target=itemBox] ol.ordering .row-text").forEach(function (box) {
        var walker = document.createTreeWalker(box, NodeFilter.SHOW_TEXT);
        var node;
        while ((node = walker.nextNode())) {
          var re = /\\S+/g, m;
          while ((m = re.exec(node.data))) {
            var range = document.createRange();
            range.setStart(node, m.index);
            range.setEnd(node, m.index + m[0].length);
            out.push({ word: m[0], rects: range.getClientRects().length });
          }
        }
      });
      return out;
    })()
  JS

  test "on a 390 px phone every word of an ordering row is on one line and the page does not scroll sideways" do
    visit "/diagnosis"
    click_button "Comincia"
    assert_text "Test d'ingresso · Matematica"
    click_button "Comincia"
    assert_selector "[data-sitting-target=itemBox] ol.ordering .row-text", count: TEXTS.size
    assert_selector "[data-sitting-target=itemBox] ol.ordering .row-moves", count: TEXTS.size

    words = page.evaluate_script(WORD_RECTS)
    assert_equal TEXTS.join(" ").split.sort, words.map { |w| w["word"] }.sort
    LONG_WORDS.each { |word| assert_includes words.map { |w| w["word"] }, word }
    broken = words.reject { |w| w["rects"] == 1 }.map { |w| w["word"] }
    assert_empty broken, "words cut over two lines: #{broken.join(', ')}"

    width = page.evaluate_script("document.documentElement.scrollWidth")
    assert_operator width, :<=, 390, "the page scrolls sideways (#{width} px)"
  end
end
