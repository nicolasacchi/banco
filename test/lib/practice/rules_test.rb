require "test_helper"

# docs/rules/practice-2.md and lib/practice/rules/v2.rb must say the same (the register is the prose,
# the module the numbers).
class PracticeRulesTest < ActiveSupport::TestCase
  DOC = Rails.root.join("docs/rules/practice-2.md").read
  V2 = Practice::Rules::V2

  def documented
    DOC[/## 1\. Constants\n(.*?)\n## 2/m, 1].lines.filter_map do |line|
      m = line.match(/\A\| `([A-Z_]+)` \| (.+?) \|/)
      m && [ m[1], m[2] ]
    end.to_h
  end

  test "every documented constant exists with the documented value, and the reverse" do
    doc = documented
    constants = V2.constants.map(&:to_s)
    assert_equal constants.sort, doc.keys.sort
    doc.each do |name, text|
      value = V2.const_get(name)
      expected = case value
      when Array then value.join(" ")
      else value.to_s
      end
      assert_equal expected, text.delete("`"), name
    end
  end

  test "the version names the rules" do
    assert_equal "practice/2", V2::RULES_VERSION
    assert_equal V2::MAX_WRONG_TRIES + V2::MAX_NEAR_MISS_RETRIES, V2::MAX_TRIES
  end

  test "an exercise left half done is kept two weeks" do
    assert_equal 14 * 24, V2::OPEN_SERVE_HOURS
  end

  test "the document says what v2 changed: superseded serves, the item and advance cases, resume" do
    section3 = DOC[/## 3\. Serve state machine.*?## 4/m]
    assert_match(/superseded/, section3)
    section4 = DOC[/## 4\. Atomicity.*?## 5/m]
    assert_match(/at most one open serve per student, skill and pinned item/, section4)
    section7 = DOC[/## 7\. Serving.*?## 8/m]
    %w[item advance resume].each { |word| assert_match(/`?#{word}`?/, section7, word) }
    assert_match(/open\s+serve touched most recently/, section7)
    assert_match(/In breve/, section7)
  end

  test "the record of version 1 stays and the code has no Rules::V1 of the practice" do
    assert_includes Rails.root.join("docs/rules/practice-1.md").read, "`practice/1`"
    assert_not Practice::Rules.const_defined?(:V1, false)
  end

  test "the states are the seven of the register" do
    assert_equal 7, V2::STATES.size
    assert_equal V2::STATES.sort, I18n.t("states").keys.map(&:to_s).sort
  end

  test "the serve actions of the document are the actions the machine produces" do
    produced = %i[next back prova_questo show_solution retry after_solution].map(&:to_s)
    DOC[/## 3\. Serve state machine.*?## 4/m].scan(/`(next|back|prova_questo|show_solution|retry|after_solution)`/).flatten.uniq.each do |a|
      assert_includes produced, a
    end
  end
end
