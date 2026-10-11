// The shared number of a card of balances: one value, every listener told, clamped to the range.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { tryModel } = await import("lesson/try_model")

test("one model updates every balance that listens, and clamps to the range", () => {
  const seen = [[], []]
  const m = tryModel({ from: 0, to: 5 }, seen.map((log) => (v) => log.push(v)))
  assert.equal(m.value, 0)
  assert.ok(m.atMin() && !m.atMax())
  m.set(3)
  m.set(m.value + 9)
  m.set(-4)
  assert.deepEqual(seen[0], [3, 5, 0])
  assert.deepEqual(seen[1], seen[0])
  assert.equal(m.value, 0)
})

test("a compact balance has no stepper of its own: cases.js shares, draw.js skips its try group", async () => {
  const { readFileSync } = await import("node:fs")
  const draw = readFileSync(new URL("../diagrams/draw.js", import.meta.url), "utf8")
  assert.match(draw, /data\.try && !options\.compact/)
  const cases = readFileSync(new URL("../blocks/cases.js", import.meta.url), "utf8")
  assert.match(cases, /balances > 1 &&/)
})
