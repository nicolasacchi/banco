require "test_helper"
require_relative "../support/decision_world"

class RefsHelperTest < ActionView::TestCase
  include DecisionWorld

  setup { build_decision_world }

  test "a skill key gives its name, its key, a button, and puts the popover at the end of the page" do
    html = ref_for("math.number")
    assert_includes html, 'class="ref-name">Abilità number</span>'
    assert_includes html, '<span class="key">(math.number)</span>'
    assert_match(/popovertarget="refpop-1"/, html)
    assert_includes content_for(:ref_popovers), 'id="refpop-1"'
    assert_includes content_for(:ref_popovers), "popover=\"auto\""
  end

  test "every occurrence has its own id" do
    first = ref_for("math.number")
    second = ref_for("math.number")
    assert_match(/refpop-1/, first)
    assert_match(/refpop-2/, second)
    assert_includes content_for(:ref_popovers), 'id="refpop-2"'
  end

  test "an unknown key is the bare key" do
    html = ref_for("math.nothing")
    assert_equal '<span class="key ref-unknown">math.nothing</span>', html
    assert_nil content_for(:ref_popovers)
  end

  test "the item is named from its skill and its component" do
    rev = @world[:revisions]["fraction"]
    assert_includes ref_for(rev.item), "Domanda su: Abilità fraction (frazione)"
    assert_includes ref_for(rev), "(#{rev.item.key})"
    assert_not_includes ref_for(rev, popover: false), "popovertarget"
  end
end
