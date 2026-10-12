# frozen_string_literal: true

module Lessons
  # Dates: Calendar dates as ISO strings: day counts, due dates and the commercial year fraction.
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-2, track T8): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/dates.js and both run test/fixtures/lesson2/dates.json (like Lessons::Num and lesson/num.js).
  module Dates
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "add_days" => "add_days(date, days, start: :excluded)",
      "diff" => "diff(from, to, convention: :actual)",
      "due" => "due(date, days_after)",
      "year_fraction" => "year_fraction(days, year: 360)"
    }.freeze

    module_function

    # The date after +days+ days; the start day is excluded (the default) or included.
    def add_days(date, days, start: :excluded)
      raise NotBuilt, "Lessons::Dates.add_days is not built yet (T8, w2-2)"
    end

    # Days between two dates, actual or commercial (30/360).
    def diff(from, to, convention: :actual)
      raise NotBuilt, "Lessons::Dates.diff is not built yet (T8, w2-2)"
    end

    # The due date of 'a N giorni data'.
    def due(date, days_after)
      raise NotBuilt, "Lessons::Dates.due is not built yet (T8, w2-2)"
    end

    # days / 360 or days / 365 as an exact fraction.
    def year_fraction(days, year: 360)
      raise NotBuilt, "Lessons::Dates.year_fraction is not built yet (T8, w2-2)"
    end
  end
end
