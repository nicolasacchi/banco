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
  #
  # Never a typo (round 10, D-408): a word that differs from the candidate's only by an inflection ending of the item's language («want» for
  # «wants», «walk» for «walked», «me encantan» for «me encanta»). The student is not told it is a typo when it is the rule the item teaches:
  # the answer is wrong. English: -s -es -ies -ed -ied -d -ing; Spanish: the person and number endings of the verb (-o -as -a -amos -áis -an …).
  # Another subject (or none) has no list, so nothing changes for it.
  module NearText
    TYPO_MIN_LETTERS = 4
    LONG_WORD_LETTERS = 8
    INFLECTION_MIN_STEM = 3
    ENDINGS = {
      "english" => [ "", "s", "es", "ies", "y", "ed", "ied", "d", "ing" ],
      "spanish" => [ "", "o", "a", "e", "as", "es", "an", "en", "n", "s", "mos", "amos", "emos", "imos", "áis", "éis", "ís", "ais", "eis", "is", "ás", "é", "í", "ó", "ió", "aste", "iste", "aron", "ieron", "ando", "iendo", "ado", "ido" ]
    }.freeze

    module_function

    def kind(answer, candidates, case_sensitive: false, subject: nil)
      mine = words(answer, case_sensitive)
      return nil if mine.empty?

      others = Array(candidates).map { |c| words(c, case_sensitive) }.reject(&:empty?).uniq
      return :typo if others.any? { |c| typo?(mine, c, subject) }
      return :one_word if others.any? { |c| one_word?(mine, c) }

      nil
    end

    def words(text, case_sensitive)
      text.to_s.split(/[[:space:]]+/).map { |t| Frame.key(t, case_sensitive: case_sensitive) }.reject(&:empty?)
    end

    def typo?(mine, other, subject = nil)
      return false unless mine.size == other.size

      pairs = mine.zip(other).reject { |a, b| a == b }
      return false unless pairs.size == 1

      given, wanted = pairs.first
      return false if wanted.length < TYPO_MIN_LETTERS
      return false if inflection?(given, wanted, subject)

      Closed::Text.damerau(given, wanted) <= (wanted.length >= LONG_WORD_LETTERS ? 2 : 1)
    end

    # Do the two words share a stem and differ only by an inflection ending of the language (both tails are endings, or none)?
    def inflection?(given, wanted, subject)
      endings = ENDINGS[subject.to_s] or return false
      stem = given.chars.zip(wanted.chars).take_while { |a, b| a == b }.size
      return false if stem < INFLECTION_MIN_STEM

      tails = [ given[stem..], wanted[stem..] ]
      tails.all? { |t| endings.include?(t) }
    end

    # Is the answer the candidate with only one word's inflection ending changed? (`Closed::Text` near miss, `spelling_policy: near`.)
    def inflection_only?(answer, candidate, subject)
      mine = words(answer, false)
      other = words(candidate, false)
      return false unless mine.size == other.size

      pairs = mine.zip(other).reject { |a, b| a == b }
      pairs.size == 1 && inflection?(*pairs.first, subject)
    end

    # One whole word more or less, in the same order.
    def one_word?(mine, other)
      longer, shorter = mine.size > other.size ? [ mine, other ] : [ other, mine ]
      return false unless longer.size == shorter.size + 1

      longer.each_index.any? { |i| longer[0...i] + longer[(i + 1)..] == shorter }
    end
  end
end
