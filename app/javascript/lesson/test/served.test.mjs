// The served-form lessons (test/fixtures/lesson2/served): every diagram and schema in them, as the page gets
// it (states merged, tilt computed, no x_value), lays out at the phone and desktop widths and sizes.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readdirSync, readFileSync } from "node:fs"
import { test } from "node:test"

const { layout, describe, stateCount } = await import("lesson/diagrams/registry")
const dir = new URL("../../../../test/fixtures/lesson2/served/", import.meta.url)

function* diagrams(body) {
  if (body.hero) yield ["hero", body.hero]
  const fromBlock = function* (b, where) {
    if (b.diagram) yield [where, b.diagram]
    if (b.schema) yield [where, b.schema]
    for (const c of b.cases ?? []) if (c.diagram) yield [`${where} case`, c.diagram]
    for (const e of b.exercises ?? []) if (e.diagram) yield [`${where} exercise`, e.diagram]
    for (const inner of b.blocks ?? []) yield* fromBlock(inner, `${where} more`)
  }
  for (const card of body.cards) for (const b of card.blocks) yield* fromBlock(b, `card ${card.n}`)
}

for (const file of readdirSync(dir).filter((f) => f.endsWith(".json"))) {
  const body = JSON.parse(readFileSync(new URL(file, dir), "utf8"))
  const subject = body.subject
  for (const [where, data] of diagrams(body)) {
    test(`${file} ${where} (${data.type}) lays out`, () => {
      assert.ok(describe(data).length > 10)
      for (const width of [320, 390, 768, 1280]) {
        for (const fontPx of [18, 20, 26]) {
          for (let state = 0; state < stateCount(data); state++) {
            const scene = layout(data, { width, fontPx, subject, state, tryValue: data.try ? data.try.from : undefined })
            assert.ok(!scene.error, `${width}/${fontPx}/${state}: ${scene.error?.path} ${scene.error?.message}`)
          }
        }
      }
    })
  }
}
