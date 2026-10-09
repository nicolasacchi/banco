# frozen_string_literal: true

module Lessons
  # Exact numbers of banco.diagram/1 (A7): an integer ("-3"), a decimal with comma ("2,5"), a fraction a/b
  # with b > 0 ("-5/2") and, where the caller allows it, "-inf" / "+inf". Everything is a Rational (or
  # +-Float::INFINITY for the two infinities); a check never uses a float. The browser twin is
  # app/javascript/lesson/num.js; both run test/fixtures/lesson2/numbers.json.
  module Num
    INTEGER = /\A-?(?:0|[1-9][0-9]*)\z/
    DECIMAL = /\A(-?)(0|[1-9][0-9]*),([0-9]+)\z/
    FRACTION = /\A(-?(?:0|[1-9][0-9]*))\/([1-9][0-9]*)\z/
    INFINITIES = { "+inf" => Float::INFINITY, "-inf" => -Float::INFINITY }.freeze

    module_function

    # The Rational (or an infinity) of +text+, or nil when the text is not an exact number.
    def parse(text, allow_inf: false)
      return nil unless text.is_a?(String)
      return (allow_inf ? INFINITIES[text] : nil) if INFINITIES.key?(text)

      if text.match?(INTEGER) then Rational(text.to_i, 1)
      elsif (m = text.match(DECIMAL))
        Rational("#{m[1]}#{m[2]}#{m[3]}".to_i, 10**m[3].size)
      elsif (m = text.match(FRACTION)) then Rational(m[1].to_i, m[2].to_i)
      end
    end

    def valid?(text, allow_inf: false) = !parse(text, allow_inf: allow_inf).nil?

    # "n/d" reduced, or "+inf" / "-inf", or nil.
    def canonical(text, allow_inf: false)
      value = parse(text, allow_inf: allow_inf) or return nil
      return (value.positive? ? "+inf" : "-inf") if value.is_a?(Float)

      "#{value.numerator}/#{value.denominator}"
    end

    # -1, 0 or 1; nil when either is not a number.
    def compare(a, b, allow_inf: false)
      x = parse(a, allow_inf: allow_inf)
      y = parse(b, allow_inf: allow_inf)
      x && y ? x <=> y : nil
    end

    # The text of a Rational, the way an author writes it: "3", "-5/2".
    def to_s(value) = value.denominator == 1 ? value.numerator.to_s : "#{value.numerator}/#{value.denominator}"
  end
end
