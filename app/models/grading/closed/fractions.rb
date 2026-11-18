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

        members = Equation.members(value["n"]) if alone_in_the_numerator?(value)
        members&.last&.include?("/") ? written(spec, members) : settle(spec, read(value))
      rescue Numbers::Invalid => e
        Closed.invalid(e.code)
      end

      def settle(spec, answer)
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
      end

      # The whole answer typed in the numerator box (the other boxes empty): «x = 37/5», «1/7+0/7 = 1/7».
      def alone_in_the_numerator?(boxes)
        boxes["n"].is_a?(String) && boxes["d"].to_s.strip.empty? && boxes["w"].to_s.strip.empty?
      end

      # An answer written in full (D-362, Equation): the last member, a fraction a/b, is graded as the boxes would be (the declared
      # forms and errors apply); it counts only when the left side is accepted (a letter, the expression shown) or the answer is
      # a chain, and every member before the last is a fraction equal to the key; one that is not makes the answer wrong.
      def written(spec, members)
        *before, last = members
        left_ok = Equation.left_side?(spec, before.first)
        raise Numbers::Invalid, "unreadable_fraction" unless left_ok || before.size > 1

        steps = (left_ok ? before.drop(1) : before).map { |member| value_of(written_parts(member)) } # a step that is not a fraction: unreadable, whatever the last says
        result = settle(spec, written_parts(last))
        return result unless %w[correct wrong_form].include?(result.verdict)

        expected = value_of(expected_parts(spec.answer))
        steps.all? { |value| value == expected } ? result : Closed.result("wrong", normalized: result.normalized)
      end

      WRITTEN = %r{\A([+-])?#{SPACES}*(\d+)#{SPACES}*/#{SPACES}*(\d+)\z}

      # «37/5», «−3/4», «(37/5)» -> {w:, n:, d:}.
      def written_parts(text)
        m = WRITTEN.match(Numbers.unwrap(Numbers.clean(text)))
        raise Numbers::Invalid, "unreadable_fraction" unless m

        d = m[3].to_i
        raise Numbers::Invalid, "zero_denominator" if d.zero?

        { w: nil, n: m[1] == "-" ? -m[2].to_i : m[2].to_i, d: d }
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

        s = Numbers.clean(text)
        raise Numbers::Invalid, "empty" if s.empty?
        s = Numbers.unwrap(s).sub(/\A([+-])#{SPACES}+/, '\1')
        raise Numbers::Invalid, "ambiguous_mixed_number" if s.match?(/\d#{SPACES}+\d/)
        raise Numbers::Invalid, "unreadable_fraction" unless s.match?(/\A[+-]?\d+\z/)

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
