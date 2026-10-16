# frozen_string_literal: true

module Validation
  # W-INSTANCES-ALIKE (D-297): two instances of one item that show the student nearly the
  # same thing. The instances of an item are there so a repeat looks like a different
  # question, not the same rows reshuffled. A pair is alike when, after the text grader's
  # normalization, it shares more than pool.alike_share of
  #   matching  the left rows
  #   ordering  the elements
  #   choice    the options, with the same stem
  # (the share is taken of the larger side). The right column of a matching is not counted:
  # classification categories repeat by nature.
  module AlikeInstances
    module_function

    COMPONENTS = %w[choice ordering matching].freeze
    KEYS = { "choice" => "options", "ordering" => "elements", "matching" => "left" }.freeze

    # [[i, j], ...] indexes of the alike pairs among +list+ (instances with a "display").
    def pairs(component, list)
      return [] unless COMPONENTS.include?(component)

      share = Rules.get(:pool, :alike_share)
      rows = list.map { |inst| rows_of(component, inst["display"]) }
      out = []
      rows.each_index do |i|
        (i + 1...rows.size).each do |j|
          a = rows[i]
          b = rows[j]
          next if a[:rows].empty? || b[:rows].empty?
          next unless a[:stem] == b[:stem]

          shared = (a[:rows] & b[:rows]).size
          out << [ i, j ] if shared > share * [ a[:rows].size, b[:rows].size ].max
        end
      end
      out
    end

    def rows_of(component, display)
      d = display.is_a?(Hash) ? display : {}
      stem = component == "choice" ? norm(d["stem_it"]) : nil
      { stem: stem, rows: Array(d[KEYS.fetch(component)]).map { |e| norm(e.is_a?(Hash) ? e["text"] : e) }.reject(&:empty?).uniq }
    end

    def norm(text) = text.is_a?(String) ? Grading::Closed::Text.normalize(text) : ""
  end
end
