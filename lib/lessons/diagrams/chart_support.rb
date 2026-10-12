# frozen_string_literal: true

module Lessons
  module Diagrams
    # What the chart family shares on the Ruby side (T6): exact numbers written the Italian way, and the list of strings a figure prints (L4).
    # The browser twin is app/javascript/lesson/diagrams/chart/format.js; the two run test/fixtures/lesson2/chart_format.json.
    module ChartSupport
      module_function

      # The decimals an exact number needs to be written as a terminating decimal, or 6 when it repeats.
      def places_of(x)
        d = Rational(x).denominator
        twos = fives = 0
        (d /= 2; twos += 1) while (d % 2).zero?
        (d /= 5; fives += 1) while (d % 5).zero?
        d == 1 ? [ twos, fives ].max : 6
      end

      # "21,6", "1598", "-3,25": the number as an author writes it (decimal comma, no thousands dot), half up away from zero at +places+.
      def fmt(x, places = nil)
        x = Rational(x)
        places ||= places_of(x)
        scaled = (x.abs * (10**places)).round(half: :up)
        digits = scaled.to_s.rjust(places + 1, "0")
        text = places.zero? ? digits : "#{digits[0...-places]},#{digits[-places..]}"
        x.negative? && scaled.positive? ? "-#{text}" : text
      end

      # The strings of numbers (author style), without repeats, from the smallest number to the largest.
      def numbers(list)
        list.compact.filter_map { |s| Diagrams.num(s.to_s) }.uniq.sort.map { |x| fmt(x) }
      end

      def months = %w[gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre].freeze
    end
  end
end
