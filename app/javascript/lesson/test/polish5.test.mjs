// Polish after the content reviews (2026-10-14): the summary's icons outside the maths, the full stop of a year, the insolation names.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { iconFor } = await import("lesson/blocks/summary")
const { describe } = await import("lesson/diagrams/time/timeline")

test("a summary outside the maths never takes a sigma, an equals sign, infinity, divide or scale", () => {
  const used = []
  const names = ["Ogni data conta.", "Il principio è uno.", "Un rapporto di cause.", "Una frazione di storia.", "Altro", "Ancora", "Ancora uno", "E un altro"].map((t) => iconFor(t, used, "history"))
  for (const bad of ["sigma", "equal", "infinity", "divide", "scale"]) assert.ok(!names.includes(bad), `${bad} in ${names}`)
})

test("a maths summary keeps its keyword icons", () => {
  assert.equal(iconFor("Una frazione si divide.", [], "math"), "divide")
})

test("a timeline description never writes a.C. followed by two stops", () => {
  const data = {
    type: "timeline", alt_it: "x", scale: "years", from: "-146", to: "-27", centuries: true,
    periods: [{ from: "-146", to: "-27", label_it: "Crisi" }], events: [{ id: "a", at: "-133", label_it: "Tiberio Gracco" }]
  }
  const text = describe(data, { state: 0 })
  assert.ok(!/[ac]\.C\.\./.test(text), text)
  assert.match(text, /a\.C\./)
})
