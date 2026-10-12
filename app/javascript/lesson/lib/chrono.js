// Chrono: Years without a year 0, centuries and Roman numerals. A year is an integer string, negative = a.C.; '0' is refused.
// Built by T4a (WAVE2 1.10, batch w2-1). The Ruby twin is lib/lessons/chrono.rb and both run test/fixtures/lesson2/chrono.json.
// A bad argument (not a whole year, the year 0, a year past 9999) throws a RangeError.
//
// The axis of years: `position(year)` is the year's place on a line that goes from 1 a.C. straight into 1 d.C., so that the difference of two
// positions is the number of whole years between them (duration("-1", "1") is 1): the drawing and the sum can never disagree.

// name => signature
export const SIGNATURES = {
  "duration": "duration(from, to)",
  "century": "century(year)",
  "roman": "roman(n)",
  "parse_roman": "parseRoman(text)",
  "mutants": "mutants(from, to)"
}

const ROMAN = [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]

// A year as an integer (never 0); a RangeError otherwise.
function yearOf(value) {
  const text = String(value ?? "").trim()
  if (!/^-?[0-9]{1,4}$/.test(text)) throw new RangeError(`${JSON.stringify(value)} is not a whole year`)
  const y = Number(text)
  if (y === 0) throw new RangeError("there is no year 0")
  return y
}

// The place of a year on the axis: 1 a.C. is -1 and 1 d.C. is 0, with no place for the year 0.
export function position(value) {
  const y = yearOf(value)
  return y > 0 ? y - 1 : y
}

// Whole years from one year to the other, the year 0 not counted: -27 to 14 is 40. Negative when `to` is before `from`.
export function duration(from, to) {
  return position(to) - position(from)
}

// The Italian label of a year's century: 'II secolo a.C.'.
export function century(year) {
  const y = yearOf(year)
  const n = Math.floor((Math.abs(y) - 1) / 100) + 1
  return `${roman(n)} secolo ${y < 0 ? "a.C." : "d.C."}`
}

// A positive integer below 4000 as a Roman numeral.
export function roman(n) {
  const text = String(n)
  if (!/^[0-9]{1,4}$/.test(text) || Number(text) < 1 || Number(text) > 3999) throw new RangeError(`${JSON.stringify(n)} is not a whole number from 1 to 3999`)
  let rest = Number(text)
  let out = ""
  for (const [value, sign] of ROMAN) {
    while (rest >= value) {
      out += sign
      rest -= value
    }
  }
  return out
}

// A Roman numeral as an integer, null when it is not one (only the written form roman gives is one: IIII and IC are not).
export function parseRoman(text) {
  const s = String(text ?? "").trim().toUpperCase()
  if (!/^[IVXLCDM]+$/.test(s)) return null
  let sum = 0
  let rest = s
  for (const [value, sign] of ROMAN) {
    while (rest.startsWith(sign)) {
      sum += value
      rest = rest.slice(sign.length)
    }
  }
  return rest === "" && sum >= 1 && sum <= 3999 && roman(sum) === s ? sum : null
}

// The wrong values of duration that a typical error gives (year 0 counted, eras subtracted, same era added), by name. A name is there only when
// the error gives a different number from the right one for these two years.
export function mutants(from, to) {
  const a = yearOf(from)
  const b = yearOf(to)
  const right = duration(a, b)
  const all = {}
  if ((a < 0 && b > 0) || (a > 0 && b < 0)) {
    all.year_zero_counted = b - a
    all.eras_subtracted = Math.abs(Math.abs(b) - Math.abs(a))
  } else all.same_era_added = Math.abs(a) + Math.abs(b)
  return Object.fromEntries(Object.entries(all).filter(([, v]) => v !== right).map(([k, v]) => [k, String(v)]))
}
