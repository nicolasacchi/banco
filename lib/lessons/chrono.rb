# frozen_string_literal: true

module Lessons
  # Chrono: Years without a year 0, centuries and Roman numerals. A year is an integer string, negative = a.C.; '0' is refused.
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T4a): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/chrono.js and both run test/fixtures/lesson2/chrono.json (like Lessons::Num and lesson/num.js).
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

    module_function

    # Whole years from one year to the other, the year 0 not counted: -27 to 14 is 40.
    def duration(from, to)
      raise NotBuilt, "Lessons::Chrono.duration is not built yet (T4a, w2-1)"
    end

    # The Italian label of a year's century: 'II secolo a.C.'.
    def century(year)
      raise NotBuilt, "Lessons::Chrono.century is not built yet (T4a, w2-1)"
    end

    # A positive integer below 4000 as a Roman numeral.
    def roman(n)
      raise NotBuilt, "Lessons::Chrono.roman is not built yet (T4a, w2-1)"
    end

    # A Roman numeral as an integer, nil when it is not one.
    def parse_roman(text)
      raise NotBuilt, "Lessons::Chrono.parse_roman is not built yet (T4a, w2-1)"
    end

    # The wrong values of duration that a typical error gives (year 0 counted, eras subtracted, same era added), by name.
    def mutants(from, to)
      raise NotBuilt, "Lessons::Chrono.mutants is not built yet (T4a, w2-1)"
    end
  end
end
