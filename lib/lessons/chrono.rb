# frozen_string_literal: true

module Lessons
  # Chrono: Years without a year 0, centuries and Roman numerals. A year is an integer string, negative = a.C.; '0' is refused.
  # Built by T4a (WAVE2 1.10, batch w2-1). The JS twin is app/javascript/lesson/lib/chrono.js and both run test/fixtures/lesson2/chrono.json
  # (like Lessons::Num and lesson/num.js). A bad argument (not a whole year, the year 0, a year past 9999) raises ArgumentError.
  #
  # The axis of years: `position(year)` is the year's place on a line that goes from 1 a.C. straight into 1 d.C., so that the difference of
  # two positions is the number of whole years between them (duration(-1, 1) = 1): the drawing and the sum can never disagree.
  module Chrono
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "duration" => "duration(from, to)",
      "century" => "century(year)",
      "roman" => "roman(n)",
      "parse_roman" => "parse_roman(text)",
      "mutants" => "mutants(from, to)"
    }.freeze
    MAX_YEAR = 9999
    ROMAN = [ [ 1000, "M" ], [ 900, "CM" ], [ 500, "D" ], [ 400, "CD" ], [ 100, "C" ], [ 90, "XC" ], [ 50, "L" ], [ 40, "XL" ], [ 10, "X" ],
              [ 9, "IX" ], [ 5, "V" ], [ 4, "IV" ], [ 1, "I" ] ].freeze

    module_function

    # A year as an Integer (never 0); ArgumentError otherwise.
    def year(value)
      text = value.to_s.strip
      raise ArgumentError, "#{value.inspect} is not a whole year" unless text.match?(/\A-?[0-9]{1,4}\z/)

      y = text.to_i
      raise ArgumentError, "there is no year 0" if y.zero?

      y
    end

    # The place of a year on the axis: 1 a.C. is -1 and 1 d.C. is 0, with no place for the year 0.
    def position(value)
      y = year(value)
      y.positive? ? y - 1 : y
    end

    # Whole years from one year to the other, the year 0 not counted: -27 to 14 is 40. Negative when +to+ is before +from+.
    def duration(from, to)
      position(to) - position(from)
    end

    # The Italian label of a year's century: 'II secolo a.C.'.
    def century(year)
      y = year(year)
      n = (y.abs - 1) / 100 + 1
      "#{roman(n)} secolo #{y.negative? ? 'a.C.' : 'd.C.'}"
    end

    # A positive integer below 4000 as a Roman numeral.
    def roman(n)
      raise ArgumentError, "#{n.inspect} is not a whole number from 1 to 3999" unless n.to_s.match?(/\A[0-9]{1,4}\z/) && (1..3999).cover?(n.to_i)

      rest = n.to_i
      ROMAN.each_with_object(+"") do |(value, sign), out|
        while rest >= value
          out << sign
          rest -= value
        end
      end
    end

    # A Roman numeral as an integer, nil when it is not one (only the written form roman gives is one: IIII and IC are not).
    def parse_roman(text)
      s = text.to_s.strip.upcase
      return nil unless s.match?(/\A[IVXLCDM]+\z/)

      sum = 0
      rest = s.dup
      ROMAN.each do |value, sign|
        while rest.start_with?(sign)
          sum += value
          rest = rest.delete_prefix(sign)
        end
      end
      rest.empty? && sum.between?(1, 3999) && roman(sum) == s ? sum : nil
    end

    # The wrong values of duration that a typical error gives (year 0 counted, eras subtracted, same era added), by name. A name is there
    # only when the error gives a different number from the right one for these two years.
    def mutants(from, to)
      a = year(from)
      b = year(to)
      right = duration(a, b)
      all = {}
      if (a.negative? && b.positive?) || (a.positive? && b.negative?)
        all["year_zero_counted"] = b - a                   # the year 0 is counted as a year: 14 - (-27) = 41
        all["eras_subtracted"] = (b.abs - a.abs).abs       # the two numbers are subtracted, the eras forgotten: 27 and 14 give 13
      else
        all["same_era_added"] = a.abs + b.abs              # two years of the same era are added: 133 + 27 = 160
      end
      all.reject { |_, v| v == right }.transform_values(&:to_s)
    end
  end
end
