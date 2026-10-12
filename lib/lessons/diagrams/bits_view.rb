# frozen_string_literal: true

module Lessons
  module Diagrams
    # What register and column_calc print, in Ruby (the twin of app/javascript/lesson/diagrams/computing/bits_common.js): the minus sign,
    # digits in groups, the weights and the sum of the weights that count. Lessons::Bits does the arithmetic.
    module BitsView
      MINUS = "−"
      THIN = "\u202F"
      ALPHABET = Lessons::Bits::ALPHABET

      module_function

      # A whole number the way S reads it: the true minus sign, no plus.
      def show(n) = "#{n.negative? ? MINUS : ''}#{n.abs}"

      # Digits in groups from the right ("11111011" by 4 -> "1111<thin>1011").
      def grouped(digits, group, sep: THIN)
        return digits if group.to_i.zero?

        out = []
        end_ = digits.size
        while end_ > 0
          out.unshift(digits[[ 0, end_ - group ].max...end_])
          end_ -= group
        end
        out.join(sep)
      end

      # The weight of the digit at position i (0 = leftmost) in a register of n digits; the first one is negative in two's complement.
      def weight_at(i, n, base, twos)
        w = base**(n - 1 - i)
        twos && i.zero? ? -w : w
      end

      # "-128 + 64 + 8 + 2 + 1 = -5": the weights of the digits that count, and their sum ("" when none counts; base 2).
      def sum_line(digits, twos)
        parts = []
        total = 0
        digits.each_char.with_index do |ch, i|
          next unless ch == "1"

          w = weight_at(i, digits.size, 2, twos)
          parts << show(w)
          total += w
        end
        return "" if parts.empty? # nothing counts: there is nothing to add

        "#{parts.join(' + ')} = #{show(total)}"
      end

      # The `verify:` functions of the computing family (WAVE2 1.10): each takes the check's args (a Hash) and gives the canonical answer.
      def verify_functions
        {
          "bits.read" => ->(args) { Lessons::Bits.read(args["digits"], base: (args["base"] || 2).to_i, twos: args["twos"] == true || args["twos"] == "true").to_s },
          "bits.write" => ->(args) { Lessons::Bits.write(args["value"], args["width"].to_i, base: (args["base"] || 2).to_i, twos: args["twos"] == true || args["twos"] == "true") },
          "bits.add" => ->(args) { Lessons::Bits.add(args["a"], args["b"], args["width"].to_i, base: (args["base"] || 2).to_i)["digits"] }
        }
      end

      def pad(text, width) = text.rjust(width, "0")

      # The two forms of a number written in groups: with the narrow no-break space and with a plain space (what an author types).
      def both_groupings(digits, group)
        return [ digits ] if group.to_i.zero? || digits.size <= group

        [ digits, grouped(digits, group), grouped(digits, group, sep: " ") ].uniq
      end
    end
  end
end
