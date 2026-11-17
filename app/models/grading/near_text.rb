module Grading
  # How near a wrong text answer is to a right one (D-339). Pure and deterministic: no database, no clock, no model.
  # The caller asks only when the answer is wrong and no declared error matched; the candidates are the key and every
  # accepted form.
  #
  #   Grading::NearText.kind("neiborhood", [ "neighborhood" ])   # => :typo
  #   Grading::NearText.kind("Has Tom", [ "Has Tom got" ])        # => :one_word
  #   Grading::NearText.kind("is", [ "are" ])                     # => nil (a grammar error is not near)
  #
  # :typo      the same number of words as a candidate, exactly one word differs, that word has at least TYPO_MIN_LETTERS
  #            letters in the candidate and is one edit away (two from LONG_WORD_LETTERS letters; a transposition is one).
  # :one_word  the answer is a candidate with exactly one whole word missing or one word added; never a substitution.
  module NearText
    TYPO_MIN_LETTERS = 4
    LONG_WORD_LETTERS = 8

    module_function

    def kind(answer, candidates, case_sensitive: false)
      mine = words(answer, case_sensitive)
      return nil if mine.empty?

      others = Array(candidates).map { |c| words(c, case_sensitive) }.reject(&:empty?).uniq
      return :typo if others.any? { |c| typo?(mine, c) }
      return :one_word if others.any? { |c| one_word?(mine, c) }

      nil
    end

    def words(text, case_sensitive)
      text.to_s.split(/[[:space:]]+/).map { |t| Frame.key(t, case_sensitive: case_sensitive) }.reject(&:empty?)
    end

    def typo?(mine, other)
      return false unless mine.size == other.size

      pairs = mine.zip(other).reject { |a, b| a == b }
      return false unless pairs.size == 1

      given, wanted = pairs.first
      return false if wanted.length < TYPO_MIN_LETTERS

      Closed::Text.damerau(given, wanted) <= (wanted.length >= LONG_WORD_LETTERS ? 2 : 1)
    end

    # One whole word more or less, in the same order.
    def one_word?(mine, other)
      longer, shorter = mine.size > other.size ? [ mine, other ] : [ other, mine ]
      return false unless longer.size == shorter.size + 1

      longer.each_index.any? { |i| longer[0...i] + longer[(i + 1)..] == shorter }
    end
  end
end
