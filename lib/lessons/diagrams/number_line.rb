# frozen_string_literal: true

module Lessons
  module Diagrams
    # A number line: exact numbers only (Lessons::Num), marks, intervals and jumps inside [min, max].
    module NumberLine
      module_function

      def static(data, c)
        min = Diagrams.num(data["min"])
        max = Diagrams.num(data["max"])
        step = Diagrams.num(data["step"])
        if min && max && min >= max
          c.diagram("/min", "min must be below max", rule: "min-max")
        elsif min && max && step
          if !step.positive?
            c.diagram("/step", "step must be above 0", rule: "step-positive")
          else
            count = (max - min) / step
            c.diagram("/step", "(max - min) / step must be a whole number of at most 30 steps (here #{Lessons::Num.to_s(count)})", rule: "step-count") if count.denominator != 1 || count > 30
          end
        elsif step && !step.positive?
          c.diagram("/step", "step must be above 0", rule: "step-positive")
        end
      end

      def state(eff, c, path)
        min = Diagrams.num(eff["min"])
        max = Diagrams.num(eff["max"])
        return unless min && max

        inside = ->(v) { v && v >= min && v <= max }
        eff["marks"].to_a.each_with_index do |m, i|
          at = "#{path}/marks/#{i}"
          c.diagram("#{at}/at", "the mark #{m['at']} is outside [#{eff['min']}, #{eff['max']}]", rule: "mark#{at}") unless inside.call(Diagrams.num(m["at"]))
          c.role("#{at}/role", m["role"]) if m["role"]
          c.label("#{at}/label_it", m["label_it"])
        end
        eff["jumps"].to_a.each_with_index do |j, i|
          at = "#{path}/jumps/#{i}"
          from = Diagrams.num(j["from"])
          by = Diagrams.num(j["by"])
          if from && by && !(inside.call(from) && inside.call(from + by))
            c.diagram(at, "the landing #{Lessons::Num.to_s(from + by)} (from #{j['from']}, by #{j['by']}) is outside [#{eff['min']}, #{eff['max']}]", rule: "jump#{at}")
          end
          c.role("#{at}/role", j["role"]) if j["role"]
          c.label("#{at}/label_it", j["label_it"])
        end
        eff["intervals"].to_a.each_with_index do |iv, i|
          at = "#{path}/intervals/#{i}"
          from = Diagrams.num(iv["from"], allow_inf: true)
          to = Diagrams.num(iv["to"], allow_inf: true)
          if from && to && (from > to || (from == to && !(iv["from_closed"] && iv["to_closed"])))
            c.diagram(at, "an interval goes from a smaller to a larger end", rule: "interval#{at}")
          end
          c.role("#{at}/role", iv["role"]) if iv["role"]
          c.label("#{at}/label_it", iv["label_it"])
        end
      end
    end
  end
end
