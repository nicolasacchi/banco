module Grading
  module Closed
    # The fraction component: two labelled integer boxes (numerator, denominator),
    # plus a whole-part box for items that declare the form mixed. The value is
    # exact; the declared forms (lowest_terms, improper, mixed) only decide between
    # correct and wrong_form. The violation names the shape that was found, as in
    # config/banco/error_codes.yml: lowest_terms (not reduced), improper (an
    # improper fraction where a mixed number is declared), mixed (the opposite).
    module Fractions
      MINUSES = Numbers::MINUSES
      SPACES = Numbers::SPACES

      module_function

      def grade(spec, value)
        return Closed.invalid("unparseable") unless value.is_a?(Hash)

        answer = read(value)
        expected = expected_parts(spec.answer)
        normalized = display(answer)
        if value_of(answer) == value_of(expected)
          violations = violations(spec.form, answer)
          return Closed.result("correct", normalized: normalized) if violations.empty?

          Closed.result("wrong_form", form_violations: violations, normalized: normalized)
        else
          codes = Closed.error_hit(spec, value_of(answer)) { |v, a| (value_of(expected_parts(v)) == a rescue false) }
          Closed.verdict_for_errors(codes, normalized: normalized)
        end
      rescue Numbers::Invalid => e
        Closed.invalid(e.code)
      end

      # {"n"=>, "d"=>, "w"=>?} of box texts -> {w:, n:, d:} of Integers.
      def read(boxes)
        d = integer(boxes["d"])
        raise Numbers::Invalid, "zero_denominator" if d.zero?
        raise Numbers::Invalid, "negative_denominator" if d.negative?

        w = boxes.key?("w") && !boxes["w"].to_s.strip.empty? ? integer(boxes["w"]) : nil
        n = integer(boxes["n"])
        # In a mixed number the sign belongs to the whole part: "1 -1/2" is not read as 3/2.
        raise Numbers::Invalid, "signed_fraction_part" if w && n.negative?

        { w: w, n: n, d: d }
      end

      def integer(text)
        return text if text.is_a?(Integer)

        s = text.to_s.gsub(MINUSES, "-").gsub(/\A#{SPACES}+|#{SPACES}+\z/, "")
        raise Numbers::Invalid, "empty" if s.empty?
        raise Numbers::Invalid, "ambiguous_mixed_number" if s.match?(/\d#{SPACES}+\d/)
        raise Numbers::Invalid, "unparseable" unless s.match?(/\A[+-]?\d+\z/)

        s.to_i
      end

      def expected_parts(value)
        return { w: value["w"] && Integer(value["w"]), n: Integer(value["n"]), d: Integer(value["d"]) } if value.is_a?(Hash)

        r = Numbers.expected_value(value)
        { w: nil, n: r.numerator, d: r.denominator }
      end

      def value_of(parts)
        fraction = Rational(parts[:n], parts[:d])
        return fraction unless parts[:w]

        sign = parts[:w] <=> 0
        sign.zero? ? fraction : sign * (parts[:w].abs + fraction.abs)
      end

      def violations(forms, parts)
        found = []
        found << "lowest_terms" if forms.include?("lowest_terms") && parts[:n].abs.gcd(parts[:d].abs) != 1
        found << "improper" if forms.include?("mixed") && (parts[:w].nil? || parts[:n].abs >= parts[:d])
        found << "mixed" if forms.include?("improper") && !parts[:w].nil?
        found
      end

      def display(parts)
        base = "#{parts[:n]}/#{parts[:d]}"
        parts[:w] ? "#{parts[:w]} #{base}" : base
      end
    end
  end
end
