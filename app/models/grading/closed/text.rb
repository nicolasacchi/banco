module Grading
  module Closed
    # The normalized_text component. The pipeline (A-01): NFC, trim, whitespace
    # collapse, apostrophe and quote unification, trailing punctuation stripped,
    # invisible characters (ZWSP, ZWNJ, ZWJ, word joiner, BOM, soft hyphen) removed,
    # case folded unless the item is case sensitive. Accents are NOT folded in the
    # comparison: an accent slip is its own finding, never "correct".
    #
    # Findings, in order: exact match of an accepted answer (correct); a declared
    # error value (typical_error with its code); an accent or apostrophe slip whose
    # unaccented form is not itself a paradigm form (typical_error with es_accents,
    # it_accents or it_apostrophe_accent; whether it earns credit is the evidence
    # table's business, X-03); on items with spelling_policy near, an answer of 5+
    # characters one Damerau edit from an accepted answer (near_miss); else wrong.
    # Spelling is exact by default, English included.
    module Text
      APOSTROPHES = /[\u2018\u2019\u201B\u02BC`\u00B4\u2032]/
      QUOTES = /[\u201C\u201D\u201E\u00AB\u00BB\u2033]/
      # Never typed on purpose: zero-width space, non-joiner and joiner, word joiner, BOM, soft hyphen.
      INVISIBLE = /[\u00AD\u200B-\u200D\u2060\uFEFF]/
      # Only the grave and the acute are folded: the tilde of ñ and the diaeresis
      # of ü make different letters.
      FOLDED_MARKS = /[\u0300\u0301]/
      LEADING_RUN_OF_TRAILING = /\A[[:space:].,;:!?\u2026]+/ # applied to the reversed text
      LEADING_PUNCTUATION = /\A[\u00BF\u00A1]+[[:space:]]*/
      WORD_FINAL_APOSTROPHE = /(?<=[aeiou])'(?=[[:space:]]|\z)/

      module_function

      def grade(spec, value)
        return Closed.invalid("unparseable") unless value.is_a?(String)
        return binary(spec, value) if spec.profile.is_a?(Hash) && spec.profile["name"] == "binary"

        answer = normalize(value, case_sensitive: spec.case_sensitive)
        return Closed.invalid("empty") if answer.empty?

        accepted = ([ spec.answer ] + spec.accept).map { |t| normalize(t.to_s, case_sensitive: spec.case_sensitive) }
        return Closed.result("correct", normalized: answer) if accepted.include?(answer)
        return Closed.invalid("spaces_in_code") if spaced_code?(answer, accepted)

        declared = Closed.error_hit(spec, answer) { |v, a| normalize(v.to_s, case_sensitive: spec.case_sensitive) == a }
        return Closed.result("typical_error", error_codes: declared, normalized: answer) if declared.any?

        if (slip = accent_slip(spec, answer, accepted))
          return Closed.result("typical_error", error_codes: [ slip ], normalized: answer)
        end

        if (folded = folded_declared(spec, answer, accepted)).any?
          return Closed.result("typical_error", error_codes: folded, normalized: answer)
        end
        return Closed.result("near_miss", normalized: answer) if near_miss?(spec, answer, accepted)

        Closed.result("wrong", normalized: answer)
      end

      # A code made only of bits or of letters (001110, GHCC) typed in groups: the content is
      # right, the form is not an attempt, so the student retypes (D-114).
      def spaced_code?(answer, accepted)
        return false unless answer.match?(/[[:space:]]/)

        joined = answer.gsub(/[[:space:]]+/, "")
        accepted.any? { |c| c == joined && c.length > 1 && c.match?(/\A(?:[01]+|\p{L}+)\z/) }
      end

      def normalize(text, case_sensitive: false)
        s = text.unicode_normalize(:nfc).gsub(INVISIBLE, "")
        s = s.gsub(/[[:space:]]+/, " ").strip
        s = s.gsub(APOSTROPHES, "'").gsub(QUOTES, '"')
        s = s.sub(LEADING_PUNCTUATION, "")
        s = strip_trailing_punctuation(s)
        case_sensitive ? s : s.downcase
      end

      # One linear pass over the reversed text: a regex retried in a loop was cubic on "a. . . . ..."
      # (20 KB held a worker for about 16 s).
      def strip_trailing_punctuation(text)
        text.reverse.sub(LEADING_RUN_OF_TRAILING, "").reverse.strip
      end

      def fold_accents(text)
        text.unicode_normalize(:nfd).gsub(FOLDED_MARKS, "").unicode_normalize(:nfc)
      end

      # The code of an accent or apostrophe slip, or nil.
      def accent_slip(spec, answer, accepted)
        without_apostrophe = answer.gsub(WORD_FINAL_APOSTROPHE, "")
        apostrophe = without_apostrophe != answer
        unaccented = fold_accents(without_apostrophe)
        return nil unless accepted.any? { |c| fold_accents(c) == unaccented }
        # The bare form is a word of its own (esta / está): a different answer.
        return nil if paradigm?(spec, answer)

        if apostrophe then "it_apostrophe_accent"
        elsif spec.subject == "spanish" then "es_accents"
        else "it_accents"
        end
      end

      # Under accent_policy flag a declared error typed without its accent still hits it
      # (abris for the declared abrís), unless the bare form is a word of its own (paradigm
      # form) or the answer is the key without its accent (accent_slip took that already).
      def folded_declared(spec, answer, accepted)
        return [] unless spec.accent_policy == "flag"
        return [] if paradigm?(spec, answer)

        unaccented = fold_accents(answer)
        return [] if accepted.any? { |c| fold_accents(c) == unaccented }

        Closed.error_hit(spec, unaccented) { |v, a| fold_accents(normalize(v.to_s, case_sensitive: spec.case_sensitive)) == a }
      end

      def paradigm?(spec, answer)
        unaccented = fold_accents(answer)
        spec.paradigm_forms.any? { |f| normalize(f, case_sensitive: spec.case_sensitive) == unaccented }
      end

      def near_miss?(spec, answer, accepted)
        return false unless spec.spelling_policy == "near"
        return false if answer.length < Diagnosis::Rules::V1::NEAR_MISS_MIN_LENGTH

        accepted.any? { |c| damerau(answer, c) == Diagnosis::Rules::V1::NEAR_MISS_EDIT_DISTANCE }
      end

      # Optimal string alignment distance: insertion, deletion, substitution and
      # adjacent transposition each cost one.
      def damerau(a, b)
        a = a.chars
        b = b.chars
        d = Array.new(a.size + 1) { |i| [ i ] + [ 0 ] * b.size }
        (0..b.size).each { |j| d[0][j] = j }
        (1..a.size).each do |i|
          (1..b.size).each do |j|
            cost = a[i - 1] == b[j - 1] ? 0 : 1
            d[i][j] = [ d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost ].min
            d[i][j] = [ d[i][j], d[i - 2][j - 2] + 1 ].min if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]
          end
        end
        d[a.size][b.size]
      end

      # Profile binary(width, leading_zeros required|optional): a string of 0 and 1.
      def binary(spec, value)
        s = value.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
        return Closed.invalid("empty") if s.empty?
        # Bits written in groups ("1110 1100") are one string of bits (D-113).
        s = s.gsub(/(?<=[01])[[:space:]]+(?=[01])/, "")
        unless s.match?(/\A[01]+\z/)
          # A declared error value that is not a bit string (1121, the digit 2 written) is still a
          # typical error, not an unreadable answer (D-116).
          compact = s.gsub(/[[:space:]]+/, "")
          declared = compact.match?(/\A[0-9]+\z/) ? Closed.error_hit(spec, compact) { |v, a| v.to_s.gsub(/[[:space:]]+/, "") == a } : []
          return Closed.result("typical_error", error_codes: declared, normalized: compact) if declared.any?

          return Closed.invalid("unparseable")
        end

        key = spec.answer.to_s
        stripped = s.sub(/\A0+(?=.)/, "")
        unless stripped == key.sub(/\A0+(?=.)/, "")
          # A declared error value is compared without leading zeros too (D-095).
          declared = Closed.error_hit(spec, stripped) { |v, a| v.to_s.sub(/\A0+(?=.)/, "") == a }
          return Closed.result("typical_error", error_codes: declared, normalized: stripped) if declared.any?

          return Closed.result("wrong", normalized: s)
        end

        width = spec.profile["width"]
        if spec.profile["leading_zeros"] == "required" && width && s.length != width
          # A declared error value written exactly so (padding_missing) is a typical error, not a form slip.
          declared = Closed.error_hit(spec, s) { |v, a| v.to_s == a }
          return Closed.result("typical_error", error_codes: declared, normalized: s) if declared.any?

          return Closed.result("wrong_form", form_violations: [ "leading_zeros" ], normalized: s)
        end

        Closed.result("correct", normalized: s)
      end
    end
  end
end
