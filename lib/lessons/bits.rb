# frozen_string_literal: true

module Lessons
  # Bits: Numbers in bases 2 to 16 at a fixed width: two's complement, column operations and repeated division.
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T9): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/bits.js and both run test/fixtures/lesson2/bits.json (like Lessons::Num and lesson/num.js).
  module Bits
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "read" => "read(digits, base: 2, twos: false)",
      "write" => "write(value, width, base: 2, twos: false)",
      "add" => "add(a, b, width, base: 2)",
      "sub" => "sub(a, b, width, base: 2)",
      "mul" => "mul(a, b, width, base: 2)",
      "repeated_division" => "repeated_division(n, base)"
    }.freeze

    module_function

    # The value of a register's digits.
    def read(digits, base: 2, twos: false)
      raise NotBuilt, "Lessons::Bits.read is not built yet (T9, w2-1)"
    end

    # The digits of a value at a width; nil when it does not fit.
    def write(value, width, base: 2, twos: false)
      raise NotBuilt, "Lessons::Bits.write is not built yet (T9, w2-1)"
    end

    # A column addition: {digits, carries, carry_out}.
    def add(a, b, width, base: 2)
      raise NotBuilt, "Lessons::Bits.add is not built yet (T9, w2-1)"
    end

    # A column subtraction: {digits, borrows}.
    def sub(a, b, width, base: 2)
      raise NotBuilt, "Lessons::Bits.sub is not built yet (T9, w2-1)"
    end

    # A column multiplication: partial products and the result.
    def mul(a, b, width, base: 2)
      raise NotBuilt, "Lessons::Bits.mul is not built yet (T9, w2-1)"
    end

    # W2-3: the quotients and remainders of dividing by the base until 0.
    def repeated_division(n, base)
      raise NotBuilt, "Lessons::Bits.repeated_division is not built yet (T9, w2-1)"
    end
  end
end
