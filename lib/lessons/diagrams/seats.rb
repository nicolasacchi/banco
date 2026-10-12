# frozen_string_literal: true

module Lessons
  module Diagrams
    # The seats (T6, WAVE2 2.4; law 1.3): a hemicycle or a grid of seats with the quorum and the majorities computed in integers.
    # numero legale floor(seats/2)+1 present; maggioranza dei presenti floor(present/2)+1 (a tie fails); assoluta floor(seats/2)+1;
    # two thirds ceil(2 seats/3); three fifths ceil(3 seats/5). Abstention is left out on purpose: everyone present votes yes or no.
    # `try` declares the ranges of two sliders; the readout of every value inside them is reachable (L5, E-CHECK-ANSWER-BY-SIMULATION).
    # The browser twin is app/javascript/lesson/diagrams/chart/seats.js; both run test/fixtures/lesson2/seats.json.
    module Seats
      extend Contract

      THRESHOLDS = %w[legal_number present_majority absolute_majority two_thirds three_fifths].freeze
      GRID_MAX = 200

      class << self
        # { "name" => { need:, met: } } for the listed thresholds; present and yes may be nil.
        def thresholds(seats, present, yes, list)
          list.to_h do |name|
            need = case name
            when "legal_number", "absolute_majority" then (seats / 2) + 1
            when "present_majority" then present.nil? ? nil : (present / 2) + 1
            when "two_thirds" then (2 * seats + 2) / 3
            when "three_fifths" then (3 * seats + 4) / 5
            end
            have = name == "legal_number" ? present : yes
            [ name, { need: need, met: need && have ? have >= need : nil } ]
          end
        end

        # true / false when the listed thresholds decide the vote, nil when they cannot (nothing listed or a number missing).
        def approved(seats, present, yes, list)
          verdicts = thresholds(seats, present, yes, list).values.map { |v| v[:met] }
          return nil if verdicts.empty? || verdicts.include?(nil)

          verdicts.all?
        end

        def static(data, c)
          cap = data["layout"] == "grid" ? GRID_MAX : Validation::Rules.get(:lesson2, :types, :seats, :seats)
          c.diagram("/seats", "a #{data['layout']} holds at most #{cap} seats", rule: "cap") if data["seats"].to_i > cap
          try = data["try"]
          return unless try

          { "present" => data["seats"].to_i, "yes" => data["seats"].to_i }.each do |key, top|
            range = try[key] or next
            lo, hi = range
            c.diagram("/try/#{key}", "the range of #{key} goes from a smaller to a larger number", rule: "try-order-#{key}") if lo > hi
            c.diagram("/try/#{key}", "the range of #{key} stays within the #{top} seats", rule: "try-top-#{key}") if hi > top
          end
          if try["yes"] && try["present"] && try["yes"][1] > try["present"][0]
            c.diagram("/try", "the largest yes (#{try['yes'][1]}) must not be above the smallest present (#{try['present'][0]}): a vote of more yes than present cannot be drawn", rule: "try-yes-present")
          end
          c.diagram("/try", "yes has a slider only when present is known: give present or its range", rule: "try-yes-needs-present") if try["yes"] && try["present"].nil? && data["present"].nil?
        end

        def state(eff, c, path)
          seats = eff["seats"].to_i
          list = eff["thresholds"].to_a
          c.diagram("#{path}/thresholds", "a threshold is named once", rule: "dup#{path}") if list.uniq.size != list.size
          groups = eff["groups"].to_a
          c.diagram("#{path}/groups", "the groups hold #{groups.sum { |g| g['seats'] }} seats, more than the #{seats} of the house", rule: "groups-sum#{path}") if groups.sum { |g| g["seats"] } > seats
          ids = groups.filter_map { |g| g["id"] }
          c.diagram("#{path}/groups", "two groups have the same id", rule: "groups-id#{path}") if ids.uniq.size != ids.size
          groups.each_with_index do |g, i|
            c.role("#{path}/groups/#{i}/role", g["role"]) if g["role"]
            c.label("#{path}/groups/#{i}/label_it", g["label_it"])
          end
          present = eff["present"]
          yes = eff["yes"]
          c.diagram("#{path}/present", "present is at most the #{seats} seats", rule: "present#{path}") if present && present > seats
          c.diagram("#{path}/yes", "yes needs present (everyone present votes yes or no)", rule: "yes-present#{path}") if yes && present.nil? && eff["try"].nil?
          c.diagram("#{path}/yes", "yes (#{yes}) is more than present (#{present})", rule: "yes-more#{path}") if yes && present && yes > present
          return unless present.nil? && (list.include?("legal_number") || list.include?("present_majority"))

          c.diagram("#{path}/thresholds", "legal_number and present_majority need present", rule: "need-present#{path}") unless eff["try"]&.key?("present")
        end

        def served(data, mode: :student) = Lessons::StudentBody.diagram_generic(data)

        def targets(_data, set) = raise(ArgumentError, "seats has no select sets (#{set.inspect})")

        def effective(data, state)
          eff = Diagrams.effective_states(data)
          eff.empty? ? data : eff.fetch([ state.to_i, eff.size - 1 ].min)
        end

        # The numbers of the state as printed: the house, the groups, present and yes, and "servono N" of each listed threshold.
        def printed(data, state)
          eff = effective(data, state)
          out = [ eff["seats"], eff["present"], eff["yes"] ] + eff["groups"].to_a.map { |g| g["seats"] }
          thresholds(eff["seats"].to_i, eff["present"], eff["yes"], eff["thresholds"].to_a).each_value { |v| out << v[:need] }
          ChartSupport.numbers(out.compact.map(&:to_s))
        end

        # Every number a slider position can print: present, yes, and the "servono" of the thresholds at each position.
        def reachable(data)
          try = data["try"] or return []
          out = []
          ([ data ] + Diagrams.effective_states(data)).each do |eff|
            seats = eff["seats"].to_i
            list = eff["thresholds"].to_a
            presents = try["present"] ? (try["present"][0]..try["present"][1]).to_a : [ eff["present"] ].compact
            yeses = try["yes"] ? (try["yes"][0]..try["yes"][1]).to_a : [ eff["yes"] ].compact
            out.concat(presents) if try["present"]
            out.concat(yeses) if try["yes"]
            presents.each { |p| thresholds(seats, p, nil, list).each_value { |v| out << v[:need] } }
            thresholds(seats, nil, nil, list).each_value { |v| out << v[:need] }
          end
          list = ChartSupport.numbers(out.compact.map(&:to_s))
          list.size > Contract::REACHABLE_CAP ? :over_cap : list
        end
      end
    end
  end
end
