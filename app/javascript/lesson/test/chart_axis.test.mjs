// The chart axis engine (T6, WAVE2 2.4): linear and log axes at every width and text size, the read cursor, the legend and the value table.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const axis = await import("lesson/diagrams/chart/axis")
const { formatValue, decimalsOf, toNum } = await import("lesson/diagrams/chart/format")
const { estimate } = await import("lesson/diagrams/common")

const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26]

test("formatValue: decimal comma, a dot between thousands, a true minus, half up", () => {
  assert.equal(formatValue("1860"), "1.860")
  assert.equal(formatValue("1860,5"), "1.860,5")
  assert.equal(formatValue("-3"), "−3")
  assert.equal(formatValue("2,25", 1), "2,3")
  assert.equal(formatValue("-2,25", 1), "−2,3")
  assert.equal(formatValue("-0,04", 1), "0,0")
  assert.equal(formatValue("1/3", 2), "0,33")
  assert.equal(formatValue("12", 2), "12,00")
  assert.equal(formatValue("999"), "999")
  assert.equal(decimalsOf(toNum("1/8")), 3)
  assert.equal(decimalsOf(toNum("1/3")), 6)
})

test("linear: bars from zero, whole 1-2-5 steps, the domain grows to whole steps", () => {
  const a = axis.linear({ min: "0", max: "238", length: 300, fontPx: 18, measure: estimate, fromZero: true, orient: "y" })
  assert.equal(a.kind, "linear")
  assert.equal(a.min, "0")
  assert.equal(Number(a.max) % Number(a.step), 0)
  assert.ok(Number(a.max) >= 238)
  assert.equal(a.scale("0"), 0)
  assert.equal(a.scale(a.max), 300)
  assert.ok(a.ticks.every((t) => Math.abs(a.scale(t.value) - t.at) < 1e-9))
  assert.deepEqual(axis.linear({ min: "20", max: "50", length: 300, fontPx: 18, fromZero: true }).min, "0", "fromZero pulls the domain down to the baseline")
  assert.equal(axis.linear({ min: "-50", max: "-20", length: 300, fontPx: 18, fromZero: true }).max, "0")
  const t = axis.linear({ min: "-15", max: "30", length: 300, fontPx: 18, measure: estimate, orient: "y" })
  assert.ok(t.ticks.some((x) => x.value === "0"), "zero is a tick when the domain holds it")
  assert.ok(t.ticks[0].label.startsWith("−"), "a true minus in the label")
})

test("linear: the labels fit at every width and text size (ticks are dropped before text shrinks) and decimals follow the step", () => {
  for (const width of WIDTHS) {
    for (const fontPx of SIZES) {
      for (const [min, max] of [["0", "1,2"], ["0", "1860"], ["0", "9999"], ["-60", "45"]]) {
        const a = axis.linear({ min, max, length: width - 40, fontPx, measure: estimate, fromZero: true })
        assert.ok(a.ticks.length >= 2)
        for (let i = 1; i < a.ticks.length; i++) {
          const need = estimate(a.ticks[i - 1].label, fontPx).w / 2 + estimate(a.ticks[i].label, fontPx).w / 2
          assert.ok(a.ticks[i].at - a.ticks[i - 1].at >= need, `${width}/${fontPx} ${min}..${max}: ${a.ticks[i - 1].label} and ${a.ticks[i].label} touch`)
        }
      }
    }
  }
  const small = axis.linear({ min: "0", max: "1", length: 400, fontPx: 18, measure: estimate })
  assert.ok(small.ticks.every((t) => /^\d,\d+$|^[01]$/.test(t.label) || t.label === "0" || t.label === "1"), small.ticks.map((t) => t.label).join(" "))
  const fewer = axis.linear({ min: "0", max: "100", length: 120, fontPx: 26, measure: estimate }).ticks.length
  const more = axis.linear({ min: "0", max: "100", length: 1200, fontPx: 18, measure: estimate }).ticks.length
  assert.ok(fewer < more, "a narrow axis at a big size has fewer ticks")
})

test("linear without nice keeps the domain; an axis with a single value still has a span", () => {
  const a = axis.linear({ min: "0", max: "45", length: 450, fontPx: 18, measure: estimate, nice: false })
  assert.equal(a.max, "45")
  assert.equal(a.scale("45"), 450)
  const one = axis.linear({ min: "5", max: "5", length: 200, fontPx: 18, measure: estimate })
  assert.ok(Number(one.max) > Number(one.min))
})

test("log: ticks on powers of ten, every other decade dropped when the labels would touch", () => {
  const a = axis.log({ min: "0,001", max: "1000", length: 700, fontPx: 18, measure: estimate })
  assert.equal(a.kind, "log")
  assert.deepEqual(a.ticks.map((t) => t.value), ["0,001", "0,01", "0,1", "1", "10", "100", "1000"])
  assert.equal(a.ticks[0].label, "0,001")
  assert.equal(a.ticks.at(-1).label, "1.000")
  assert.equal(a.scale("1"), 350)
  assert.equal(a.step, "10")
  const narrow = axis.log({ min: "0,001", max: "1000", length: 200, fontPx: 26, measure: estimate })
  assert.ok(narrow.ticks.length < a.ticks.length)
  assert.notEqual(narrow.step, "10")
  assert.throws(() => axis.log({ min: "0", max: "10", length: 100, fontPx: 18 }), /above 0/)
  for (const width of WIDTHS) for (const fontPx of SIZES) {
    const l = axis.log({ min: "0,000001", max: "1000000", length: width - 40, fontPx, measure: estimate })
    for (let i = 1; i < l.ticks.length; i++) assert.ok(l.ticks[i].at - l.ticks[i - 1].at >= (estimate(l.ticks[i - 1].label, fontPx).w + estimate(l.ticks[i].label, fontPx).w) / 2, `${width}/${fontPx}`)
  }
})

test("readCursor: steps by grid steps, clamps, Home and End, the value as exact text", () => {
  const a = axis.linear({ min: "0", max: "12", length: 240, fontPx: 18, measure: estimate })
  const c = axis.readCursor(a, { min: "0", max: "11", stepValue: "1" })
  assert.equal(c.index, 0)
  assert.equal(c.value, "0")
  assert.equal(c.move(1).value, "1")
  assert.equal(c.move(-5).index, 0)
  assert.equal(c.end().value, "11")
  assert.equal(c.move(3).index, 11)
  assert.equal(c.start().index, 0)
  assert.equal(c.at, 0)
  const d = axis.readCursor(null, { min: "0,5", max: "2", stepValue: "0,5" })
  assert.equal(d.move(1).label, "1,0")
  assert.equal(d.last, 3)
  assert.throws(() => axis.readCursor(a, { min: "0", max: "1", stepValue: "0" }))
})

test("legend gives every series its own pattern and keeps the ones the author chose", () => {
  const l = axis.legend([{ label_it: "A", role: "common" }, { label_it: "B", pattern: "solid" }, { label_it: "C" }])
  assert.deepEqual(l.map((x) => x.pattern), ["hatch", "solid", "dots"])
  assert.equal(new Set(l.map((x) => x.pattern)).size, 3)
  assert.equal(l[1].role, null)
})

test("valueTable: a header, a row per category, a hidden value as ?", () => {
  const t = axis.valueTable([{ label_it: "Pioggia (mm)", values: ["209", null] }, { label_it: "Temperatura (°C)", values: ["21,6", "21,8"] }], ["Gen", "Feb"])
  assert.deepEqual(t.header, ["", "Pioggia (mm)", "Temperatura (°C)"])
  assert.deepEqual(t.rows, [["Gen", "209", "21,6"], ["Feb", "?", "21,8"]])
})
