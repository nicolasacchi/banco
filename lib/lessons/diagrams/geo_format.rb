# frozen_string_literal: true

module Lessons
  module Diagrams
    # The numbers and words that map, insolation and cross_section print (T5, W2-1): exact numbers read the way the author wrote them,
    # degrees, years, one-decimal results, lists. Italian, short, with a comma for decimals. The JS twin is lesson/diagrams/maps/geo.js.
    module GeoFormat
      module_function

      # "23,4", "5/3", "3": an exact number as the author reads it; "−" for a minus (as lesson/num.js).
      def fmt(r)
        return r.numerator.to_s.sub("-", "−") if r.denominator == 1

        d = r.denominator
        twos = 0
        fives = 0
        (d /= 2; twos += 1) while (d % 2).zero?
        (d /= 5; fives += 1) while (d % 5).zero?
        return "#{r.numerator.to_s.sub('-', '−')}/#{r.denominator}" unless d == 1

        k = [ twos, fives ].max
        scaled = (r.abs * 10**k).to_i.to_s.rjust(k + 1, "0")
        "#{r.negative? ? '−' : ''}#{scaled[0...-k]},#{scaled[-k..]}"
      end

      # +r+ rounded half away from zero to one decimal, with a comma: "1,2", "26,0". +trim+ drops a final ",0": "26".
      def fmt1(r, trim: false)
        tenths = (r * 10).round(half: :up)
        sign = tenths.negative? ? "−" : ""
        whole, frac = tenths.abs.divmod(10)
        return "#{sign}#{whole}" if trim && frac.zero?

        "#{sign}#{whole},#{frac}"
      end

      # A positive float rounded half up to one decimal, with a comma: 1.25 -> "1,3" (a spread, never a stored value).
      def fmt1f(v)
        tenths = (v * 10 + 0.5).floor
        "#{tenths / 10},#{tenths % 10}"
      end

      def deg(r, positive, negative)
        return "0°" if r.zero?

        "#{fmt(r.abs)}° #{r.positive? ? positive : negative}"
      end

      def lat_word(r) = deg(r, "nord", "sud")

      def lon_word(r) = deg(r, "est", "ovest")

      def year_word(year) = year.to_i.negative? ? "#{-year.to_i} a.C." : "#{year.to_i} d.C."

      def list_it(items) = items.size <= 1 ? items.join : "#{items[0...-1].join(', ')} e #{items.last}"

      def capital(text) = text.to_s.sub(/\A./) { |c| c.upcase }
    end
  end
end
