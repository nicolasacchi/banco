require "test_helper"

# docs/rules/practice-1.md and lib/practice/rules/v1.rb must say the same (the register is the prose,
# the module the numbers).
class PracticeRulesTest < ActiveSupport::TestCase
  DOC = Rails.root.join("docs/rules/practice-1.md").read
  V1 = Practice::Rules::V1

  def documented
    DOC[/## 1\. Constants\n(.*?)\n## 2/m, 1].lines.filter_map do |line|
      m = line.match(/\A\| `([A-Z_]+)` \| (.+?) \|/)
      m && [ m[1], m[2] ]
    end.to_h
  end

  test "every documented constant exists with the documented value, and the reverse" do
    doc = documented
    constants = V1.constants.map(&:to_s)
    assert_equal constants.sort, doc.keys.sort
    doc.each do |name, text|
      value = V1.const_get(name)
      expected = case value
      when Array then value.join(" ")
      else value.to_s
      end
      assert_equal expected, text.delete("`"), name
    end
  end

  test "the version names the rules" do
    assert_equal "practice/1", V1::RULES_VERSION
    assert_equal V1::MAX_WRONG_TRIES + V1::MAX_NEAR_MISS_RETRIES, V1::MAX_TRIES
  end

  test "the states are the seven of the register" do
    assert_equal 7, V1::STATES.size
    assert_equal V1::STATES.sort, I18n.t("states").keys.map(&:to_s).sort
  end

  test "the serve actions of the document are the actions the machine produces" do
    produced = %i[next back prova_questo show_solution retry after_solution].map(&:to_s)
    DOC[/## 3\. Serve state machine.*?## 4/m].scan(/`(next|back|prova_questo|show_solution|retry|after_solution)`/).flatten.uniq.each do |a|
      assert_includes produced, a
    end
  end
end
