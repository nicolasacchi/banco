# frozen_string_literal: true

module Lessons
  module Diagrams
    # The balance (A7): natural terms and a positive solution. x_value is the weight of a box; it is required
    # exactly when the plates hold different numbers of boxes, and every plate pair must be level at it (the
    # drawing cannot lie). Without a unique solution (same boxes) the balance is level or tilted by the weights
    # alone. tilt is never declared: Balance.tilt computes it (-1 left lighter, 0 level, 1 left heavier).
    module Balance
      module_function

      def boxes(plate) = plate.is_a?(Hash) ? plate["x"].to_i : 0
      def units(plate) = plate.is_a?(Hash) ? plate["units"].to_i : 0

      # sign of (left weight - right weight) at x_value (a Rational, or nil when boxes are equal everywhere)
      def tilt(left, right, x_value)
        weight = ->(plate) { units(plate) + boxes(plate) * (x_value || 0) }
        weight.call(left) <=> weight.call(right)
      end

      def x_value(data) = data["x_value"].nil? ? nil : Diagrams.num(data["x_value"])

      def plates(eff) = [ eff["left"], eff["right"] ]

      def static(data, c)
        pairs = Diagrams.effective_states(data).then { |s| s.empty? ? [ data ] : s }.map { |e| plates(e) }
        differ = pairs.any? { |l, r| boxes(l) != boxes(r) }
        value = x_value(data)
        if data["x_value"]
          if value.nil? || !value.positive?
            c.diagram("/x_value", "a balance cannot draw a zero or negative solution: x_value is a positive number", rule: "x_value-positive")
          elsif !differ
            c.diagram("/x_value", "x_value is omitted exactly when both plates hold the same number of boxes (here they do)", rule: "x_value-omitted")
          end
        elsif differ
          c.diagram("/x_value", "the plates hold different numbers of boxes, so there is a unique solution: x_value is required", rule: "x_value-required")
        end
        try_range(data, value, c)
      end

      def try_range(data, value, c)
        range = data["try"] or return
        from = range["from"]
        to = range["to"]
        if to < from
          c.diagram("/try", "try: from must not be above to", rule: "try-order")
        elsif to - from + 1 > 12
          c.diagram("/try", "try has #{to - from + 1} values (at most 12)", rule: "try-wide")
        elsif value.nil?
          c.diagram("/try", "try needs x_value (there is no solution to find when the plates hold the same number of boxes)", rule: "try-no-solution")
        elsif value.denominator != 1 || !(from..to).cover?(value.numerator)
          c.diagram("/try", "the range must contain the solution #{Lessons::Num.to_s(value)}", rule: "try-solution")
        end
      end

      def state(eff, c, path)
        left, right = plates(eff)
        value = x_value(eff)
        if left.nil? || right.nil?
          c.diagram(path.empty? ? "/left" : path, "the plates are missing: left and right at the top level, or in every state", rule: "plates#{path}")
          return
        end
        if value&.positive? && tilt(left, right, value) != 0
          c.diagram(path.empty? ? "/x_value" : path, "the plates are not level at x_value #{eff['x_value']}: #{describe(left)} against #{describe(right)}; the drawing cannot lie", rule: "level#{path}")
        end
        n = eff["groups"]
        return unless n

        bad = [ left, right ].any? { |p| boxes(p) % n != 0 || units(p) % n != 0 }
        c.diagram("#{path}/groups", "the plates do not divide into #{n} equal groups", rule: "groups#{path}") if bad
      end

      def describe(plate) = [ ("#{boxes(plate)}x" if boxes(plate).positive?), (units(plate).to_s if units(plate).positive? || boxes(plate).zero?) ].compact.join(" + ")
    end
  end
end
