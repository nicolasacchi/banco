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

    # The rows a matching may have before W-MATCHING-ROWS: practice.matching_rows_warn, and for a two-label matching (a judge, right or wrong)
    # practice.matching_two_labels_warn: with 4 rows the split is always 2 + 2, so the split can only vary from 5 rows.
    def warn_limit(display)
      warn_above = Rules.get(:practice, :matching_rows_warn)
      return warn_above unless display.is_a?(Hash) && display["reuse_right"] == true && Array(display["right"]).size == 2

      [ warn_above, Rules.get(:practice, :matching_two_labels_warn) ].max
    end

    # Adds at most one finding for the unit: list holds its instances ("display" with the rows under "left").
    def call(unit, list, findings, grandfathered: false)
      return unless unit.component == "matching" && unit.body["kind"] == "practice_item"

      sizes = list.map { |inst| inst["display"].is_a?(Hash) ? Array(inst["display"]["left"]).size : 0 }
      limits = list.map { |inst| warn_limit(inst["display"]) }
      max = Rules.get(:practice, :matching_rows_max)
      long = sizes.each_index.select { |i| sizes[i] > limits[i] }
      return if long.empty?

      top = sizes.max
      warn_above = limits[long.max_by { |i| sizes[i] }]
      over = sizes.count { |n| n > max }
      field = "#{unit.path}/instances"
      if over.positive? && !grandfathered
        findings.add("E-MATCHING-ROWS", field,
                     "#{over} of #{sizes.size} instances have more than #{max} rows (the most: #{top}): a matching of that size is mostly guessing and tries used up for the student; split it into items of #{warn_above} rows or fewer",
                     count: over, rows: top)
      else
        many = long.size
        note = over.positive? ? " (it passed under older rules, so more than #{max} rows is a warning here)" : ""
        findings.add("W-MATCHING-ROWS", field,
                     "#{many} of #{sizes.size} instances have more than #{warn_above} rows (the most: #{top}): the engine already counts #{warn_above} rows as hard, more only costs tries; keep a matching, a judge included, to #{warn_above} rows#{note}",
                     count: many, rows: top)
      end
    end
  end
end
