// The picture first: a callout written before a figure is moved after it. The problem of a worked example is
// split into its lead word and the formula, so that the formula can be drawn as the big pair of member tiles.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { visualFirst } = await import("lesson/cards")
const { splitProblem } = await import("lesson/blocks/example")
const { layout } = await import("lesson/diagrams/registry")

test("a callout before the first figure comes after it; other orders stay", () => {
  const callout = { type: "callout" }
  const diagram = { type: "diagram" }
  const text = { type: "text" }
  assert.deepEqual(visualFirst([callout, diagram, text]), [diagram, callout, text])
  assert.deepEqual(visualFirst([text, diagram, callout]), [text, diagram, callout])
  assert.deepEqual(visualFirst([text, callout, diagram]), [text, callout, diagram])
  assert.deepEqual(visualFirst([callout, text]), [callout, text])
})

test("the problem of an example: the lead word and the equation", () => {
  assert.deepEqual(splitProblem("Risolvi $(x - 1)^2 = x^2 + 5$."), { lead: "Risolvi", tex: "(x - 1)^2 = x^2 + 5" })
  assert.deepEqual(splitProblem("$3x = 6$"), { lead: "", tex: "3x = 6" })
  assert.equal(splitProblem("Calcola $3 + 4$."), null)
  assert.equal(splitProblem("Un testo senza formule."), null)
})

test("the parts of an equation are drawn big: chips at least 1.3 times the body size when the figure is wide", () => {
  const data = { type: "equation_parts", alt_it: "L'equazione tre x meno sette uguale due divisa in pezzi.", parts: [{ tex: "3x", role: "left" }, { tex: "-7", role: "left" }, { tex: "=", role: "muted" }, { tex: "2", role: "right" }] }
  const scene = layout(data, { width: 800, fontPx: 20, subject: "math", state: 0, measure: (text, px) => ({ w: Math.round(String(text).length * px * 0.6), h: Math.round(px * 1.3) }) })
  assert.ok(!scene.error, scene.error?.message)
  const chip = scene.labels.find((l) => /dg-chiptext/.test(l.cls))
  assert.ok(chip.px >= 26, `chip text at ${chip.px}`)
})
