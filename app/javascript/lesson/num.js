// Exact numbers of banco.diagram/1 (A7), the mirror of Lessons::Num: an integer ("-3"), a decimal with a
// comma ("2,5"), a fraction "a/b" with b > 0, and in number_line intervals only "-inf" / "+inf".
// BigInt numerator and denominator, no float anywhere except toNumber, which is for pixel positions only.
// The cases are in test/fixtures/lesson2/numbers.json, run by both implementations.

const INTEGER = /^-?(0|[1-9][0-9]*)$/
const DECIMAL = /^(-?)(0|[1-9][0-9]*),([0-9]+)$/
const FRACTION = /^(-?(?:0|[1-9][0-9]*))\/([1-9][0-9]*)$/

function gcd(a, b) {
  a = a < 0n ? -a : a
  b = b < 0n ? -b : b
  while (b !== 0n) [a, b] = [b, a % b]
  return a
}

export function make(n, d = 1n) {
  if (d < 0n) {
    n = -n
    d = -d
  }
  const g = gcd(n, d) || 1n
  return { n: n / g, d: d / g }
}

// A number, an infinity ({ inf: 1 | -1 }), or null when the input is refused.
export function parse(input, { allowInf = false } = {}) {
  if (typeof input !== "string") return null
  if (allowInf && (input === "+inf" || input === "-inf")) return { inf: input === "+inf" ? 1 : -1 }
  let m
  if (INTEGER.test(input)) return make(BigInt(input))
  if ((m = input.match(DECIMAL))) {
    const digits = m[3]
    const n = BigInt(m[2] + digits) * (m[1] === "-" ? -1n : 1n)
    return make(n, 10n ** BigInt(digits.length))
  }
  if ((m = input.match(FRACTION))) return make(BigInt(m[1]), BigInt(m[2]))
  return null
}

export const isInf = (x) => x !== null && x !== undefined && x.inf !== undefined

export function canonical(x) {
  if (x === null) return null
  if (isInf(x)) return x.inf > 0 ? "+inf" : "-inf"
  return `${x.n}/${x.d}`
}

export function compare(a, b) {
  if (isInf(a) || isInf(b)) {
    const ra = isInf(a) ? a.inf : 0
    const rb = isInf(b) ? b.inf : 0
    if (isInf(a) && isInf(b)) return Math.sign(ra - rb)
    return isInf(a) ? Math.sign(ra) : -Math.sign(rb)
  }
  const left = a.n * b.d
  const right = b.n * a.d
  return left < right ? -1 : left > right ? 1 : 0
}

export const eq = (a, b) => compare(a, b) === 0
export const add = (a, b) => make(a.n * b.d + b.n * a.d, a.d * b.d)
export const sub = (a, b) => make(a.n * b.d - b.n * a.d, a.d * b.d)
export const mul = (a, b) => make(a.n * b.n, a.d * b.d)
export const div = (a, b) => make(a.n * b.d, a.d * b.n)
export const neg = (a) => make(-a.n, a.d)
export const isZero = (a) => a.n === 0n
export const isInteger = (a) => a.d === 1n
export const int = (k) => make(BigInt(k))

// For pixel positions only.
export function toNumber(x) {
  if (isInf(x)) return x.inf * Infinity
  const scale = 1_000_000n
  return Number((x.n * scale) / x.d) / Number(scale)
}

// "a/b" or "n" in the Italian way, for descriptions and labels ("2,5" stays "5/2" only if it is not decimal).
export function format(x) {
  if (isInf(x)) return x.inf > 0 ? "+∞" : "−∞"
  if (x.d === 1n) return String(x.n).replace("-", "−")
  // a terminating decimal reads better as a decimal
  let d = x.d
  let twos = 0
  let fives = 0
  while (d % 2n === 0n) { d /= 2n; twos++ }
  while (d % 5n === 0n) { d /= 5n; fives++ }
  if (d === 1n) {
    const k = Math.max(twos, fives)
    const scaled = (x.n < 0n ? -x.n : x.n) * (10n ** BigInt(k)) / x.d
    let s = String(scaled).padStart(k + 1, "0")
    s = `${s.slice(0, s.length - k)},${s.slice(s.length - k)}`
    return (x.n < 0n ? "−" : "") + s
  }
  return `${String(x.n).replace("-", "−")}/${x.d}`
}
