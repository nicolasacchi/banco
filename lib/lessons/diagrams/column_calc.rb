# frozen_string_literal: true

module Lessons
  module Diagrams
    # column_calc (WAVE2 2.5, computer_science.md 1.3; T9): an addition, subtraction or multiplication in columns inside a register of
    # `width` digits. The carries, the borrows, the partial products and the result are computed by Lessons::Bits: an agent cannot write a
    # wrong sum. The browser twin is lesson/diagrams/computing/column_calc.js (same checks in the same order).
    module ColumnCalc
      extend Contract

      ALPHABET = Lessons::Bits::ALPHABET
      NEUTRAL_DROPS = %w[read reveal op_it].freeze

      class << self
        def state(eff, c, path)
          found = problems(eff, path)
          c.diagram(found[0], found[1], **found[2]) if found
        end

        def problems(eff, path)
          at = ->(field) { "#{path}/#{field}" }
          fail_ = ->(field, message) { [ at.call(field), message, { rule: "column_calc#{at.call(field)}" } ] }
          base = eff["base"]
          return fail_.call("width", "a register has at most 16 bits, or 10 digits in another base") if eff["width"] > (base == 2 ? 16 : 10)

          %w[a b].each do |key|
            text = eff[key]
            return fail_.call(key, "a digit of #{key} is not a digit of base #{base}") unless text.each_char.all? { |ch| (d = ALPHABET.index(ch)) && d < base }
            return fail_.call(key, "#{key} has more digits than the register (#{eff['width']})") if text.size > eff["width"]
          end
          return fail_.call("b", "the multiplier has at most 4 digits") if eff["op"] == "mul" && eff["b"].size > 4
          return fail_.call("read", "two's complement is for base 2") if eff["read"] == "twos" && base != 2

          nil
        end

        # The work, computed: {a, b, result, ...} as in the JS twin's work().
        def work(eff)
          base = eff["base"]
          width = eff["width"]
          a = BitsView.pad(eff["a"], width)
          b = BitsView.pad(eff["b"], width)
          case eff["op"]
          when "add"
            r = Bits.add(a, b, width, base: base)
            { "op" => "add", "base" => base, "width" => width, "a" => a, "b" => b, "result" => r["digits"], "carries" => r["carries"], "carry_out" => r["carry_out"],
              "extra" => r["carry_out"], "steps" => width }
          when "sub"
            r = Bits.sub(a, b, width, base: base)
            adjusted = a.each_char.with_index.map { |ch, i| ALPHABET.index(ch) - (i + 1 < width ? r["borrows"][i + 1] : 0) + (base * r["borrows"][i]) }
            { "op" => "sub", "base" => base, "width" => width, "a" => a, "b" => b, "result" => r["digits"], "borrows" => r["borrows"], "adjusted" => adjusted,
              "borrow_out" => r["borrows"][0], "extra" => r["borrows"][0], "steps" => width }
          else
            r = Bits.mul(a, eff["b"], width, base: base)
            extra = [ 0, *r["partials"].map { |p| p["digits"].size - width }, r["full"].size - width ].max
            { "op" => "mul", "base" => base, "width" => width, "a" => a, "b" => eff["b"], "result" => r["digits"], "full" => r["full"], "partials" => r["partials"],
              "overflow" => r["overflow"], "extra" => extra, "steps" => r["partials"].size + 1 }
          end
        end

        def served(data, mode: :student)
          out = Lessons::StudentBody.diagram_generic(data) # the declared fields, the states merged, the solution fields out
          return out unless mode == :select

          out = out.except(*NEUTRAL_DROPS)
          out["states"] = out["states"].map { |s| s.except(*NEUTRAL_DROPS) } if out["states"]
          out
        end

        # The stored ids of the select set "digits": a1.., b1.., the partial products p1.1.., then the result r1.., rows from the top.
        def targets(data, set)
          return [] unless set == "digits"

          w = work(Diagrams.effective_states(data).first || data)
          ids = (1..w["width"]).map { |i| "a#{i}" } + (1..w["width"]).map { |i| "b#{i}" }
          w["partials"].each_index { |k| (1..w["width"]).each { |i| ids << "p#{k + 1}.#{i}" } } if w["op"] == "mul"
          ids + (1..w["width"]).map { |i| "r#{i}" }
        end

        # Every value token the state prints (L4); the JS twin returns the same set.
        def printed(data, state = 0)
          eff = Diagrams.effective_states(data)[state] || data
          w = work(eff)
          v = BitsView
          group = w["base"] == 2 ? 4 : 0
          out = []
          [ w["a"], w["b"], v.pad(w["b"], w["width"]), w["result"] ].each { |s| out.concat(v.both_groupings(s, group)) }
          if w["op"] == "mul"
            out << w["full"]
            w["partials"].each { |part| out << part["digits"] }
          end
          if w["op"] == "add"
            w["width"].times do |i|
              sum = ALPHABET.index(w["a"][i]) + ALPHABET.index(w["b"][i]) + (i + 1 < w["width"] ? w["carries"][i + 1] : 0)
              out << sum.to_s
              out << (Bits.write(sum, 2, base: w["base"]) || sum.to_s) if sum >= w["base"] && w["base"] != 10
            end
            w["carries"].each { |c| out << c.to_s if c.positive? }
          end
          if w["op"] == "sub"
            w["width"].times do |i|
              from = ALPHABET.index(w["a"][i]) - (i + 1 < w["width"] ? w["borrows"][i + 1] : 0)
              out << from.to_s
              out << (from + (w["base"] * w["borrows"][i])).to_s
            end
            w["adjusted"].each { |d| out << (ALPHABET[d] || d.to_s) }
          end
          unless (eff["read"] || "none") == "none"
            twos = eff["read"] == "twos"
            [ w["a"], v.pad(w["b"], w["width"]), w["result"] ].each { |digits| out << v.show(Bits.read(digits, base: w["base"], twos: twos)) }
          end
          op = data["states"] && data["states"][state] && data["states"][state]["op_it"]
          out << op if op
          out.uniq
        end

        # The reveal is a stepper over the work, not a value the student sets: no output besides the printed ones.
        def reachable(_data) = []

        def verify_functions = BitsView.verify_functions
      end
    end
  end
end
