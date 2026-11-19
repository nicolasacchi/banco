# frozen_string_literal: true

module Validation
  # W-MATCHING-ROWS and E-MATCHING-ROWS (D-370): a practice matching, a right/wrong judge included, with many rows.
  # The engine already counts a matching as hard to guess from 4 rows (Diagnosis::Rules::V1::LOW_GUESS_MIN_MATCHING_PAIRS);
  # past that the student gets no more evidence from it, only a long list to get through and tries used up (in practice he
  # got 2 of 15 right on matchings of 6 or 7 rows). Above practice.matching_rows_warn the item is warned, above
  # practice.matching_rows_max it is an error, but only for a revision that has not passed before: a revision that passed under
  # older rules and is validated again (an identical resubmission, D-154) keeps its pass, with the warning only.
  module MatchingRows
    module_function

    # Adds at most one finding for the unit: list holds its instances ("display" with the rows under "left").
    def call(unit, list, findings, grandfathered: false)
      return unless unit.component == "matching" && unit.body["kind"] == "practice_item"

      sizes = list.map { |inst| inst["display"].is_a?(Hash) ? Array(inst["display"]["left"]).size : 0 }
      warn_above = Rules.get(:practice, :matching_rows_warn)
      max = Rules.get(:practice, :matching_rows_max)
      top = sizes.max.to_i
      return unless top > warn_above

      over = sizes.count { |n| n > max }
      field = "#{unit.path}/instances"
      if over.positive? && !grandfathered
        findings.add("E-MATCHING-ROWS", field,
                     "#{over} of #{sizes.size} instances have more than #{max} rows (the most: #{top}): a matching of that size is mostly guessing and tries used up for the student; split it into items of #{warn_above} rows or fewer",
                     count: over, rows: top)
      else
        many = sizes.count { |n| n > warn_above }
        note = over.positive? ? " (it passed under older rules, so more than #{max} rows is a warning here)" : ""
        findings.add("W-MATCHING-ROWS", field,
                     "#{many} of #{sizes.size} instances have more than #{warn_above} rows (the most: #{top}): the engine already counts #{warn_above} rows as hard, more only costs tries; keep a matching, a judge included, to #{warn_above} rows#{note}",
                     count: many, rows: top)
      end
    end
  end
end
