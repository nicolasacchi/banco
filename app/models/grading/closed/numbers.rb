module Grading
  module Closed
    # The number component: a numeric field with the Italian decimal comma. The
    # value is an exact Rational, never a Float. A dot is invalid unless the item
    # sets allow_dot (E-03).
    module Numbers
      class Invalid < StandardError
        attr_reader :code

        def initialize(code)
          @code = code
          super(code)
        end
      end

      # Every Unicode space (NBSP, thin, narrow, ideographic ...) is a space; invisible
      # format characters (ZWSP, ZWNJ, ZWJ, word joiner, BOM, soft hyphen) are removed;
      # every minus and plus look-alike (U+2212, U+2010-2015, small and full width,
      # superscript and subscript) is "-" or "+". Anything else that is not a digit,
      # sign, comma or dot stays and the answer is unparseable (invalid), never guessed.
      SPACES = /[[:space:]]/
      INVISIBLE = /[\u00AD\u200B-\u200D\u2060\uFEFF]/
      MINUSES = /[\u2212\u2010-\u2015\uFE63\uFF0D\u207B\u208B]/
      PLUSES = /[\uFE62\uFF0B\u207A\u208A]/
      # Italian thousands grouping: 5.300 or 5.300,50 (a dot every three digits).
      THOUSANDS = /\A[+-]?[1-9]\d{0,2}(?:\.\d{3})+(?:,\d+)?\z/
      # The same with spaces (8 800, 1 600 000): groups of exactly three digits (D-103).
      THOUSANDS_SPACED = /\A[+-]?[1-9]\d{0,2}(?:#{SPACES}\d{3})+(?:,\d+)?\z/
      # A harmless wrapper (D-295): one Latin letter and "=" at the start ("n = -2"), then one pair of
      # parentheses around the whole value ("(-2)"). Either, or both; never repeated, never nested.
      LETTER_PREFIX = /\A[A-Za-z]#{SPACES}*=#{SPACES}*/
      DECIMAL = /\A([+-])?(\d*)(?:([.,])(\d+))?\z/
      # a·10^n, a x 10^n, a×10^n, a*10^n, with ^{n} or a superscript exponent (form "scientific", D-093).
      SCIENTIFIC = /\A(.+?)#{SPACES}*[·⋅×x*]#{SPACES}*10#{SPACES}*\^#{SPACES}*\{?#{SPACES}*([+-]?)#{SPACES}*(\d+)#{SPACES}*\}?\z/i
      SUPERSCRIPTS = "⁰¹²³⁴⁵⁶⁷⁸⁹"
      MAX_EXPONENT = 400

      module_function

      def grade(spec, value)
        return Closed.invalid("unparseable") unless value.is_a?(String)

        members = Equation.members(value)
        members ? written(spec, members) : graded(spec, value)
      rescue Invalid => e
        Closed.invalid(e.code)
      end

      # An answer written in full (D-362, Equation): «x = 7,4», «5+4 = 9», «5+4 = 9 = 9». The last member is graded as if it
      # stood alone, so a wrong value stays wrong (and an unreadable one unreadable). It counts only when the left side is accepted
      # (a letter, the expression shown) or the answer is a chain, and every member before the last equals the key; one that does
      # not makes the answer wrong. A member that is not a number is unreadable. A slash stays unreadable, as in a bare number (D-295).
      def written(spec, members)
        *before, last = members
        left_ok = Equation.left_side?(spec, before.first)
        raise Invalid, "unreadable_number" unless left_ok || before.size > 1

        steps = (left_ok ? before.drop(1) : before).map { |member| read(spec, member).first } # a step that is not a number: unreadable, whatever the last says
        result = graded(spec, last)
        return result unless %w[correct wrong_form].include?(result.verdict)

        steps.all? { |value| key?(spec, value) } ? result : Closed.result("wrong", normalized: result.normalized)
      end

      def graded(spec, value)
        answer, written_scientific = read(spec, value)
        normalized = format(answer)
        if key?(spec, answer)
          if spec.form.include?("scientific") && !scientific_shape?(answer, written_scientific)
            Closed.result("wrong_form", form_violations: [ "scientific_notation" ], normalized: normalized)
          else
            Closed.result("correct", normalized: normalized)
          end
        else
          codes = error_codes(spec, answer)
          Closed.verdict_for_errors(codes, normalized: normalized)
        end
      end

      # [Rational, written_as_a·10^n] of a text, by the item's own rules (the form scientific, the unit, the dot, the thousands).
      def read(spec, text)
        if spec.form.include?("scientific")
          parse_scientific(text, allow_dot: spec.allow_dot, unit: spec.unit, thousands: spec.thousands)
        else
          [ parse(text, allow_dot: spec.allow_dot, unit: spec.unit, thousands: spec.thousands), false ]
        end
      end

      # The key, or a value the item accepts as right.
      def key?(spec, answer) = answer == expected_value(spec.answer) || accepted?(spec.accept, answer)

      # Declared errors that match: exact, or (round_to: n, D-135) any answer that rounds half up
      # to the declared value at n decimals. The key is graded before this, so it always wins.
      def error_codes(spec, answer)
        Array(spec.errors).select { |e| error_match?(e, answer) }.map { |e| e["code"] }.uniq
      end

      def error_match?(error, answer)
        declared = expected_value(error["value"])
        n = error["round_to"]
        n.nil? ? declared == answer : declared.round(n, half: :up) == answer.round(n, half: :up)
      rescue ArgumentError, TypeError, ZeroDivisionError
        false
      end

      # Extra exact values the item accepts as right (a convention the teacher left open).
      def accepted?(accept, answer)
        Array(accept).any? { |v| expected_value(v) == answer rescue false }
      end

      # [Rational, written_as_a·10^n]. Without the notation the text is read as a plain number.
      def parse_scientific(text, allow_dot:, unit:, thousands: false)
        s = strip_unit(clean(text), unit).sub(/10([-+]?[#{SUPERSCRIPTS}]+)\z/) { "10^#{Regexp.last_match(1).tr(SUPERSCRIPTS, '0123456789')}" }
        m = SCIENTIFIC.match(s)
        return [ parse(s, allow_dot: allow_dot, thousands: thousands), false ] unless m

        exponent = m[3].to_i
        raise Invalid, "number_too_large" if exponent > MAX_EXPONENT

        mantissa = parse(m[1], allow_dot: allow_dot, thousands: thousands)
        exponent = -exponent if m[2] == "-"
        [ mantissa * Rational(10)**exponent, mantissa ]
      end

      # The declared form: 1 <= |a| < 10 for a·10^n; a plain number only when it is already in that range.
      def scientific_shape?(value, mantissa)
        mantissa = value if mantissa == false
        mantissa.zero? || (mantissa.abs >= 1 && mantissa.abs < 10)
      end

      # The item's unit at the end of the answer is dropped. The match is exact first, then
      # compatibility-folded on the tail only (NFKC: "cm3" and "cm\u00B3" are the same unit, D-107);
      # the digits before the tail are never folded, so a superscript exponent stays itself.
      def strip_unit(s, unit)
        return s unless unit.present?
        return s.delete_suffix(unit).gsub(/#{SPACES}+\z/, "") if s.end_with?(unit)

        folded = unit.unicode_normalize(:nfkc)
        (1..[ s.length, unit.length + 2 ].min).each do |k|
          next unless s[-k..].unicode_normalize(:nfkc) == folded

          return s[0...-k].gsub(/#{SPACES}+\z/, "")
        end
        s
      end

      # Italian text -> Rational. Raises Invalid(code): empty, use_comma, thousands_separator,
      # ambiguous_mixed_number, unparseable. +thousands+ (the `thousands: true` option of a lesson check, WAVE2 2.11): a dot that
      # groups exactly three digits before the decimal comma is a separator, so 1.115,00 is 1115; spaces still ask for a retype.
      def parse(text, allow_dot: false, unit: nil, thousands: false)
        s = strip_percent(strip_unit(clean(text), unit))
        raise Invalid, "empty" if s.empty?
        s = unwrap(s)
        t = s.sub(/\A([+-])#{SPACES}+/, '\1')
        raise Invalid, "thousands_separator" if t.match?(THOUSANDS_SPACED)
        raise Invalid, "ambiguous_mixed_number" if s.match?(/\d#{SPACES}+[\d,.]/)

        if t.match?(THOUSANDS) && thousands && !allow_dot
          t = t.delete(".")
        elsif t.match?(THOUSANDS) && !allow_dot
          raise Invalid, "thousands_separator"
        end

        m = DECIMAL.match(t)
        raise Invalid, "unreadable_number" if m.nil? || (m[2].empty? && m[4].nil?)
        raise Invalid, "unreadable_number" if m[2].empty? && m[3].nil?
        # A dot that cannot group thousands (0.03125, 5865.2, 12.5) is a decimal comma typed
        # with the wrong key (D-317); 1.250 was refused above as ambiguous and still is.

        sign = m[1] == "-" ? -1 : 1
        integer = m[2].empty? ? "0" : m[2]
        sign * Rational("#{integer}#{".#{m[4]}" if m[4]}")
      end

      # A trailing % or "percento" (with or without a space) is dropped: 45% is 45 (D-317).
      PERCENT = /#{SPACES}*(?:%|per#{SPACES}*cento)\z/i

      def strip_percent(s)
        stripped = s.sub(PERCENT, "")
        stripped.empty? ? s : stripped
      end

      # "n = -2", "(-2)", "n = (-2)" -> "-2". Text that is left empty by the strip is unreadable.
      def unwrap(s)
        s = s.sub(LETTER_PREFIX, "")
        if (m = /\A\((.*)\)\z/m.match(s)) && !m[1].match?(/[()]/)
          s = m[1].gsub(/\A#{SPACES}+|#{SPACES}+\z/, "")
        end
        raise Invalid, "unreadable_number" if s.empty?

        s
      end

      # Unicode look-alikes made plain, invisible characters dropped, edges trimmed.
      def clean(text)
        text.to_s.unicode_normalize(:nfc).gsub(INVISIBLE, "").gsub(MINUSES, "-").gsub(PLUSES, "+").gsub(/\A#{SPACES}+|#{SPACES}+\z/, "")
      end

      # A key value: JSON number, "7/2", "3,5", "3.5", or {"n","d"}.
      def expected_value(value)
        case value
        when Integer then Rational(value)
        when Float then Rational(value.to_s)
        when Hash then Rational(Integer(value["n"]), Integer(value["d"]))
        when String
          s = value.strip.gsub(MINUSES, "-").tr(",", ".")
          Rational(s)
        else raise ArgumentError, "not a number: #{value.inspect}"
        end
      end

      def format(rational)
        rational.denominator == 1 ? rational.numerator.to_s : "#{rational.numerator}/#{rational.denominator}"
      end
    end
  end
end
