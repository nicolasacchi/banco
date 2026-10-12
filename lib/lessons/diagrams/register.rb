# frozen_string_literal: true

module Lessons
  module Diagrams
    # register (WAVE2 2.5, computer_science.md 1.3; T9): one type for the n-bit value space, two views, row (a register of digits with weights
    # and a readout) and ring (every code of 3 or 4 bits on a circle). Nothing here is hidden from S and nothing is the author's to compute:
    # weights, readouts, group digits and landings are ours (Lessons::Bits). The browser twin is lesson/diagrams/computing/register.js; the
    # semantic checks run in the same order, so both give the same first finding for the vectors of test/fixtures/diagrams/types/register.json.
    module Register
      extend Contract

      ROW_ONLY = %w[value weights groups group_digits toggle goals mark].freeze
      RING_ONLY = %w[cliff pointer step highlight moves].freeze
      NEUTRAL_DROPS = %w[mark highlight moves goals read pointer step cliff op_it].freeze
      HOME = "computer_science"

      class << self
        def state(eff, c, path)
          found = problems(eff, path)
          c.diagram(found[0], found[1], **found[2]) if found
          (eff["mark"] || []).each_with_index { |m, i| c.role("#{path}/mark/#{i}/role", m["role"]) }
          (eff["moves"] || []).each_with_index { |m, i| c.role("#{path}/moves/#{i}/role", m["role"]) if m["role"] }
        end

        # [path, message, rule:] of the first problem of one effective state, or nil.
        def problems(eff, path)
          at = ->(field) { "#{path}/#{field}" }
          fail_ = ->(field, message) { [ at.call(field), message, { rule: "register#{at.call(field)}" } ] }
          base = eff["base"] || 2
          n = eff["width"]
          if eff["view"] == "row"
            RING_ONLY.each { |k| return fail_.call(k, "#{k} is for the ring view") unless eff[k].nil? }
            return fail_.call("width", "a register has at most 16 bits, or 10 digits in another base") if n > (base == 2 ? 16 : 10)
            return fail_.call("value", "a row needs its value") if eff["value"].nil?
            return fail_.call("value", "the value has #{eff['value'].size} digits, the register #{n}") if eff["value"].size != n
            return fail_.call("value", "a digit of the value is not a digit of base #{base}") unless digits?(eff["value"], base)
            return fail_.call("read", "read: both is for the ring") if eff["read"] == "both"
            return fail_.call("read", "two's complement is for base 2") if eff["read"] == "twos" && base != 2
            return fail_.call("group_digits", "group_digits needs groups") if eff["group_digits"] && eff["groups"].to_i.zero?
            return fail_.call("group_digits", "group_digits is for base 2") if eff["group_digits"] && base != 2
            return fail_.call("toggle", "only the bits of a base 2 register can be toggled") if eff["toggle"] && base != 2
            return fail_.call("goals", "goals need toggle: true") if !eff["goals"].nil? && !eff["toggle"]

            read = eff["read"] || "none"
            (eff["goals"] || []).each_with_index do |g, i|
              return fail_.call("goals/#{i}", "goals need a readout") if read == "none"
              return fail_.call("goals/#{i}", "#{g} cannot be written in #{n} bits") if !g.match?(/\A-?\d+\z/) || Bits.write(g, n, base: 2, twos: read == "twos").nil?
            end
            (eff["mark"] || []).each_with_index do |m, i|
              return fail_.call("mark/#{i}/at", "a mark points past the last digit") if m["at"] > n
              return fail_.call("mark/#{i}/label_it", "a label has at most 6 words") if Diagrams.label_words(m["label_it"]) > 6
            end
            return nil
          end
          ROW_ONLY.each { |k| return fail_.call(k, "#{k} is for the row view") unless eff[k].nil? }
          return fail_.call("base", "the ring has base 2 codes") if !eff["base"].nil? && eff["base"] != 2
          return fail_.call("width", "the ring has 3 or 4 bits") unless [ 3, 4 ].include?(n)
          return fail_.call("read", "the ring needs unsigned, twos or both") if (eff["read"] || "unsigned") == "none"
          return fail_.call("pointer", "the pointer is a code of #{n} bits") if !eff["pointer"].nil? && eff["pointer"].size != n
          return fail_.call("step", "step needs a pointer") if eff["step"] && eff["pointer"].nil?

          (eff["highlight"] || []).each_with_index do |h, i|
            return fail_.call("highlight/#{i}/code", "a code of #{n} bits") if h["code"].size != n
            return fail_.call("highlight/#{i}/label_it", "a label has at most 6 words") if Diagrams.label_words(h["label_it"]) > 6
          end
          (eff["moves"] || []).each_with_index do |m, i|
            return fail_.call("moves/#{i}/from", "a code of #{n} bits") if m["from"].size != n
            return fail_.call("moves/#{i}/label_it", "a label has at most 6 words") if Diagrams.label_words(m["label_it"]) > 6
          end
          nil
        end

        def digits?(text, base)
          Bits.read(text, base: base)
          true
        rescue ArgumentError
          false
        end

        # The figure as the student's page gets it: the declared fields with the states merged. In :select mode everything that marks a
        # candidate is dropped (the targets are neutral, L3).
        def served(data, mode: :student)
          out = Lessons::StudentBody.diagram_generic(data) # the declared fields, the states merged, the solution fields out
          return out unless mode == :select

          out = out.except(*NEUTRAL_DROPS)
          out["states"] = out["states"].map { |s| s.except(*NEUTRAL_DROPS) } if out["states"]
          out
        end

        # The stored ids of a select set: "bits" are the digits of a row (b1 the leftmost), "codes" the codes of a ring (the code itself, from 0 up).
        def targets(data, set)
          eff = Diagrams.effective_states(data).first || data
          return Array.new(eff["width"]) { |i| "b#{i + 1}" } if set == "bits" && eff["view"] == "row"
          return Array.new(2**eff["width"]) { |k| k.to_s(2).rjust(eff["width"], "0") } if set == "codes" && eff["view"] == "ring"

          []
        end

        # Every value token the state prints (L4); the JS twin returns the same set.
        def printed(data, state = 0)
          eff = Diagrams.effective_states(data)[state] || data
          return ring_printed(eff) if eff["view"] == "ring"

          v = BitsView
          base = eff["base"] || 2
          n = eff["width"]
          twos = eff["read"] == "twos"
          out = []
          out.concat(v.both_groupings(eff["value"], eff["groups"].to_i.zero? ? 4 : eff["groups"]))
          (0...n).each { |i| out << v.show(v.weight_at(i, n, base, twos)) } if eff["weights"]
          if eff["group_digits"] && eff["groups"].to_i.positive?
            g = eff["groups"]
            end_ = n
            while end_ > 0
              value = eff["value"][[ 0, end_ - g ].max...end_].to_i(2)
              out << (g == 4 ? value.to_s(16).upcase : value.to_s)
              end_ -= g
            end
          end
          read = eff["read"] || "none"
          if read != "none"
            out << v.show(Bits.read(eff["value"], base: base, twos: twos))
            out << v.sum_line(eff["value"], twos) if eff["weights"] && base == 2 && !v.sum_line(eff["value"], twos).empty?
          end
          (eff["goals"] || []).each { |g| out << v.show(g.to_i) }
          (eff["mark"] || []).each { |m| out << m["label_it"] if m["label_it"] }
          op = data["states"] && data["states"][state] && data["states"][state]["op_it"]
          out << op if op
          out.uniq
        end

        def ring_printed(eff)
          v = BitsView
          n = eff["width"]
          nn = 2**n
          read = eff["read"] || "unsigned"
          out = []
          nn.times do |k|
            out << k.to_s if %w[unsigned both].include?(read)
            out << v.show(k < nn / 2 ? k : k - nn) if %w[twos both].include?(read)
          end
          out << eff["pointer"] if eff["pointer"]
          (eff["highlight"] || []).each do |h|
            out << h["code"]
            out << h["label_it"] if h["label_it"]
          end
          (eff["moves"] || []).each do |m|
            out << ((m["from"].to_i(2) + m["by"]) % nn).to_s(2).rjust(n, "0")
            out << m["from"]
            out << m["label_it"] if m["label_it"]
          end
          out.uniq
        end

        # The outputs the figure's controls can show (L5): every value of the register when its bits toggle, every pointer position of a ring.
        def reachable(data)
          eff = Diagrams.effective_states(data).first || data
          if eff["view"] == "row" && eff["toggle"]
            n = eff["width"]
            return :over_cap if 2**n > Contract::REACHABLE_CAP

            read = eff["read"] || "none"
            twos = read == "twos"
            return (0...2**n).flat_map do |k|
              digits = k.to_s(2).rjust(n, "0")
              [ digits, *BitsView.both_groupings(digits, eff["groups"].to_i.zero? ? 4 : eff["groups"]), (BitsView.show(Bits.read(digits, twos: twos)) unless read == "none") ]
            end.compact.uniq
          end
          if eff["view"] == "ring" && eff["step"]
            nn = 2**eff["width"]
            return Array.new(nn) { |k| ring_printed({ "width" => eff["width"], "read" => eff["read"], "pointer" => k.to_s(2).rjust(eff["width"], "0") }) }.flatten.uniq
          end
          []
        end

        # The `verify:` functions of the figure's family (WAVE2 1.10): {"bits.read" => ->(args) { "-5" }, ...}; args is the check's hash.
        def verify_functions = BitsView.verify_functions
      end
    end
  end
end
