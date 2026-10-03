# frozen_string_literal: true

module Diagnosis
  # A clock that moves only when told to.
  class FakeClock < Clock
    START = Time.utc(2026, 11, 2, 8, 0, 0)

    attr_reader :now

    def initialize(now = START)
      super()
      @now = now
    end

    def advance(seconds)
      @now += seconds
      self
    end

    # Move to hour:00 of a calendar day (stays put when already past it).
    def advance_to(date, hour: 8)
      target = Time.utc(date.year, date.month, date.day, hour, 0, 0)
      @now = target if target > @now
      self
    end

    def date(time) = time.to_date
  end
end
