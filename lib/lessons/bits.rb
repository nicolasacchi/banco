# frozen_string_literal: true

module Lessons
  # Bits: Numbers in bases 2 to 16 at a fixed width: two's complement, column operations and repeated division.
  # Built by T9 (WAVE2 1.10, batch w2-1). The JS twin is app/javascript/lesson/lib/bits.js and both run test/fixtures/lesson2/bits.json
  # (like Lessons::Num and lesson/num.js).
  #
  # Digits are strings of 0-9 and A-F (upper case, as the schema holds them); the width is the number of digits of a register.
  # Bad arguments raise ArgumentError (the types check their data before they call the library, and a refused call is a vector too).
  # Orientation of the column results: index 0 is the LEFTMOST column, as the register is drawn.
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
    ALPHABET = "0123456789ABCDEF"
    MAX_WIDTH = 64

    module_function

    # The value of a register's digits (two's complement when +twos+: base 2 only).
    def read(digits, base: 2, twos: false)
      check_base(base)
      d = digits_of(digits, base)
      raise ArgumentError, "two's complement is for base 2" if twos && base != 2

      value = to_int(d, base)
      value -= 1 << d.size if twos && d.first == 1
      value
    end

    # The digits of a value at a width; nil when it does not fit.
    def write(value, width, base: 2, twos: false)
      check_base(base)
      check_width(width)
      raise ArgumentError, "two's complement is for base 2" if twos && base != 2

      v = integer(value, "value")
      space = base**width
      if twos
        half = space / 2
        return nil if v < -half || v >= half

        v += space if v.negative?
      elsif v.negative? || v >= space
        return nil
      end
      to_digits(v, base, width)
    end

    # A column addition of a and b (each at most +width+ digits) in a register of +width+ digits: {digits, carries, carry_out}.
    # carries[i] is the carry that enters column i (it is written over that column); the carry of the leftmost column falls out
    # of the register: carry_out.
    def add(a, b, width, base: 2)
      check_base(base)
      check_width(width)
      x = fitted(a, width, base)
      y = fitted(b, width, base)
      digits = Array.new(width, 0)
      carries = Array.new(width, 0)
      carry = 0
      (width - 1).downto(0) do |i|
        carries[i] = carry
        sum = x[i] + y[i] + carry
        digits[i] = sum % base
        carry = sum >= base ? 1 : 0
      end
      { "digits" => as_digits(digits), "carries" => carries, "carry_out" => carry }
    end

    # A column subtraction a - b in a register of +width+ digits, wrapping when a < b: {digits, borrows}. borrows[i] is 1 when
    # column i borrows from the column on its left (a borrow across zeros is a chain of ones); borrows[0] is the borrow that falls
    # out of the register.
    def sub(a, b, width, base: 2)
      check_base(base)
      check_width(width)
      x = fitted(a, width, base)
      y = fitted(b, width, base)
      digits = Array.new(width, 0)
      borrows = Array.new(width, 0)
      borrow = 0
      (width - 1).downto(0) do |i|
        diff = x[i] - y[i] - borrow
        borrow = 0
        if diff.negative?
          diff += base
          borrow = 1
        end
        digits[i] = diff
        borrows[i] = borrow
      end
      { "digits" => as_digits(digits), "borrows" => borrows }
    end

    # A column multiplication a x b: one partial product per digit of b, from the right (shift 0, 1, ...), each as the digits of
    # a x digit x base^shift written at least at +width+ digits (a longer one keeps its extra left digits: they fall out of the
    # register); digits: the product at +width+; full: the exact product; overflow: it does not fit.
    def mul(a, b, width, base: 2)
      check_base(base)
      check_width(width)
      x = to_int(fitted(a, width, base), base)
      y = digits_of(b, base)
      partials = y.each_with_index.map do |digit, k|
        shift = y.size - 1 - k
        { "shift" => shift, "digit" => ALPHABET[digit], "digits" => to_digits(x * digit * (base**shift), base, width) }
      end.reverse
      full = to_digits(x * to_int(y, base), base, width)
      { "partials" => partials, "digits" => full[-width..], "full" => full, "overflow" => full.size > width }
    end

    # W2-3 (the type column_calc op repeated_division is reserved): the quotients and remainders of dividing n by the base until
    # 0: {steps: [{dividend, quotient, remainder}], digits} with digits the remainders read from the bottom.
    def repeated_division(n, base)
      check_base(base)
      v = integer(n, "n")
      raise ArgumentError, "n is not negative" if v.negative?

      steps = []
      loop do
        steps << { "dividend" => v.to_s, "quotient" => (v / base).to_s, "remainder" => ALPHABET[v % base] }
        v /= base
        break if v.zero?
      end
      { "steps" => steps, "digits" => steps.map { |s| s["remainder"] }.reverse.join }
    end

    def integer(value, name)
      return value if value.is_a?(Integer)
      raise ArgumentError, "#{name} #{value.inspect} is not an integer" unless value.is_a?(String) && value.match?(/\A-?\d+\z/)

      Integer(value, 10)
    end

    def check_base(base)
      raise ArgumentError, "base #{base.inspect}: 2 to 16" unless base.is_a?(Integer) && base.between?(2, 16)
    end

    def check_width(width)
      raise ArgumentError, "width #{width.inspect}: 1 to #{MAX_WIDTH}" unless width.is_a?(Integer) && width.between?(1, MAX_WIDTH)
    end

    def digits_of(text, base)
      raise ArgumentError, "digits: a non-empty string" unless text.is_a?(String) && !text.empty?

      text.chars.map do |ch|
        d = ALPHABET.index(ch)
        raise ArgumentError, "digit #{ch} is not a digit of base #{base}" if d.nil? || d >= base

        d
      end
    end

    def fitted(text, width, base)
      d = digits_of(text, base)
      raise ArgumentError, "#{text} has more than #{width} digits" if d.size > width

      Array.new(width - d.size, 0) + d
    end

    def to_int(digits, base) = digits.inject(0) { |acc, d| (acc * base) + d }

    def as_digits(list) = list.map { |d| ALPHABET[d] }.join

    def to_digits(value, base, width)
      out = +""
      v = value
      while v.positive?
        out.prepend(ALPHABET[v % base])
        v /= base
      end
      out.rjust(width, "0")
    end
  end
end
