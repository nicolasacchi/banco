// The tick labels of a cartesian plot: the first and the last label of an axis end at the frame's edge (never straddle it), the
// others stay centred on their tick, and no two labels overlap, whatever the numbers' width.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { layout } = await import("lesson/diagrams/registry")

const plot = (x, y) => ({ type: "cartesian", alt_it: "Un piano cartesiano con una griglia.", x, y, grid: true })

const frameOf = (scene) => scene.shapes.find((s) => s.cls === "dg-plot")
const ticks = (scene) => scene.labels.filter((l) => l.cls === "dg-tick-label")
const xTicks = (scene) => ticks(scene).filter((l) => l.anchor === "middle")
const yTicks = (scene) => ticks(scene).filter((l) => l.anchor === "end")

for (const width of [390, 1280]) {
  test(`x labels at ${width}: the last one ends at the frame, the inner ones are centred on their gridline`, () => {
    const scene = layout(plot(["-1", "4"], ["-2", "6"]), { width, fontPx: 20, subject: "math" })
    assert.equal(scene.error, undefined)
    const frame = frameOf(scene)
    const labels = xTicks(scene)
    const grid = scene.shapes.filter((s) => s.cls === "dg-grid" && s.x1 === s.x2).map((s) => s.x1).sort((a, b) => a - b)
    assert.equal(labels.length, 6)
    for (const l of labels) {
      assert.ok(l.x >= frame.x, `${l.text_it} starts inside the frame`)
      assert.ok(l.x + l.w <= frame.x + frame.w, `${l.text_it} ends inside the frame`)
    }
    labels.slice(1, -1).forEach((l, i) => assert.ok(Math.abs(l.x + l.w / 2 - grid[i]) <= 1.5, `${l.text_it} is centred on its gridline`))
    assert.equal(labels.at(-1).x + labels.at(-1).w, frame.x + frame.w)
    assert.equal(labels[0].x, frame.x)
  })

  test(`y labels at ${width}: the top and the bottom one stay inside the frame`, () => {
    const scene = layout(plot(["-1", "4"], ["-2", "6"]), { width, fontPx: 20, subject: "math" })
    const frame = frameOf(scene)
    const labels = yTicks(scene)
    for (const l of labels) {
      assert.ok(l.y >= frame.y, `${l.text_it} starts inside the frame`)
      assert.ok(l.y + l.h <= frame.y + frame.h, `${l.text_it} ends inside the frame`)
    }
  })
}

test("wide numbers: the step grows until the nudged labels stand apart", () => {
  const scene = layout(plot(["-100", "100"], ["-100", "100"]), { width: 390, fontPx: 20, subject: "math" })
  assert.equal(scene.error, undefined)
  for (const set of [xTicks(scene), yTicks(scene)]) {
    assert.ok(set.length >= 2)
    for (let i = 1; i < set.length; i++) assert.ok(set[i].x > set[i - 1].x + set[i - 1].w - 0.5 || set[i].y > set[i - 1].y + set[i - 1].h - 0.5 || set[i].y + set[i].h < set[i - 1].y + 0.5, "no two tick labels overlap")
  }
})
