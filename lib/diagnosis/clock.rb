# frozen_string_literal: true

module Diagnosis
  # The only source of "now" and of calendar days for the engine. The engine
  # itself reads times from the log; the clock is used for what has no event
  # yet (abandon gaps, the day a next sitting may start). Tests and simulate
  # use FakeClock.
  class Clock
    def now = Time.now

    # Calendar day of a time in the school's zone (Rome). Plain Ruby times keep
    # their own offset; in Rails the zone applies.
    def date(time)
      time.respond_to?(:in_time_zone) ? time.in_time_zone.to_date : time.to_date
    end
  end
end
