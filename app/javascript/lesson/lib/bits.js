// Bits: Numbers in bases 2 to 16 at a fixed width: two's complement, column operations and repeated division.
// Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T9): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// lib/lessons/bits.rb and both run test/fixtures/lesson2/bits.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "read": "read(digits, base, twos)",
  "write": "write(value, width, base, twos)",
  "add": "add(a, b, width, base)",
  "sub": "sub(a, b, width, base)",
  "mul": "mul(a, b, width, base)",
  "repeated_division": "repeatedDivision(n, base)"
}

// The value of a register's digits.
export const read = notBuilt("bits.read", "T9", "w2-1")
// The digits of a value at a width; nil when it does not fit.
export const write = notBuilt("bits.write", "T9", "w2-1")
// A column addition: {digits, carries, carry_out}.
export const add = notBuilt("bits.add", "T9", "w2-1")
// A column subtraction: {digits, borrows}.
export const sub = notBuilt("bits.sub", "T9", "w2-1")
// A column multiplication: partial products and the result.
export const mul = notBuilt("bits.mul", "T9", "w2-1")
// W2-3: the quotients and remainders of dividing by the base until 0.
export const repeatedDivision = notBuilt("bits.repeatedDivision", "T9", "w2-1")
