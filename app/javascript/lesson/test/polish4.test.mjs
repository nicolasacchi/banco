// Round 4 of the pilot look (D-259): the one-line fraction answer, labels that keep off the drawn lines, a chain that
// does not repeat the balance's equation, labels whose connectors cross no other label.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { fractionLineValue } = await import("lesson/blocks/check")
const { dropRepeatedStart } = await import("lesson/cards")
const { crosses, labelNear, stackLabels } = await import("lesson/diagrams/common")

test("a fraction typed on one line is read as numerator and denominator; an integer is over 1", () => {
  assert.deepEqual(fractionLineValue("3"), { n: "3", d: "1" })
  assert.deepEqual(fractionLineValue(" -5 / 3 "), { n: "-5", d: "3" })
  assert.deepEqual(fractionLineValue("−5/3"), { n: "-5", d: "3" })
  assert.deepEqual(fractionLineValue("5/"), { n: "5", d: "" })
  assert.deepEqual(fractionLineValue("abc"), { n: "abc", d: "1" })
})

test("a segment crosses a rectangle when it passes through it, not when it passes by", () => {
  const rect = { x: 10, y: 10, w: 20, h: 10 }
  assert.ok(crosses({ x1: 0, y1: 0, x2: 40, y2: 30 }, rect))
  assert.ok(crosses({ x1: 20, y1: 0, x2: 20, y2: 40 }, rect))
  assert.ok(!crosses({ x1: 0, y1: 40, x2: 40, y2: 40 }, rect))
  assert.ok(!crosses({ x1: 0, y1: 0, x2: 5, y2: 40 }, rect))
})

const measure = (text, px) => ({ w: Math.round(String(text).length * px * 0.6), h: Math.round(px * 1.3) })
const scratch = () => ({ measure, fontPx: 20, lineH: 28, width: 400, labels: [], shapes: [] })

test("a label next to a mark keeps off the drawn lines when there is room", () => {
  const ctx = scratch()
  const line = { x1: 100, y1: 300, x2: 300, y2: 20 }
  const box = { x0: 2, y0: 2, x1: 398, y1: 398 }
  const placed = labelNear(ctx, "y = 2x - 4", 300, 20, 6, box, { avoid: [line] })
  assert.ok(placed)
  assert.ok(!crosses(line, { x: placed.x, y: placed.y, w: placed.w, h: placed.h }), "the label is not crossed by the line")
})

test("a chain that starts with the equation of the balance above it drops that first line", () => {
  const balance = { type: "diagram", diagram: { type: "balance", states: [{ left: { x: 2, units: 3 }, right: { units: 7 } }, { left: { x: 2 }, right: { units: 4 } }] } }
  const chain = { type: "math", lines: [{ tex: "2x + 3 = 7" }, { tex: "2x + 3 - 3 = 7 - 3", note_it: "togli 3" }, { tex: "2x = 4" }] }
  const [, out] = dropRepeatedStart([balance, chain])
  assert.deepEqual(out.lines.map((l) => l.tex), ["2x + 3 - 3 = 7 - 3", "2x = 4"])
  const other = { type: "math", lines: [{ tex: "3x = 9" }, { tex: "x = 3" }, { tex: "x = 3" }] }
  assert.equal(dropRepeatedStart([balance, other])[1], other)
  const short = { type: "math", lines: [{ tex: "2x + 3 = 7" }, { tex: "2x = 4" }] }
  assert.equal(dropRepeatedStart([balance, short])[1], short)
  assert.equal(dropRepeatedStart([chain])[0], chain)
})

test("a label that would cover another's connector goes to the upper row, so no connector crosses a label", () => {
  const ctx = scratch()
  const specs = [
    { text: "termine con la x", cx: 60, cls: "n", connectFrom: 200 },
    { text: "numero", cx: 130, cls: "n", connectFrom: 200 }
  ]
  stackLabels(ctx, specs, 190, -1)
  const wide = ctx.labels.find((l) => l.text_it === "termine con la x")
  const small = ctx.labels.find((l) => l.text_it === "numero")
  assert.ok(wide.y < small.y, "the wide label is in the higher row")
  const connectors = ctx.shapes.filter((s) => s.cls === "dg-connector")
  assert.equal(connectors.length, 1)
  assert.ok(!crosses({ x1: connectors[0].x1, y1: connectors[0].y1, x2: connectors[0].x2, y2: connectors[0].y2 }, { x: small.x, y: small.y, w: small.w, h: small.h }, 0), "its connector passes beside the small label")
})
