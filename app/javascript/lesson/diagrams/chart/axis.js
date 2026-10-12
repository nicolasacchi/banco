// The chart axis engine (WAVE2 2.4; signatures frozen in W2-0, built by T6): linear and log axes, bars from zero, ticks at the student's size
// (every other tick is dropped before any text shrinks, A3), a legend with patterns, a keyboard read cursor stepping by grid steps with the
// readout in a live region, and the value table printed under every chart (P2). climograph, seats, bar_model, chart and scale are built on it;
// number_line also gets `log: true` (W2-3).
// Values are exact strings (lesson/num); pixels are the only floats. Labels are Italian: a decimal comma, a dot between thousands.
//
// Optional keys that the frozen signatures leave room for (a caller that ignores them gets the documented defaults):
//   linear: orient "x" (default, labels side by side) | "y" (labels one above the other); nice true (default: the domain grows to whole steps)
//   log: orient as above
import * as N from "lesson/num"
import { decimalsOf, exactString, formatValue, toNum } from "lesson/diagrams/chart/format"

const GAP = 8
const PATTERNS = ["solid", "hatch", "dots", "cross", "grid"]

const fallbackMeasure = (text, px) => ({ w: String(text).length * px * 0.55, h: Math.ceil(px * 1.4) })
const extent = (measure, labels, fontPx, orient) => Math.max(...labels.map((l) => (orient === "y" ? measure(l, fontPx).h : measure(l, fontPx).w)))

// the 1-2-5 ladder of steps, as exact numbers, from tiny to huge
function* steps() {
  for (let e = -6; e <= 12; e++) {
    for (const m of [1n, 2n, 5n]) yield e >= 0 ? N.make(m * 10n ** BigInt(e)) : N.make(m, 10n ** BigInt(-e))
  }
}

// the integer q with q <= a / b < q + 1, for exact a and b > 0
function floorDiv(a, b) {
  const top = a.n * b.d
  const bottom = a.d * b.n
  const q = top / bottom
  return top % bottom !== 0n && top < 0n ? q - 1n : q
}

// linear({ min, max, length, fontPx, measure, fromZero }) -> Axis
//   Axis: { scale(value) -> px, ticks: [{ value, at, label }], step, kind: "linear", min, max, length }
// fromZero: the domain includes 0 (bars start on the baseline). The ticks are the smallest 1-2-5 step whose labels fit side by side (or one
// above the other with orient "y"): a step too fine is dropped before a label would be drawn smaller (A3).
export function linear({ min, max, length, fontPx, measure, fromZero = false, orient = "x", nice = true }) {
  let lo = toNum(min)
  let hi = toNum(max)
  if (!lo || !hi) throw new Error("axis.linear: min and max are exact numbers")
  if (fromZero) {
    if (N.compare(lo, N.int(0)) > 0) lo = N.int(0)
    if (N.compare(hi, N.int(0)) < 0) hi = N.int(0)
  }
  if (N.compare(lo, hi) >= 0) hi = N.add(lo, N.int(1))
  const m = measure ?? fallbackMeasure
  let chosen = null
  for (const step of steps()) {
    const first = nice ? N.mul(N.make(floorDiv(lo, step)), step) : lo
    const last = nice ? N.mul(N.make(-floorDiv(N.neg(hi), step)), step) : hi
    const span = N.toNumber(N.sub(last, first))
    if (span <= 0) continue
    const values = []
    for (let v = nice ? first : N.mul(N.make(-floorDiv(N.neg(lo), step)), step); N.compare(v, last) <= 0; v = N.add(v, step)) {
      values.push(v)
      if (values.length > 200) break
    }
    if (values.length > 200 || values.length === 0) continue
    const decimals = decimalsOf(step)
    const labels = values.map((v) => formatValue(v, decimals))
    const pitch = (N.toNumber(step) / span) * length
    if (pitch >= extent(m, labels, fontPx, orient) + GAP || values.length <= 2) {
      chosen = { step, first, last, values, labels, span }
      break
    }
  }
  const { step, first, last, values, labels, span } = chosen
  const origin = nice ? first : lo
  const width = nice ? span : N.toNumber(N.sub(hi, lo))
  const scale = (value) => (N.toNumber(N.sub(toNum(value), origin)) / width) * length
  return {
    kind: "linear",
    min: exactString(origin),
    max: exactString(nice ? last : hi),
    step: exactString(step),
    length,
    scale,
    ticks: values.map((v, i) => ({ value: exactString(v), at: scale(v), label: labels[i] }))
  }
}

// log({ min, max, length, fontPx, measure }) -> Axis, ticks on powers of ten (the caller adds its unit: the axis gives 1, 10, 100, 1.000)
//   Axis: { scale(value) -> px, ticks: [{ value, at, label }], step, kind: "log", min, max, length, decades }
//   step is the factor between two labelled ticks: "10", or "100" when every other decade was dropped to keep the labels at size
export function log({ min, max, length, fontPx, measure, orient = "x" }) {
  const lo = toNum(min)
  const hi = toNum(max)
  if (!lo || !hi || lo.n <= 0n || hi.n <= 0n) throw new Error("axis.log: min and max are exact numbers above 0")
  const a = Math.floor(Math.log10(N.toNumber(lo)) + 1e-9)
  let b = Math.ceil(Math.log10(N.toNumber(hi)) - 1e-9)
  if (b <= a) b = a + 1
  const power = (e) => (e >= 0 ? N.make(10n ** BigInt(e)) : N.make(1n, 10n ** BigInt(-e)))
  const m = measure ?? fallbackMeasure
  const decades = b - a
  const labelOf = (e) => formatValue(power(e), Math.max(0, -e))
  let every = 1
  for (; every < decades; every++) {
    const labels = []
    for (let e = a; e <= b; e += every) labels.push(labelOf(e))
    if ((every / decades) * length >= extent(m, labels, fontPx, orient) + GAP) break
  }
  const scale = (value) => ((Math.log10(N.toNumber(toNum(value))) - a) / decades) * length
  const ticks = []
  for (let e = a; e <= b; e += every) ticks.push({ value: exactString(power(e)), at: ((e - a) / decades) * length, label: labelOf(e) })
  return { kind: "log", min: exactString(power(a)), max: exactString(power(b)), step: String(10 ** every), length, scale, ticks, decades }
}

// readCursor(axis, { min, max, stepValue }) -> { index, value, label, move(delta), end() }
// The keyboard cursor: its positions are min, min + stepValue, ... up to max. Arrows call move(+1 / -1), Home start(), End end(). It begins on the
// first position. label is what the live region reads for the value; at is its pixel on the axis (when the axis has a scale).
export function readCursor(axis, { min, max, stepValue }) {
  const lo = toNum(min)
  const hi = toNum(max)
  const step = toNum(stepValue)
  if (!lo || !hi || !step || N.compare(step, N.int(0)) <= 0 || N.compare(lo, hi) > 0) throw new Error("readCursor: min <= max and stepValue > 0, all exact")
  const last = Number(floorDiv(N.sub(hi, lo), step))
  const decimals = Math.max(decimalsOf(lo), decimalsOf(step))
  const cursor = {
    index: 0,
    last,
    move: (delta) => cursor.to(cursor.index + delta),
    to(index) {
      cursor.index = Math.max(0, Math.min(last, index))
      const v = N.add(lo, N.mul(step, N.int(cursor.index)))
      cursor.value = exactString(v)
      cursor.label = formatValue(v, decimals)
      cursor.at = axis?.scale ? axis.scale(v) : undefined
      return cursor
    },
    start: () => cursor.to(0),
    end: () => cursor.to(last)
  }
  return cursor.to(0)
}

// legend(series) -> [{ role, pattern, label_it }]: the legend list under a chart (patterns, never colour alone, A4). A series without a pattern
// gets the next of solid, hatch, dots, cross, grid that no other series uses.
export function legend(series) {
  const taken = new Set(series.map((s) => s.pattern).filter(Boolean))
  const free = PATTERNS.filter((p) => !taken.has(p))
  return series.map((s) => ({ role: s.role ?? null, pattern: s.pattern ?? free.shift() ?? "solid", label_it: s.label_it }))
}

// valueTable(series, categories) -> { header, rows }: the value table printed under every chart of real data (P2, `print_table`) and opened by
// "Vedi i numeri". A value that is null (a hidden solution field) prints as "?"; a number prints as the author wrote it.
export function valueTable(series, categories) {
  const cell = (v) => (v === null ? "?" : v === undefined ? "" : String(v))
  return { header: ["", ...series.map((s) => s.label_it)], rows: categories.map((name, i) => [name, ...series.map((s) => cell(s.values?.[i]))]) }
}

// The frozen signatures, one string per function (checked by lesson/test/contract.test.mjs against the exports).
export const SIGNATURES = {
  linear: "linear({ min, max, length, fontPx, measure, fromZero })",
  log: "log({ min, max, length, fontPx, measure })",
  readCursor: "readCursor(axis, { min, max, stepValue })",
  legend: "legend(series)",
  valueTable: "valueTable(series, categories)"
}
