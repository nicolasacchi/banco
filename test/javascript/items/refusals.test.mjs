// The refused-answer rules of the student's pages (D-298): a pause after a refusal, the format from the second one.
import assert from "node:assert/strict"
import { test } from "node:test"
import { Refusals, COOLDOWN_MS } from "../../../app/javascript/items/refusals.js"

test("after a refusal the answer is inert for the cooldown and then free again", () => {
  const r = new Refusals()
  assert.equal(r.cooling(1000), false)
  r.record("item-1", 1000)
  assert.equal(r.cooling(1000), true)
  assert.equal(r.cooling(1000 + COOLDOWN_MS - 1), true)
  assert.equal(r.cooling(1000 + COOLDOWN_MS), false)
})

test("the cooldown is about a second and a half", () => {
  assert.equal(COOLDOWN_MS, 1500)
})

test("a refusal again restarts the cooldown", () => {
  const r = new Refusals()
  r.record("a", 0)
  r.record("a", 1400)
  assert.equal(r.cooling(2000), true)
  assert.equal(r.cooling(2900), false)
})

test("the format is shown from the second refusal of the same item, and only for it", () => {
  const r = new Refusals()
  assert.equal(r.showFormat("a"), false)
  assert.equal(r.record("a", 0), 1)
  assert.equal(r.showFormat("a"), false)
  assert.equal(r.record("a", 5000), 2)
  assert.equal(r.showFormat("a"), true)
  assert.equal(r.showFormat("b"), false)
  assert.equal(r.record("b", 9000), 1)
  assert.equal(r.showFormat("b"), false)
  assert.equal(r.showFormat("a"), true)
})
