require "test_helper"

# The small parts of validation: the thresholds, the findings, the answers and the
# canonical form.
class SupportModulesTest < ActiveSupport::TestCase
  test "the thresholds are the ones of the brief, and the file has a version" do
    assert_equal 1, Validation::Rules.version
    assert_equal 24, Validation::Rules.get(:generator, :pool)
    assert_equal 200, Validation::Rules.get(:generator, :seeds)
    assert_equal 20, Validation::Rules.get(:generator, :min_distinct_displays)
    assert_equal 0.2, Validation::Rules.get(:generator, :max_problem_ratio)
    assert_equal 2000, Validation::Rules.get(:generator, :generate_timeout_ms)
    assert_equal 16_384, Validation::Rules.get(:generator, :output_max_bytes)
    assert_equal 50, Validation::Rules.get(:generator, :batch)
    assert_equal 15, Validation::Rules.get(:generator, :batch_timeout_seconds)
    assert_equal 200, Validation::Rules.get(:roundtrip, :random_answers)
    assert_equal 65_536, Validation::Rules.get(:files, :max_file_bytes)
    assert_equal 2_097_152, Validation::Rules.get(:files, :max_total_bytes)
    assert_equal 204_800, Validation::Rules.get(:files, :max_asset_bytes)
    assert_equal [ 25, 60, 3, 4, 2 ], %i[max_sentence_words max_stem_words max_bold_spans max_bold_span_words max_message_sentences].map { |k| Validation::Rules.get(:readability, k) }
    assert_equal [ 6, 2, 3 ], %i[min_instances_per_skill min_items_per_skill min_low_guess_instances].map { |k| Validation::Rules.get(:pool, k) }
  end

  test "with overrides a value for the block only, and the file's tree is untouched" do
    Validation::Rules.with(generator: { pool: 3 }) do
      assert_equal 3, Validation::Rules.get(:generator, :pool)
      assert_equal 200, Validation::Rules.get(:generator, :seeds)
    end
    assert_equal 24, Validation::Rules.get(:generator, :pool)
  end

  test "every subject has a coverage range, and the ranges do not overlap" do
    ranges = Validation::Rules.get(:coverage, :ranges)
    assert_equal Diagnosis::Rules::V1::SUBJECTS.sort, ranges.keys.sort
    sorted = ranges.values.sort
    sorted.each_cons(2) { |a, b| assert_operator a.last, :<, b.first }
  end

  test "findings refuse a code the registry does not know, and merge repeats" do
    f = Validation::Findings.new
    assert_raises(ArgumentError) { f.add("E-NOT-A-CODE", "/x", "m") }
    f.add("E-READ", "/a", "m", rule: "emoji", seed: 3)
    f.add("E-READ", "/a", "m", rule: "emoji", seed: 5)
    f.add("E-READ", "/a", "m", rule: "all_caps")
    f.add("W-ABSOLUTE", "/a", "m")
    assert_equal 3, f.size
    first = f.first
    assert_equal 2, first.detail[:count]
    assert_equal [ 3, 5 ], first.detail[:seeds]
    assert_equal [ "E-READ" ], f.codes
    assert_equal [ "W-ABSOLUTE" ], f.warnings.map(&:code)
    assert f.any_error?
    assert_equal "error", first.severity
  end

  test "decimal strings: finite decimals with the comma, nothing for a repeating one" do
    assert_equal "3,5", Validation::Answers.decimal_string(Rational(7, 2))
    assert_equal "-0,25", Validation::Answers.decimal_string(Rational(-1, 4))
    assert_equal "12", Validation::Answers.decimal_string(Rational(12))
    assert_equal "0,05", Validation::Answers.decimal_string(Rational(1, 20))
    assert_nil Validation::Answers.decimal_string(Rational(1, 3))
  end

  test "raw forms of keys for the grader" do
    assert_equal [ "7", nil ], Validation::Answers.raw_for("number", 7)
    assert_equal [ "3,5", nil ], Validation::Answers.raw_for("number", "3.5")
    assert_nil Validation::Answers.raw_for("number", "1/3").first
    assert_equal({ "n" => "7", "d" => "2" }, Validation::Answers.raw_for("fraction", Rational(7, 2)).first)
    assert_equal({ "w" => "3", "n" => "1", "d" => "2" }, Validation::Answers.raw_for("fraction", Rational(7, 2), form: [ "mixed" ]).first)
    assert_equal [ "o1", nil ], Validation::Answers.raw_for("choice", "o1")
    assert_equal [ [ "a", "b" ], nil ], Validation::Answers.raw_for("ordering", %w[a b])
    assert_equal({ "l1" => "r1" }, Validation::Answers.raw_for("matching", { "l1" => "r1" }).first)
    assert_equal [ "x+1", nil ], Validation::Answers.raw_for("expression", { "latex" => "x+1", "unknown" => "x" })
  end

  test "a key is found as a whole token, not inside a longer number or word" do
    assert Validation::Answers.contains?("il valore e 125 euro", "125")
    assert_not Validation::Answers.contains?("il valore e 1125 euro", "125")
    assert_not Validation::Answers.contains?("il valore e 12,5 euro", "2,5")
    assert Validation::Answers.contains?("vale 3,5 metri", "3,5")
    assert_not Validation::Answers.contains?("la parola capitale", "capi")
    assert_not Validation::Answers.contains?("ab", "ab"), "under 3 characters is never a leak"
    assert Validation::Answers.contains?("x  +  3 = 9", "x+3")
  end

  test "canonical JSON sorts keys, so the fingerprint ignores order" do
    a = { "b" => 1, "a" => [ { "z" => 1, "y" => 2 } ] }
    b = { "a" => [ { "y" => 2, "z" => 1 } ], "b" => 1 }
    assert_equal Validation::Canonical.dump(a), Validation::Canonical.dump(b)
    assert_equal Validation::Canonical.fingerprint(a), Validation::Canonical.fingerprint(b)
    assert_not_equal Validation::Canonical.fingerprint(a), Validation::Canonical.fingerprint(a.merge("b" => 2))
  end
end
