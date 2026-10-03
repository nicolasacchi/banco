# frozen_string_literal: true

module Diagnosis
  # Counted time (B-05): per served item, min(answered - served - paused - hidden,
  # cap), with cap 600 s (1200 s for a testlet). Pure arithmetic on times.
  module TimeAccount
    module_function

    # intervals: [[from, to_or_nil], ...] (nil = still open at +stop+). Returns the
    # seconds of the union of the intervals inside [start, stop].
    def overlap_seconds(intervals, start, stop)
      clipped = intervals.filter_map do |from, to|
        a = [ from, start ].max
        b = [ to || stop, stop ].min
        [ a, b ] if b > a
      end
      total = 0.0
      current_from = nil
      current_to = nil
      clipped.sort_by(&:first).each do |a, b|
        if current_to && a <= current_to
          current_to = [ current_to, b ].max
        else
          total += current_to - current_from if current_to
          current_from = a
          current_to = b
        end
      end
      total += current_to - current_from if current_to
      total
    end

    # Counted seconds of one item. stop is the time the answer (or the abandon)
    # was recorded; excluded are the pause and hidden intervals.
    def counted_seconds(start, stop, excluded, testlet: false)
      cap = testlet ? Rules::V1::TESTLET_CAP_SECONDS : Rules::V1::ITEM_CAP_SECONDS
      raw = (stop - start) - overlap_seconds(excluded, start, stop)
      raw.clamp(0, cap).round
    end
  end
end
