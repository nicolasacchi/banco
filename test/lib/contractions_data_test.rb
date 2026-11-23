require "test_helper"

# english/contractions and its second table english/contractions_expected (WAVE2 1.9; T3, D-398). The first follows Speakspeak, the second The Editor's
# Manual; this test compares them and checks the table on its own: every row is well formed, a whole-word row never hides a suffix row, the ambiguous
# ones are only the two that may be a possessive, and a possessive is never expanded.
class ContractionsDataTest < ActiveSupport::TestCase
  Contractions = Grading::Closed::Contractions
  TABLE = Lessons::VettedData.table("english/contractions")
  EXPECTED = Lessons::VettedData.table("english/contractions_expected")
  ROWS = TABLE["contractions"]

  setup { Contractions.reset! }
  teardown { Contractions.reset! }

  test "both tables are written and valid against their schemas, with their sources" do
    assert Lessons::VettedData.valid?("english/contractions"), Lessons::VettedData.errors("english/contractions").first(3).join("; ")
    assert Lessons::VettedData.valid?("english/contractions_expected"), Lessons::VettedData.errors("english/contractions_expected").first(3).join("; ")
    assert_match(/Speakspeak/, TABLE["source"])
    assert_match(/Editor/, EXPECTED["source"])
    assert_not_equal TABLE["source"], EXPECTED["source"], "the second table has its own route"
  end

  test "every row is lower case, its readings are lower case, and no short form is listed twice" do
    shorts = ROWS.map { |r| r["short"] }
    assert_equal shorts.uniq, shorts
    ROWS.each do |r|
      assert_equal r["short"].downcase, r["short"], r["short"]
      r["long"].each { |l| assert_equal l.downcase.strip, l, r["short"] }
      assert_equal r["long"].uniq, r["long"], r["short"]
    end
  end

  test "a short form is a suffix (it starts with an apostrophe or n') or a whole word with an apostrophe or the word cannot" do
    ROWS.each do |r|
      suffix = r["short"].start_with?("'", "n'")
      assert suffix || r["short"].include?("'") || r["short"] == "cannot", r["short"]
    end
  end

  test "only 's and 'd after a noun are ambiguous, and they are never expanded: a possessive stays a possessive" do
    assert_equal [ "'d", "'s" ], ROWS.select { |r| r["ambiguous"] }.map { |r| r["short"] }.sort
    assert_equal %w[would had], ROWS.find { |r| r["short"] == "'d" }["long"]
    assert_equal %w[is has], ROWS.find { |r| r["short"] == "'s" }["long"]
    EXPECTED["kept"].each { |text| assert_equal [ text.downcase ], Contractions.readings(text), text }
  end

  test "every form of the second table reads as that table says, for every reading" do
    EXPECTED["forms"].each do |form, readings|
      assert_equal readings.sort, Contractions.readings(form).sort, form
    end
  end

  test "every whole-word row of the first table is in the second, with the same readings (cannot is the long form of can't, written both ways)" do
    expected = EXPECTED["forms"].transform_keys(&:downcase).transform_values { |v| v.sort }
    whole = ROWS.reject { |r| r["ambiguous"] || r["short"].start_with?("'", "n'") || r["short"] == "cannot" }
    assert_empty whole.map { |r| r["short"] } - expected.keys
    whole.each { |r| assert_equal expected[r["short"]], r["long"].sort, r["short"] }
    assert_equal %w[cannot can\ not], ROWS.find { |r| r["short"] == "cannot" }["long"].sort.reverse
  end

  test "the suffix rows are 'm, 're, 've, 'll and n't, and every regular negative of the page is its verb and not" do
    assert_equal [ "'ll", "'m", "'re", "'ve", "n't" ], ROWS.select { |r| r["short"].start_with?("'", "n'") && !r["ambiguous"] }.map { |r| r["short"] }.sort
    negatives = EXPECTED["forms"].select { |form, _| form.end_with?("n't") && !%w[can't won't shan't].include?(form) }
    assert_operator negatives.size, :>=, 12
    negatives.each { |form, readings| assert_equal [ "#{form.delete_suffix("n't")} not" ], readings, form }
  end

  test "the readings of a long text are bounded, and a text with no contraction reads as itself" do
    assert_equal [ "she goes home" ], Contractions.readings("She goes home")
    many = Contractions.readings("it's he's she's that's there's what's who's here's")
    assert_operator many.size, :<=, Grading::Closed::Contractions::MAX_READINGS
    assert_includes Contractions.readings("it's that's"), "it is that is"
  end
end
