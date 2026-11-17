require "test_helper"

# docs/rules/practice-5.md and lib/practice/rules/v5.rb must say the same (the register is the prose,
# the module the numbers).
class PracticeRulesTest < ActiveSupport::TestCase
  DOC = Rails.root.join("docs/rules/practice-5.md").read
  V5 = Practice::Rules::V5

  def documented
    DOC[/## 1\. Constants\n(.*?)\n## 2/m, 1].lines.filter_map do |line|
      m = line.match(/\A\| `([A-Z_]+)` \| (.+?) \|/)
      m && [ m[1], m[2] ]
    end.to_h
  end

  test "every documented constant exists with the documented value, and the reverse" do
    doc = documented
    constants = V5.constants.map(&:to_s)
    assert_equal constants.sort, doc.keys.sort
    doc.each do |name, text|
      value = V5.const_get(name)
      expected = case value
      when Array then value.join(" ")
      else value.to_s
      end
      assert_equal expected, text.delete("`"), name
    end
  end

  test "the version names the rules" do
    assert_equal "practice/5", V5::RULES_VERSION
    assert_equal V5::MAX_WRONG_TRIES + V5::MAX_NEAR_MISS_RETRIES, V5::MAX_TRIES
  end

  test "an exercise left half done is kept two weeks" do
    assert_equal 14 * 24, V5::OPEN_SERVE_HOURS
  end

  test "the document keeps what version 2 changed: superseded serves, the item and advance cases, resume" do
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
    assert_equal 7, V5::STATES.size
    assert_equal V5::STATES.sort, I18n.t("states").keys.map(&:to_s).sort
  end

  test "the serve actions of the document are the actions the machine produces" do
    produced = %i[next back prova_questo show_solution retry after_solution contest].map(&:to_s)
    DOC[/## 3\. Serve state machine.*?## 4/m].scan(/`(next|back|prova_questo|show_solution|retry|after_solution|contest)`/).flatten.uniq.each do |a|
      assert_includes produced, a
    end
    assert_includes DOC[/## 3\. Serve state machine.*?## 4/m], "`contest`"
  end

  test "the document of version 3 says what it changed: near, contested, the contest rows, the loader's rule, an In breve line" do
    outcomes = DOC[/## 2\. Outcome of one graded try.*?## 3/m]
    assert_match(/`wrong`, near `typo`.*`near_miss`/, outcomes)
    assert_match(/`wrong`, near `one_word`.*`near_miss`/, outcomes)
    assert_match(/`contested`/, outcomes)
    assert_match(/Grading::NearText\.kind/, outcomes)
    assert_match(/`PracticeContest`/, outcomes)
    assert_match(/`normalized_text`/, outcomes)
    assert_match(/In breve: .*(ci sei quasi|manca poco)/m, outcomes)
    section3 = DOC[/## 3\. Serve state machine.*?## 4/m]
    assert_match(/^\| 16 \|.*contest.*closed `contested`/, section3)
    assert_match(/^\| 17 \|.*closed `wrong`.*contest/, section3)
    assert_match(/Fai controllare/, section3)
    assert_match(/not_contestable/, section3)
  end

  test "version 5 says what it changed: no seen exercise on its own, the row, the chosen redo, the line for the same item" do
    section7 = DOC[/## 7\. Serving.*?## 8/m]
    assert_match(/No unseen instance left in the skill/, section7)
    assert_match(/`PracticePoolExhaustion`/, section7)
    assert_match(/`exhausted`/, section7)
    assert_match(/Hai visto tutti gli\s+esercizi di questa abilità\. Ne stiamo preparando altri\./, section7)
    assert_match(/Ti propongo un esercizio simile: per passare al\s+prossimo ne servono 2 giusti\./, section7)
    assert_equal 2, V5::ADVANCE_AFTER_CORRECT_UNAIDED
    assert_includes Rails.root.join("docs/rules/practice-4.md").read, "`practice/4`"
    assert_not Practice::Rules.const_defined?(:V4, false)
  end

  test "the record of version 2 stays" do
    assert_includes Rails.root.join("docs/rules/practice-2.md").read, "`practice/2`"
    assert_not Practice::Rules.const_defined?(:V2, false)
  end
end
