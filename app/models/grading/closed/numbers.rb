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
      DECIMAL = /\A([+-])?(\d*)(?:([.,])(\d+))?\z/

      module_function

      def grade(spec, value)
        return Closed.invalid("unparseable") unless value.is_a?(String)

        answer = parse(value, allow_dot: spec.allow_dot, unit: spec.unit)
        expected = expected_value(spec.answer)
        normalized = format(answer)
        if answer == expected
          Closed.result("correct", normalized: normalized)
        else
          codes = Closed.error_hit(spec, answer) { |v, a| (expected_value(v) == a rescue false) }
          Closed.verdict_for_errors(codes, normalized: normalized)
        end
      rescue Invalid => e
        Closed.invalid(e.code)
      end

      # Italian text -> Rational. Raises Invalid(code): empty, use_comma,
      # ambiguous_mixed_number, unparseable.
      def parse(text, allow_dot: false, unit: nil)
        s = clean(text)
        s = s.delete_suffix(unit).gsub(/#{SPACES}+\z/, "") if unit.present? && s.end_with?(unit)
        raise Invalid, "empty" if s.empty?
        raise Invalid, "ambiguous_mixed_number" if s.match?(/\d#{SPACES}+[\d,.]/)

        m = DECIMAL.match(s.sub(/\A([+-])#{SPACES}+/, '\1'))
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
