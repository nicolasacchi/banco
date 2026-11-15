// A segment, line or point with the tint-only role `highlight` must be drawn (it was invisible while `.st-highlight` did
// not exist): the cartesian plot draws it as ink on a marker-pen band.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { layout } = await import("lesson/diagrams/registry")

const base = {
  type: "cartesian",
  alt_it: "Triangolo rettangolo ACH con AC come ipotenusa, AH e CH come cateti.",
  x: ["-5", "10"],
  y: ["-1", "7"],
  points: [{ x: "-4", y: "0", label_it: "A" }, { x: "0", y: "6", label_it: "C", role: "highlight" }, { x: "0", y: "0", label_it: "H" }],
  segments: [
    { from: ["-4", "0"], to: ["0", "6"], role: "highlight" },
    { from: ["-4", "0"], to: ["0", "0"] },
    { from: ["0", "0"], to: ["0", "6"], role: "highlight" }
  ],
  lines: [{ id: "l", eq: "y = x", role: "highlight" }]
}

const cls = (scene) => scene.shapes.map((s) => s.cls ?? "")

test("highlighted segments, line and point are drawn with ink and a band", () => {
  const scene = layout(base, { width: 390, fontPx: 20, subject: "math" })
  assert.equal(scene.error, undefined)
  const classes = cls(scene)
  // two highlighted segments and the line: ink on top, a band under each
  assert.equal(classes.filter((c) => c === "dg-halo").length, 3)
  assert.equal(classes.filter((c) => c === "dg-segment dg-ink").length, 2)
  assert.equal(classes.filter((c) => c === "dg-line dg-ink").length, 1)
  assert.equal(classes.filter((c) => c === "dg-segment st-muted").length, 1)
    assert.equal(classes.filter((c) => c === "fl-highlight dg-halo-dot").length, 1)
  assert.equal(classes.filter((c) => c === "dg-ink dg-point").length, 1)
  // each band is drawn before every ink segment, so it never covers one
  const last = classes.lastIndexOf("dg-halo")
  assert.ok(last < classes.indexOf("dg-segment dg-ink"))
})

test("a role with a mark keeps its stroke class", () => {
  const data = { ...base, lines: [], points: [], segments: [{ from: ["-4", "0"], to: ["0", "6"], role: "unknown" }] }
  const classes = cls(layout(data, { width: 390, fontPx: 20, subject: "math" }))
  assert.ok(classes.includes("dg-segment st-unknown"))
  assert.ok(!classes.includes("dg-halo"))
})
