require "test_helper"

# D-314: the limits of D-301. A matching one pair off is not nearly_correct when the right column has only two
# options (a right/wrong judge), nor when the answer gives one right option to every left row.
class NearlyCorrectJudgeTest < ActiveSupport::TestCase
  LEFT = (1..6).map { |i| { "id" => "l#{i}", "text" => "Frase #{i}" } }.freeze
  JUDGE = { "left" => LEFT, "right" => [ { "id" => "ok", "text" => "Giusta" }, { "id" => "no", "text" => "Sbagliata" } ], "reuse_right" => true }.freeze
  THREE = { "left" => LEFT.first(4), "right" => (1..3).map { |i| { "id" => "c#{i}", "text" => "Categoria #{i}" } }, "reuse_right" => true }.freeze

  def spec(answer, display, errors: []) = Grading::Spec.new(component: "matching", subject: "english", answer: answer, errors: errors, display: display)
  def verdict(answer, display, given, **opts) = Grading::Closed.grade(spec(answer, display, **opts), given).verdict
  def rows(labels) = labels.each_with_index.to_h { |r, i| [ "l#{i + 1}", r ] }

  test "a judge with one odd row: the same label for every row is wrong, not nearly correct" do
    key = rows(%w[ok ok ok ok ok no])
    assert_equal "wrong", verdict(key, JUDGE, rows(%w[ok ok ok ok ok ok]))
    assert_equal "correct", verdict(key, JUDGE, key)
  end

  test "a judge is all or nothing even when the answer uses both labels" do
    key = rows(%w[ok ok ok no no no])
    assert_equal "wrong", verdict(key, JUDGE, rows(%w[ok ok ok no no ok])), "5 of 6 with two right options"
    assert_equal "wrong", verdict(key, JUDGE, rows(%w[no ok ok no no no]))
  end

  test "three categories: one label for every row is wrong, one row off with mixed labels stays nearly correct" do
    key = rows(%w[c1 c1 c1 c2])
    assert_equal "wrong", verdict(key, THREE, rows(%w[c1 c1 c1 c1])), "3 of 4, all the same"
    assert_equal "nearly_correct", verdict(key, THREE, rows(%w[c1 c1 c3 c2])), "3 of 4, mixed"
    assert_equal "nearly_correct", verdict(rows(%w[c1 c2 c3 c1]), THREE, rows(%w[c1 c2 c3 c2]))
  end

  test "a one-to-one matching keeps D-301" do
    display = { "left" => LEFT.first(4), "right" => (1..5).map { |i| { "id" => "r#{i}", "text" => "Destra #{i}" } } }
    key = (1..4).to_h { |i| [ "l#{i}", "r#{i}" ] }
    assert_equal "nearly_correct", verdict(key, display, key.merge("l4" => "r5"))
    assert_equal "wrong", verdict(key, display, key.merge("l3" => "r5", "l4" => "r3"))
  end

  test "without a display the right column is the right ids the key names" do
    assert_equal "wrong", verdict(rows(%w[ok ok ok no]), {}, rows(%w[ok ok ok ok]))
    assert_equal "wrong", verdict(rows(%w[ok ok no no]), {}, rows(%w[ok ok no ok]))
    assert_equal "nearly_correct", verdict(rows(%w[c1 c2 c3 c1]), {}, rows(%w[c1 c2 c3 c2]))
  end

  test "a declared error keeps precedence" do
    key = rows(%w[ok ok ok ok ok no])
    all_ok = rows(%w[ok ok ok ok ok ok])
    result = Grading::Closed.grade(spec(key, JUDGE, errors: [ { "code" => "all_right", "value" => all_ok } ]), all_ok)
    assert_equal [ "typical_error", [ "all_right" ] ], [ result.verdict, result.error_codes ]
  end

  test "the shown ids are mapped first: a shuffled judge is judged on the canonical answer" do
    key = rows(%w[ok ok ok ok ok no])
    id_map = { "a" => "ok", "b" => "no" }.merge(LEFT.to_h { |l| [ l["id"], l["id"] ] })
    given = rows(%w[a a a a a a])
    assert_equal "wrong", Grading::Closed.grade(spec(key, JUDGE), given, id_map: id_map).verdict
  end

  test "practice: the same label for every row of a judge is a wrong try" do
    key = rows(%w[ok ok ok ok ok no])
    s = spec(key, JUDGE)
    result = Grading.grade_spec(s, rows(%w[ok ok ok ok ok ok]).to_json)
    evidence_key = Grading::Evidence.key(verdict: result.verdict, spec: s, error_codes: result.error_codes, method: result.grading_method)
    assert_equal :unrecognised, Practice::Outcome.call(evidence_key: evidence_key, aided: false)
  end

  test "lesson checks: a judge one row off is wrong, a mixed classification one row off is right with the note" do
    judge = { "component" => "matching", "reuse_right" => true, "answer" => rows(%w[ok ok ok ok ok no]), "left" => LEFT, "right" => JUDGE["right"] }
    assert Lessons::Checks.closed(judge, rows(%w[ok ok ok ok ok ok]), {}, "english").wrong?
    assert Lessons::Checks.closed(judge, judge["answer"], {}, "english").right?

    three = { "component" => "matching", "reuse_right" => true, "answer" => rows(%w[c1 c1 c1 c2]), "left" => THREE["left"], "right" => THREE["right"] }
    assert Lessons::Checks.closed(three, rows(%w[c1 c1 c1 c1]), {}, "english").wrong?
    ok = Lessons::Checks.closed(three, rows(%w[c1 c1 c3 c2]), {}, "english")
    assert ok.right?
    assert_equal "Giusto, tranne una coppia: «Frase 3» va con «Categoria 1», non con «Categoria 3».", ok.message_it
  end

  test "in a testlet a judge sub item one row off makes the unit wrong" do
    key = rows(%w[ok ok ok ok ok no])
    sub = Grading::Spec.new(component: "matching", subject: "english", answer: key, display: JUDGE)
    testlet = Grading::Spec.new(component: "testlet", subject: "english", skill: "english.x")
    testlet.sub_specs = { "s1" => sub }
    result = Grading.grade_spec(testlet, { "s1" => rows(%w[ok ok ok ok ok ok]) }.to_json)
    assert_equal "wrong", result.verdict
  end
end
