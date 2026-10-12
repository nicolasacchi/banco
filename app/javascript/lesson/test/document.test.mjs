// The document type (T8): its vectors (test/fixtures/diagrams/types/document.json) both ways, the hidden rows that never reach a text, the
// select targets in Ruby's order, the layout at the widths and sizes of the plan.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const { layout, describe, preload } = await import("lesson/diagrams/registry")
await preload(["document"]) // a wave 2 type is loaded on demand
const doc = await import("lesson/diagrams/docs/document")
const file = JSON.parse(readFileSync(new URL("../../../../test/fixtures/diagrams/types/document.json", import.meta.url), "utf8"))

const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26]

for (const v of file.vectors) {
  if (v.schema === "invalid") {
    test(`refuses ${v.name}`, () => assert.ok(layout(v.data, { width: 390, fontPx: 20, subject: v.subject }).error))
  } else if (v.semantic !== "ok") {
    test(`refuses ${v.name} with ${v.semantic} at ${v.path}`, () => {
      const result = layout(v.data, { width: 390, fontPx: 20, subject: v.subject })
      assert.equal(result.error?.code, v.semantic, JSON.stringify(result.error))
      assert.equal(result.error.path, v.path)
    })
  } else {
    test(`draws ${v.name} at every width and size`, () => {
      assert.ok(describe(v.data).length > 10)
      const states = v.data.states?.length ?? 1
      for (const width of WIDTHS) {
        for (const fontPx of SIZES) {
          for (let state = 0; state < states; state++) {
            const scene = layout(v.data, { width, fontPx, subject: v.subject, state })
            assert.ok(!scene.error, `${width}/${fontPx}/${state}: ${JSON.stringify(scene.error)}`)
            assert.equal(scene.width, width)
            assert.ok(scene.height > 0)
            for (const l of scene.labels) {
              assert.ok(l.px >= fontPx, "label size")
              assert.ok(l.x >= -0.5 && l.x + l.w <= width + 0.5, `label inside ${l.text_it}`)
            }
          }
        }
      }
    })
  }
}

test("a hidden row's amount is in no label, no description and no printed string (L10)", () => {
  const v = file.vectors.find((x) => x.name === "invoice-hidden-rows").data
  for (const width of WIDTHS) {
    const scene = layout(v, { width, fontPx: 20, subject: "business" })
    const texts = scene.labels.map((l) => l.text_it).join("|")
    assert.ok(!texts.includes("1.860,00") && !texts.includes("409,20"), texts)
    assert.ok(texts.includes("?"))
  }
  const said = [describe(v), ...doc.printed(v, 0)].join(" ")
  assert.ok(!said.includes("1.860,00") && !said.includes("1860,00") && !said.includes("409,20"), said)
  assert.ok(said.includes("da calcolare"))
})

test("select mode puts the stored target id on a shape for each zone and row, in the order of targets()", () => {
  const v = file.vectors.find((x) => x.name === "invoice-sheet-cover").data
  const scene = layout(v, { width: 1280, fontPx: 20, subject: "business", mode: "select" })
  const keys = scene.shapes.filter((s) => s.target).map((s) => s.target)
  const zones = doc.targets(v, "zones").map((t) => t.key)
  const rows = doc.targets(v, "rows").map((t) => t.key)
  assert.deepEqual(zones, ["seller", "buyer", "number", "date", "lines", "costs"])
  assert.deepEqual(rows, ["gross", "discounts", "net", "costs_in", "base", "vat", "costs_out", "total"])
  for (const key of [...zones, ...rows]) assert.ok(keys.includes(key), key)
  assert.ok(!layout(v, { width: 1280, fontPx: 20, subject: "business" }).shapes.some((s) => s.target))
})

test("the cascade steps show only the rows of their state", () => {
  const v = file.vectors.find((x) => x.name === "invoice-cascade-steps").data
  const first = layout(v, { width: 1280, fontPx: 20, subject: "business", state: 0 })
  const last = layout(v, { width: 1280, fontPx: 20, subject: "business", state: 4 })
  assert.equal(first.shapes.filter((s) => s.key?.startsWith("bar:")).length, 1)
  assert.equal(last.shapes.filter((s) => s.key?.startsWith("bar:")).length, 8)
  assert.ok(describe(v, { state: 0 }).includes("Merce (lordo)") && !describe(v, { state: 0 }).includes("Totale fattura"))
})

test("the typical error is drawn as it computes and titled", () => {
  const v = file.vectors.find((x) => x.name === "invoice-error-documented-costs-taxed").data
  const texts = layout(v, { width: 1280, fontPx: 20, subject: "business" }).labels.map((l) => l.text_it)
  assert.ok(texts.includes("Fattura con un errore"))
  assert.ok(texts.includes("€ 1.910,00"), texts.join("|")) // 1.800 + 60 + 50 taxed
})
