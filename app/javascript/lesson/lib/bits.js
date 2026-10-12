// Bits: Numbers in bases 2 to 16 at a fixed width: two's complement, column operations and repeated division.
// Built by T9 (WAVE2 1.10, batch w2-1). The Ruby twin is lib/lessons/bits.rb and both run test/fixtures/lesson2/bits.json.
//
// Digits are strings of 0-9 and A-F (upper case, as the schema holds them); the width is the number of digits of a register.
// Everything is exact (BigInt inside). A value that is not a safe integer cannot leave `read`: it throws a RangeError.
// Bad arguments throw a RangeError (the types check their data before they call the library, and a refused call is a vector too).
// Orientation of the column results: index 0 is the LEFTMOST column, as the register is drawn.

// name => signature
export const SIGNATURES = {
  "read": "read(digits, base, twos)",
  "write": "write(value, width, base, twos)",
  "add": "add(a, b, width, base)",
  "sub": "sub(a, b, width, base)",
  "mul": "mul(a, b, width, base)",
  "repeated_division": "repeatedDivision(n, base)"
}

const ALPHABET = "0123456789ABCDEF"
const MAX_WIDTH = 64

function checkBase(base) {
  if (!Number.isInteger(base) || base < 2 || base > 16) throw new RangeError(`base ${base}: 2 to 16`)
  return base
}

function checkWidth(width) {
  if (!Number.isInteger(width) || width < 1 || width > MAX_WIDTH) throw new RangeError(`width ${width}: 1 to ${MAX_WIDTH}`)
  return width
}

// The digits of a string as numbers.
function digitsOf(text, base) {
  if (typeof text !== "string" || text.length === 0) throw new RangeError("digits: a non-empty string")
  return [...text].map((ch) => {
    const d = ALPHABET.indexOf(ch)
    if (d < 0 || d >= base) throw new RangeError(`digit ${ch} is not a digit of base ${base}`)
    return d
  })
}

// An integer given as a number or as a string of digits (the form the schema holds), as a BigInt.
function integer(value, name) {
  if (typeof value === "bigint") return value
  if (typeof value === "number" && Number.isSafeInteger(value)) return BigInt(value)
  if (typeof value === "string" && /^-?\d+$/.test(value)) return BigInt(value)
  throw new RangeError(`${name} ${value} is not an integer`)
}

const toBig = (digits, base) => digits.reduce((acc, d) => acc * BigInt(base) + BigInt(d), 0n)

function bigToDigits(value, base, width) {
  let out = ""
  let v = value
  const b = BigInt(base)
  while (v > 0n) {
    out = ALPHABET[Number(v % b)] + out
    v /= b
  }
  return out.padStart(width, "0")
}

function fitted(text, width, base) {
  const d = digitsOf(text, base)
  if (d.length > width) throw new RangeError(`${text} has more than ${width} digits`)
  return [...Array(width - d.length).fill(0), ...d]
}

const asDigits = (list) => list.map((d) => ALPHABET[d]).join("")

// The value of a register's digits (two's complement when `twos`: base 2 only).
export function read(digits, base = 2, twos = false) {
  checkBase(base)
  const d = digitsOf(digits, base)
  if (twos && base !== 2) throw new RangeError("two's complement is for base 2")
  let value = toBig(d, base)
  if (twos && d[0] === 1) value -= 1n << BigInt(d.length)
  if (value > BigInt(Number.MAX_SAFE_INTEGER) || value < -BigInt(Number.MAX_SAFE_INTEGER)) throw new RangeError("the value is not a safe integer")
  return Number(value)
}

// The digits of a value at a width; null when it does not fit.
export function write(value, width, base = 2, twos = false) {
  checkBase(base)
  checkWidth(width)
  if (twos && base !== 2) throw new RangeError("two's complement is for base 2")
  let v = integer(value, "value")
  const space = BigInt(base) ** BigInt(width)
  if (twos) {
    const half = space / 2n
    if (v < -half || v >= half) return null
    if (v < 0n) v += space
  } else if (v < 0n || v >= space) return null
  return bigToDigits(v, base, width)
}

// A column addition of a and b (each at most `width` digits) in a register of `width` digits:
// { digits, carries, carry_out }. carries[i] is the carry that enters column i (it is written over that column); the carry of the
// leftmost column falls out of the register: carry_out.
export function add(a, b, width, base = 2) {
  checkBase(base)
  checkWidth(width)
  const x = fitted(a, width, base)
  const y = fitted(b, width, base)
  const digits = Array(width).fill(0)
  const carries = Array(width).fill(0)
  let carry = 0
  for (let i = width - 1; i >= 0; i--) {
    carries[i] = carry
    const sum = x[i] + y[i] + carry
    digits[i] = sum % base
    carry = sum >= base ? 1 : 0
  }
  return { digits: asDigits(digits), carries, carry_out: carry }
}

// A column subtraction a - b in a register of `width` digits, wrapping when a < b: { digits, borrows }. borrows[i] is 1 when column i
// borrows from the column on its left (a borrow across zeros is a chain of ones); borrows[0] is the borrow that falls out of the register.
export function sub(a, b, width, base = 2) {
  checkBase(base)
  checkWidth(width)
  const x = fitted(a, width, base)
  const y = fitted(b, width, base)
  const digits = Array(width).fill(0)
  const borrows = Array(width).fill(0)
  let borrow = 0
  for (let i = width - 1; i >= 0; i--) {
    let diff = x[i] - y[i] - borrow
    borrow = 0
    if (diff < 0) {
      diff += base
      borrow = 1
    }
    digits[i] = diff
    borrows[i] = borrow
  }
  return { digits: asDigits(digits), borrows }
}

// A column multiplication a x b: one partial product per digit of b, from the right (shift 0, 1, ...), each as the digits of
// a x digit x base^shift written at least at `width` digits (a longer one keeps its extra left digits: they fall out of the register);
// digits: the product at `width`; full: the exact product; overflow: it does not fit.
export function mul(a, b, width, base = 2) {
  checkBase(base)
  checkWidth(width)
  const x = toBig(fitted(a, width, base), base)
  const ydigits = digitsOf(b, base)
  const partials = ydigits.map((_, k) => {
    const shift = ydigits.length - 1 - k
    const digit = ydigits[k]
    const value = x * BigInt(digit) * BigInt(base) ** BigInt(shift)
    return { shift, digit: ALPHABET[digit], digits: bigToDigits(value, base, width) }
  }).reverse()
  const product = x * toBig(ydigits, base)
  const full = bigToDigits(product, base, width)
  return { partials, digits: full.slice(full.length - width), full, overflow: full.length > width }
}

// W2-3 (the type `column_calc` op repeated_division is reserved): the quotients and remainders of dividing n by the base until 0:
// { steps: [{ dividend, quotient, remainder }], digits } with digits the remainders read from the bottom.
export function repeatedDivision(n, base) {
  checkBase(base)
  let v = integer(n, "n")
  if (v < 0n) throw new RangeError("n is not negative")
  const b = BigInt(base)
  const steps = []
  do {
    steps.push({ dividend: v.toString(), quotient: (v / b).toString(), remainder: ALPHABET[Number(v % b)] })
    v /= b
  } while (v > 0n)
  return { steps, digits: steps.map((s) => s.remainder).reverse().join("") }
}

