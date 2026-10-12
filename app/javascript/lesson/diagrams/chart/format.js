// Exact numbers on a chart: parsing, the Italian text of a value ("1.860,5", a true minus) and the author's way of writing it ("2,5").
// Shared by the axis engine and the chart types; pure.
import * as N from "lesson/num"

// an exact number from a string, a number we computed (to six decimals) or a lesson/num value
export const toNum = (v) => {
  if (v === null || v === undefined) return null
  if (typeof v === "number") return Number.isFinite(v) ? N.make(BigInt(Math.round(v * 1e6)), 1000000n) : null
  if (typeof v === "string") return N.parse(v)
  if (typeof v === "object" && typeof v.n === "bigint") return v
  return null
}

// the decimals an exact number needs, at most 6 (a repeating fraction is cut there)
export function decimalsOf(x) {
  let d = x.d
  let twos = 0
  let fives = 0
  while (d % 2n === 0n) { d /= 2n; twos++ }
  while (d % 5n === 0n) { d /= 5n; fives++ }
  return d === 1n ? Math.max(twos, fives) : 6
}

// "1.860,5": the decimals asked for (default: those of the number), half up away from zero, a dot between thousands from four digits, a true minus
export function formatValue(value, decimals) {
  const x = toNum(value)
  if (!x) return ""
  const k = decimals ?? decimalsOf(x)
  const scale = 10n ** BigInt(k)
  const negative = x.n < 0n
  const abs = negative ? -x.n : x.n
  const scaled = (abs * scale * 2n + x.d) / (x.d * 2n)
  const digits = String(scaled).padStart(k + 1, "0")
  const whole = digits.slice(0, digits.length - k).replace(/\B(?=(\d{3})+(?!\d))/g, ".")
  const frac = k > 0 ? `,${digits.slice(digits.length - k)}` : ""
  return `${negative && scaled !== 0n ? "−" : ""}${whole}${frac}`
}

// the author's way of writing an exact number: "3", "2,5", "-1,25"
export function exactString(x) {
  if (x.d === 1n) return String(x.n)
  return formatValue(x, decimalsOf(x)).replace(/\./g, "").replace("−", "-")
}


// the author's way of writing a number rounded to `places` (or as it is): "1860,00", "-3,25" (no dot between thousands, a plain minus)
export function authorValue(value, places) {
  return formatValue(value, places).replace(/\./g, "").replace("−", "-")
}
