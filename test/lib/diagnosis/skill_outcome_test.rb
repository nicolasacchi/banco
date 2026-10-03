require "test_helper"

# B-02: the per-skill rule, checked exhaustively on sequences of up to three
# evidences against an oracle written from the prose of docs/rules/diagnosis-1.md
# (section 3), not from the code.
class SkillOutcomeTest < ActiveSupport::TestCase
  Outcome = Diagnosis::SkillOutcome::Outcome

  LETTERS = %i[C W D].freeze
  # Evidence that does not count: it never reaches SkillOutcome, the fold drops it.
  NOT_COUNTED = %i[pending ungraded].freeze

  def outcome(letter, low_guess: true, choice: false)
    Outcome.new(evidence: letter, low_guess: low_guess, choice: choice, code: nil, serve: 1)
  end

  # Oracle. seq: [[letter, low_guess, choice], ...] already without pending.
  def oracle(seq)
    return nil if seq.empty?
    return [ "to_recover", "dont_know" ] if seq[0][0] == :D
    return nil if seq.size < 2

    a = seq[0][0]
    b = seq[1][0] == :D ? :W : seq[1][0]
    return [ "demonstrated", seq[0][2] && seq[1][2] ? "two_of_two_choice" : "two_of_two" ] if a == :C && b == :C
    return [ "to_recover", "two_wrong" ] if a == :W && b == :W
    return nil if seq.size < 3

    c = seq[2][0]
    low_credit = seq.first(3).any? { |l, lg, _| l == :C && lg }
    c == :C && low_credit ? [ "demonstrated", "two_of_three" ] : [ "to_recover", "mixed" ]
  end

  def each_sequence(max)
    flags = [ [ true, false ], [ false, false ], [ true, true ] ] # low_guess, choice
    (0..max).each do |n|
      LETTERS.repeated_permutation(n).each do |letters|
        flags.repeated_permutation(n).each { |fl| yield letters.zip(fl) }
      end
    end
  end

  test "exhaustive table: every sequence of up to three evidences, with low-guess and choice flags" do
    count = 0
    each_sequence(3) do |pairs|
      seq = pairs.map { |l, (lg, ch)| [ l, lg, ch ] }
      # Play it through record(): stops counting at resolution.
      so = Diagnosis::SkillOutcome.new("math.a")
      prefix = []
      seq.each do |l, lg, ch|
        so.record(outcome(l, low_guess: lg, choice: ch))
        prefix << [ l, lg, ch ]
        break if so.resolved?
      end
      expected = nil
      (1..prefix.size).each { |k| expected ||= oracle(prefix.first(k)) }
      actual = so.state ? [ so.state, so.reason ] : nil
      if expected
        assert_equal expected, actual, "sequence #{seq.inspect}"
      else
        assert_nil actual, "sequence #{seq.inspect}"
      end
      count += 1
    end
    assert_operator count, :>, 500
  end

  test "pending and ungraded are not outcomes: Rules::V1 keeps them out of the evidence letters" do
    NOT_COUNTED.each { |e| assert_includes %i[pending ungraded], e }
    assert_equal :pending, Diagnosis::Rules::V1.evidence("undetermined")
    assert_equal :ungraded, Diagnosis::Rules::V1.evidence("ungraded")
  end

  test "D on item 1 is dont_know, a later D counts as W" do
    so = Diagnosis::SkillOutcome.new("math.a")
    assert so.record(outcome(:D))
    assert_equal %w[to_recover dont_know], [ so.state, so.reason ]

    later = Diagnosis::SkillOutcome.new("math.a")
    later.record(outcome(:C))
    later.record(outcome(:D))
    assert_equal :third, later.need
    later.record(outcome(:W))
    assert_equal "mixed", later.reason

    pair = Diagnosis::SkillOutcome.new("math.a")
    pair.record(outcome(:W))
    pair.record(outcome(:D))
    assert_equal "two_wrong", pair.reason
  end

  test "two_of_three needs a low-guess credit among the three" do
    so = Diagnosis::SkillOutcome.new("math.a")
    so.record(outcome(:C, low_guess: false))
    so.record(outcome(:W, low_guess: false))
    so.record(outcome(:C, low_guess: false))
    assert_equal %w[to_recover mixed], [ so.state, so.reason ]
  end

  test "need follows the number of counted outcomes" do
    so = Diagnosis::SkillOutcome.new("math.a")
    assert_equal :first, so.need
    so.record(outcome(:C))
    assert_equal :second, so.need
    so.record(outcome(:W))
    assert_equal :third, so.need
  end

  test "a resolved skill ignores later outcomes" do
    so = Diagnosis::SkillOutcome.new("math.a")
    so.record(outcome(:C))
    so.record(outcome(:C))
    so.record(outcome(:W))
    assert_equal %w[demonstrated two_of_two], [ so.state, so.reason ]
    assert_equal 2, so.outcomes.size
  end

  test "unclassified: a W without a catalogue code, or a D" do
    so = Diagnosis::SkillOutcome.new("math.a")
    so.record(Outcome.new(evidence: :W, low_guess: true, choice: false, code: "sign", serve: 1))
    so.record(Outcome.new(evidence: :W, low_guess: true, choice: false, code: "sign", serve: 2))
    refute so.unclassified?(%w[sign])
    assert so.unclassified?(%w[other])
    assert_equal %w[sign sign], so.error_codes
  end
end
