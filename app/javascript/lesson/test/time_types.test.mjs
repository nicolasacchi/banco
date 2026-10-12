// The time family (WAVE2 2.2, T4a), the browser's half of test/fixtures/diagrams/types/timeline.json (Ruby runs the same: test/lib/lessons/time_types_test.rb):
// refused figures give { error } with the code and path of Ruby's finding, good ones draw at 320, 390, 768 and 1280 px and 18, 20 and 26 px in every
// state and with every control, in select mode for every set, and what each state prints and offers as select targets is what Ruby computed.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const doc = JSON.parse(readFileSync(new URL("test/fixtures/diagrams/types/timeline.json", root), "utf8"))
const mod = await import("lesson/diagrams/time/timeline")
const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26, 28]
const SETS = ["events", "periods", "marks"]

function controlSets(data) {
  const list = mod.controls(data)
  if (!list.length) return [{}]
  const sets = [{}]
  for (const c of list) {
    for (const v of c.values) sets.push({ [c.id]: [v.value] })
    sets.push({ [c.id]: c.values.slice(0, 2).map((v) => v.value) })
    sets.push({ [c.id]: c.values.map((v) => v.value) })
  }
  return sets
}

const stored = (set, key) => (set === "periods" ? key.replace(/^pd:/, "p") : key.replace(/^(ev|mk):/, ""))

for (const v of doc.vectors) {
  const refused = v.schema === "invalid" || v.semantic !== "ok"
  test(`${refused ? "refuses" : "draws"} ${v.name}`, () => {
    if (refused) {
      const result = mod.layout(v.data, { width: 390, fontPx: 20, subject: v.subject })
      assert.ok(result.error, "expected an error, got a scene")
      if (v.schema === "valid") {
        assert.equal(result.error.code, v.semantic, `code (${result.error.path}: ${result.error.message})`)
        assert.equal(result.error.path, v.path, result.error.message)
      }
      return
    }
    const states = Math.max(1, v.data.states?.length ?? 1)
    for (const controls of controlSets(v.data)) {
      for (let state = 0; state < states; state++) {
        assert.ok(mod.describe(v.data, { state, controls }).length > 20, "a description")
        for (const width of WIDTHS) {
          for (const fontPx of SIZES) {
            const scene = mod.layout(v.data, { width, fontPx, subject: v.subject, state, controls })
            const where = `${v.name} ${width}/${fontPx}/state ${state}/${JSON.stringify(controls)}`
            assert.ok(!scene.error, `${where}: ${scene.error?.message}`)
            assert.equal(scene.width, width)
            assert.ok(scene.height > 0, where)
            for (const l of scene.labels) {
              assert.ok(l.px >= fontPx, `${where}: label size`)
              assert.ok(l.x >= -0.5 && l.x + l.w <= width + 0.5, `${where}: label inside (${l.text_it})`)
            }
            for (const h of scene.hits ?? []) assert.ok(h.w >= 24 && h.h >= 24, `${where}: a hit target of at least 24 px`)
          }
        }
      }
    }
    for (let state = 0; state < states; state++) assert.deepEqual(mod.printed(v.data, state), v.expect.printed[state], `${v.name}: printed, state ${state}`)
    for (const set of SETS) {
      const ids = v.expect.targets[set]
      const mine = mod.targets(v.data, set)
      assert.deepEqual(mine.map((t) => stored(set, t.key)), ids, `${v.name}: targets ${set}`)
      for (const t of mine) assert.ok(t.bbox && t.bbox.w >= 24 && t.bbox.h >= 24 && t.neutral_it, `${v.name}: ${t.key} has a box of at least 24 px and a neutral description`)
      if (ids.length) {
        for (const width of [320, 390, 768]) {
          const scene = mod.layout(v.data, { width, fontPx: 20, subject: v.subject, mode: "select", set })
          assert.ok(!scene.error, `${v.name} select ${set} ${width}: ${scene.error?.message}`)
          assert.equal(scene.shapes.filter((s) => s.target).length, ids.length, `${v.name}: ${set} targets drawn`)
        }
      }
    }
  })
}

test("a select figure prints none of the figure's own words (L3)", () => {
  for (const v of doc.vectors.filter((x) => x.expect)) {
    const texts = []
    const walk = (n) => {
      if (Array.isArray(n)) n.forEach(walk)
      else if (n && typeof n === "object") for (const [k, x] of Object.entries(n)) typeof x === "string" && /_(it|en|es)$/.test(k) && k !== "alt_it" && k !== "op_it" ? texts.push(x) : walk(x)
    }
    walk({ ...v.data, alt_it: undefined, states: undefined })
    for (const set of SETS) {
      if (!v.expect.targets[set].length) continue
      const scene = mod.layout(v.data, { width: 700, fontPx: 20, subject: v.subject, mode: "select", set })
      const drawn = scene.labels.map((l) => l.text_it).join("\n")
      for (const t of texts) assert.ok(!drawn.includes(t), `${v.name}: select ${set} draws ${t}`)
    }
  }
})
