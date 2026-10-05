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
      DECIMAL = /\A([+-])?(\d*)(?:([.,])(\d+))?\z/
      # a·10^n, a x 10^n, a×10^n, a*10^n, with ^{n} or a superscript exponent (form "scientific", D-093).
      SCIENTIFIC = /\A(.+?)#{SPACES}*[·⋅×x*]#{SPACES}*10#{SPACES}*\^#{SPACES}*\{?#{SPACES}*([+-]?)#{SPACES}*(\d+)#{SPACES}*\}?\z/i
      SUPERSCRIPTS = "⁰¹²³⁴⁵⁶⁷⁸⁹"
      MAX_EXPONENT = 400

      module_function

      def grade(spec, value)
        return Closed.invalid("unparseable") unless value.is_a?(String)

        scientific = spec.form.include?("scientific")
        answer, written_scientific = scientific ? parse_scientific(value, allow_dot: spec.allow_dot, unit: spec.unit) : [ parse(value, allow_dot: spec.allow_dot, unit: spec.unit), false ]
        expected = expected_value(spec.answer)
        normalized = format(answer)
        if answer == expected || accepted?(spec.accept, answer)
          if scientific && !scientific_shape?(answer, written_scientific)
            Closed.result("wrong_form", form_violations: [ "scientific_notation" ], normalized: normalized)
          else
            Closed.result("correct", normalized: normalized)
          end
        else
          codes = Closed.error_hit(spec, answer) { |v, a| (expected_value(v) == a rescue false) }
          Closed.verdict_for_errors(codes, normalized: normalized)
        end
      rescue Invalid => e
        Closed.invalid(e.code)
      end

      # Extra exact values the item accepts as right (a convention the teacher left open).
      def accepted?(accept, answer)
        Array(accept).any? { |v| expected_value(v) == answer rescue false }
      end

      # [Rational, written_as_a·10^n]. Without the notation the text is read as a plain number.
      def parse_scientific(text, allow_dot:, unit:)
        s = strip_unit(clean(text), unit).sub(/10([-+]?[#{SUPERSCRIPTS}]+)\z/) { "10^#{Regexp.last_match(1).tr(SUPERSCRIPTS, '0123456789')}" }
        m = SCIENTIFIC.match(s)
        return [ parse(s, allow_dot: allow_dot), false ] unless m

        exponent = m[3].to_i
        raise Invalid, "number_too_large" if exponent > MAX_EXPONENT

        mantissa = parse(m[1], allow_dot: allow_dot)
        exponent = -exponent if m[2] == "-"
        [ mantissa * Rational(10)**exponent, mantissa ]
      end

      # The declared form: 1 <= |a| < 10 for a·10^n; a plain number only when it is already in that range.
      def scientific_shape?(value, mantissa)
        mantissa = value if mantissa == false
        mantissa.zero? || (mantissa.abs >= 1 && mantissa.abs < 10)
      end

      def strip_unit(s, unit)
        unit.present? && s.end_with?(unit) ? s.delete_suffix(unit).gsub(/#{SPACES}+\z/, "") : s
      end

      # Italian text -> Rational. Raises Invalid(code): empty, use_comma, thousands_separator,
      # ambiguous_mixed_number, unparseable.
      def parse(text, allow_dot: false, unit: nil)
        s = strip_unit(clean(text), unit)
        raise Invalid, "empty" if s.empty?
        raise Invalid, "ambiguous_mixed_number" if s.match?(/\d#{SPACES}+[\d,.]/)

        t = s.sub(/\A([+-])#{SPACES}+/, '\1')
        raise Invalid, "thousands_separator" if !allow_dot && t.match?(THOUSANDS)

        m = DECIMAL.match(t)
        raise Invalid, "unparseable" if m.nil? || (m[2].empty? && m[4].nil?)
        raise Invalid, "unparseable" if m[2].empty? && m[3].nil?
        raise Invalid, "use_comma" if m[3] == "." && !allow_dot

        sign = m[1] == "-" ? -1 : 1
        integer = m[2].empty? ? "0" : m[2]
        sign * Rational("#{integer}#{".#{m[4]}" if m[4]}")
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
