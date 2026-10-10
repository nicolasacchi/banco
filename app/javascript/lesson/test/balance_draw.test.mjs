// The balance of E7: the boxes always carry an "x" (never the number being tried, which showed as a slashed zero), the
// units a "1", the pans the member colours, and the beam and pans are groups that draw.js moves.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { layout } = await import("lesson/diagrams/registry")
const { equationTex } = await import("lesson/diagrams/balance")

const data = { type: "balance", alt_it: "Bilancia con due scatole e un peso a sinistra e sette pesi a destra.", left: { x: 2, units: 1 }, right: { units: 7 }, try: { from: 0, to: 5 }, tilt: 0 }
const flat = (shapes) => shapes.flatMap((s) => (s.kind === "group" ? flat(s.children) : [s]))

test("a box is drawn with the letter x, whatever number is tried", () => {
  for (const tryValue of [undefined, 0, 3, 5]) {
    const scene = layout(data, { width: 600, fontPx: 20, subject: "math", state: 0, tryValue })
    assert.ok(!scene.error, scene.error?.message)
    const boxes = flat(scene.shapes).filter((s) => s.kind === "text" && s.cls === "bl-x")
    assert.equal(boxes.length, 2)
    for (const b of boxes) assert.equal(b.text, "x")
    const ones = flat(scene.shapes).filter((s) => s.cls === "bl-one")
    assert.equal(ones.length, 8)
    for (const o of ones) assert.equal(o.text, "1")
  }
})

test("every text is at least the base size and the pans use the member classes", () => {
  const scene = layout(data, { width: 390, fontPx: 18, subject: "math", state: 0, tryValue: 3 })
  for (const t of flat(scene.shapes).filter((s) => s.kind === "text")) assert.ok(t.px >= 18, `${t.text} at ${t.px}`)
  const classes = flat(scene.shapes).map((s) => s.cls).join(" ")
  assert.match(classes, /bl-pan-left/)
  assert.match(classes, /bl-pan-right/)
  assert.doesNotMatch(classes, /red|green|st-wrong|st-correct/)
})

test("the beam goes toward the heavier pan and is level when the pans weigh the same", () => {
  const beam = (tryValue) => layout(data, { width: 600, fontPx: 20, subject: "math", state: 0, tryValue }).shapes.find((s) => s.key === "beam").move.rot
  assert.ok(beam(0) > 0, "x = 0: the right pan is heavier, the right end goes down (clockwise)")
  assert.equal(Math.abs(beam(3)), 0)
  assert.ok(beam(5) < 0, "x = 5: the left pan is heavier")
})

test("the equation line of a state", () => {
  assert.equal(equationTex(data), "2x + 1 = 7")
  assert.equal(equationTex({ ...data, left: { x: 1 }, right: { units: 3 } }), "x = 3")
})
