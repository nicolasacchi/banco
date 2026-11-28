module Grading
  module Closed
    # The normalized_text component. The pipeline (A-01): NFC, trim, whitespace
    # collapse, apostrophe and quote unification, trailing punctuation stripped,
    # invisible characters (ZWSP, ZWNJ, ZWJ, word joiner, BOM, soft hyphen) removed,
    # case folded unless the item is case sensitive. The direction of an accent mark is
    # never tested (D-296): grave and acute are made the same mark (NFD, U+0300 to
    # U+0301, NFC) on both sides, so perchè for perché and està for está are correct,
    # whatever the item's accent_policy. Missing accents are NOT folded in the
    # comparison: an accent slip is its own finding, never "correct". The tilde of ñ
    # and the diaeresis of ü are different letters and stay. A mark that makes ANOTHER
    # word (porqué for porque, el/él, Italian e/è: DiacriticPairs) is not a slip but wrong,
    # or the declared error value. A number and a currency or percent sign are one form
    # with or without the space (8€ = 8 €, 20% = 20 %).
    #
    # Findings, in order: exact match of an accepted answer, or one that differs only in
    # the direction of an accent (correct); a declared
    # error value (typical_error with its code); a bit or letter code typed in groups (invalid, spaces_in_code, D-114/D-403); an accent or apostrophe slip whose
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
      # The subject whose letter codes (GHCC) typed in groups are not an attempt (D-403).
      CODE_SUBJECT = "computer_science"
      WORD_FINAL_APOSTROPHE = /(?<=[aeiou])'(?=[[:space:]]|\z)/
      # A number followed by a currency or a percent sign is written with one space, whichever way it was typed: 8€ = 8 €, 20% = 20 % (D-403).
      SIGN_AFTER_NUMBER = /(\d)[[:space:]]?([€$£%])/

      module_function

      def grade(spec, value)
        return Closed.invalid("unparseable") unless value.is_a?(String)
        return binary(spec, value) if spec.profile.is_a?(Hash) && spec.profile["name"] == "binary"

        answer = normalize(value, case_sensitive: spec.case_sensitive)
        return Closed.invalid("empty") if answer.empty?

        entries = ([ spec.answer ] + spec.accept).map(&:to_s)
        accepted = entries.map { |t| normalize(t, case_sensitive: spec.case_sensitive) }
        folded = fold_direction(answer)
        # what an accepted text is called in the answer of the grade commands: the key (the first) or an accept entry
        right = ->(i) { Closed.result("correct", normalized: answer, matched: { kind: i.zero? ? "key" : "accept", value: entries[i] }) }
        if (i = accepted.index(answer) || accepted.index { |c| fold_direction(c) == folded })
          return right.(i)
        end

        contracted = spec.contractions == "en"
        # The key decides which reading of an ambiguous 's/'d is meant ("'s got" is "is got" or "has got"): any reading of the answer that an
        # accepted text has is right, unless that reading is itself a declared error value (Contractions.accepts?).
        # A suffix at the start of the answer ('s, 're) is a fragment only after a word of the frame: «___ Jack coming?» has none (round 10).
        context = contracted ? frame_context(spec) : {}
        if contracted
          errors = spec.error_values.map { |_code, v| normalize(v.to_s, case_sensitive: spec.case_sensitive) }
          i = accepted.index { |t| Contractions.accepts?(t, answer, case_sensitive: spec.case_sensitive, except: errors, **context) }
          return right.(i) if i
        end
        # A declared error value that the answer equals is looked at first (D-403): «por que» for «porque» is its declared error, not a code typed in groups.
        declared = declared_entries(spec, answer, **context)
        if declared.any?
          code, written = declared.first
          return Closed.result("typical_error", error_codes: declared.map(&:first).uniq, normalized: answer, matched: { kind: "error", value: written, code: code })
        end
        return Closed.invalid("spaces_in_code") if spaced_code?(spec, answer, accepted)

        # A diacritic that makes ANOTHER word (porqué for porque, e for è, DiacriticPairs) is no slip: a declared error value has won above, else the answer is wrong.
        other_word = other_word?(spec, answer, accepted)
        if !other_word && (slip = accent_slip(spec, answer, accepted))
          return Closed.result("typical_error", error_codes: [ slip ], normalized: answer, matched: slip_of(spec, answer, accepted, entries, slip))
        end

        if (folded_hits = folded_declared(spec, answer, accepted)).any?
          return Closed.result("typical_error", error_codes: folded_hits, normalized: answer)
        end
        return Closed.result("near_miss", normalized: answer, matched: near_of(spec, answer, accepted, entries)) if !other_word && near_miss?(spec, answer, accepted)

        Closed.result("wrong", normalized: answer)
      end

      # [[code, value as written]] of the declared error values that the answer equals (or, with contractions on, reads as), in the order of the catalogue.
      def declared_entries(spec, answer, **context)
        spec.error_values.select do |_code, v|
          written = normalize(v.to_s, case_sensitive: spec.case_sensitive)
          written == answer || (spec.contractions == "en" && Contractions.accepts?(written, answer, case_sensitive: spec.case_sensitive, **context))
        end
      end

      # What the sentence shown says about the contractions of a gap's filler (Contractions.accepts?): `fragment`, whether the filler may start with a suffix of the table
      # ('s, 're), which it may not when the sentence opens with the gap (a contraction needs a word before it); `after`, the words that follow the gap, which tell a
      # final «'s» whether it is «has» (before a participle) or «is». No sentence shown (no frame): the author's own text decides, as before.
      def frame_context(spec)
        frame = Frame.for_spec(spec)
        frame ? { fragment: frame.prefix.any?, after: frame.suffix.first(2) } : {}
      end

      # The accepted entry an accent slip is of (the one that is the answer without its accents).
      def slip_of(spec, answer, accepted, entries, code)
        unaccented = fold_accents(answer.gsub(WORD_FINAL_APOSTROPHE, ""))
        i = accepted.index { |c| fold_accents(c) == unaccented }
        { kind: "slip", value: i && entries[i], code: code }.compact
      end

      # Is the answer an accepted text with the diacritic of a word that the language's list calls another word (DiacriticPairs)? An apostrophe typed for an
      # accent (e' for è) is the usual way to write the mark and stays a slip.
      def other_word?(spec, answer, accepted)
        return false if answer.gsub(WORD_FINAL_APOSTROPHE, "") != answer

        unaccented = fold_accents(answer)
        same = accepted.select { |c| fold_accents(c) == unaccented }
        same.any? && same.all? { |c| DiacriticPairs.word_changed?(spec.subject, answer, c) }
      end

      def near_of(spec, answer, accepted, entries)
        i = accepted.index { |c| damerau(answer, c) == Diagnosis::Rules::V1::NEAR_MISS_EDIT_DISTANCE && !NearText.inflection_only?(answer, c, spec.subject) }
        i ? { kind: "slip", value: entries[i] } : nil
      end

      # A code made only of bits (001110) typed in groups, or of letters (GHCC) in a code-like item: the content is right, the form is not an
      # attempt, so the student retypes (D-114). The letters count only where a code is meant (D-403): the subject computer_science, or a key in
      # capitals of a case sensitive item; in every other item a one-word key typed with spaces («every day» for «everyday») is graded as any answer.
      def spaced_code?(spec, answer, accepted)
        return false unless answer.match?(/[[:space:]]/)

        joined = answer.gsub(/[[:space:]]+/, "")
        letters = spec.subject == CODE_SUBJECT
        accepted.any? do |c|
          next false unless c == joined && c.length > 1

          c.match?(/\A[01]+\z/) || (c.match?(/\A\p{L}+\z/) && (letters || (spec.case_sensitive && c.match?(/\A\p{Lu}+\z/))))
        end
      end

      def normalize(text, case_sensitive: false)
        s = text.unicode_normalize(:nfc).gsub(INVISIBLE, "")
        s = s.gsub(/[[:space:]]+/, " ").strip.gsub(SIGN_AFTER_NUMBER, '\1 \2')
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

      # Grave and acute made one mark (D-296); every other mark (ñ, ü) is left alone.
      def fold_direction(text)
        text.unicode_normalize(:nfd).tr("\u0300", "\u0301").unicode_normalize(:nfc)
      end

      # Would the grader take +b+ typed for the accepted text +a+? Its own comparison, whichever the order of the tests: the normalisation,
      # then the direction of an accent, then (contractions "en") a reading of what was typed that the accepted text has, except the one
      # that is +b+ itself as a declared error value. Used to see that an accepted text and a declared error value are the same answer (the
      # accept list is tried first, so the error could never fire): an accept entry "'s got" does not swallow the error value "is got".
      def same_answer?(a, b, case_sensitive: false, contractions: nil)
        x = normalize(a.to_s, case_sensitive: case_sensitive)
        y = normalize(b.to_s, case_sensitive: case_sensitive)
        x == y || fold_direction(x) == fold_direction(y) || (contractions == "en" && Contractions.accepts?(x, y, case_sensitive: case_sensitive, except: [ y ]))
      end

      def same_direction_as_any?(answer, accepted)
        folded = fold_direction(answer)
        accepted.any? { |c| fold_direction(c) == folded }
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

        accepted.any? { |c| damerau(answer, c) == Diagnosis::Rules::V1::NEAR_MISS_EDIT_DISTANCE && !NearText.inflection_only?(answer, c, spec.subject) }
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
