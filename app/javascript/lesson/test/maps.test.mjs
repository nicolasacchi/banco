// The vectors of the maps family (test/fixtures/diagrams/types/{map,insolation,cross_section}.json), the browser's half: the same cases
// that test/lib/lessons/maps_types_test.rb runs in Ruby. Columns: schema, semantic, layout (320, 390, 768 and 1280 px at fontPx 18, 20,
// 26), describe, printed, targets, neutral, reachable and the geometry of the scene (labels inside the width, none under the base size).
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { pathToFileURL } from "node:url"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const G = await import("lesson/diagrams/maps/geo")
const { validate } = await import("lesson/schema")
const mods = {
  map: await import("lesson/diagrams/maps/map"),
  insolation: await import("lesson/diagrams/maps/insolation"),
  cross_section: await import("lesson/diagrams/maps/cross_section")
}
G.setBaseLoader((name) => import(pathToFileURL(new URL(`public/vendor/banco-maps@1/${name}.js`, root).pathname).href))

const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26]
const stateCount = (data) => (Array.isArray(data.states) && data.states.length > 0 ? data.states.length : 1)

for (const type of Object.keys(mods)) {
  const mod = mods[type]
  const doc = JSON.parse(readFileSync(new URL(`test/fixtures/diagrams/types/${type}.json`, root), "utf8"))
  for (const v of doc.vectors) {
    test(`${v.name}`, async () => {
      if (v.data.base) await mod.prepare(v.data, {})
      const bad = validate(mod.schema, v.data)
      if (v.schema === "invalid") {
        assert.ok(bad, "the schema refuses it")
        return
      }
      assert.equal(bad, null, JSON.stringify(bad))
      if (v.semantic !== "ok") {
        const result = mod.layout(v.data, { width: 390, fontPx: 20, subject: v.subject })
        assert.ok(result.error, `expected ${JSON.stringify(v.semantic)}, got a scene`)
        assert.equal(result.error.code, v.semantic.code, `${result.error.path}: ${result.error.message}`)
        assert.equal(result.error.path, v.semantic.path, result.error.message)
        return
      }
      assert.equal(mod.semantic(v.data), null)
      assert.equal(v.layout, "ok")
      const n = stateCount(v.data)
      for (const width of WIDTHS) {
        for (const fontPx of SIZES) {
          for (let state = 0; state < n; state++) {
            const scene = mod.layout(v.data, { width, fontPx, subject: v.subject, state })
            assert.ok(!scene.error, `${width}/${fontPx}/${state}: ${scene.error?.path} ${scene.error?.message}`)
            assert.equal(scene.width, width)
            assert.ok(scene.height > 0)
            for (const l of scene.labels) {
              assert.ok(l.px >= fontPx, "label size")
              assert.ok(l.x >= -0.5 && l.x + l.w <= width + 0.5, `label inside: ${l.text_it}`)
            }
          }
        }
      }
      if (v.describe) v.describe.forEach((text, state) => assert.equal(mod.describe(v.data, { state }), text, `describe ${state}`))
      if (v.printed) v.printed.forEach((list, state) => assert.deepEqual(mod.printed(v.data, state), list, `printed ${state}`))
      if (v.reachable) assert.deepEqual(mod.reachable(v.data), v.reachable, "reachable")
      for (const [set, ids] of Object.entries(v.targets ?? {})) {
        const t = mod.targets(v.data, set)
        assert.deepEqual(t.map((x) => x.id), ids, `targets ${set}`)
        assert.deepEqual(t.map((x) => x.neutral_it), v.neutral[set], `neutral ${set}`)
        assert.deepEqual(t.map((x) => x.key), ids.map((_, i) => `t${i + 1}`), "keys in reading order")
        // select mode: a scene of the same figure, the targets t1..tN, nothing marked and no name in the page
        const scene = mod.layout(v.data, { width: 390, fontPx: 20, subject: v.subject, mode: "select", set })
        assert.ok(!scene.error, `select ${set}: ${scene.error?.message}`)
        assert.deepEqual(scene.targets.map((x) => x.key), ids.map((_, i) => `t${i + 1}`))
        assert.equal(scene.legend.length, 0)
        const text = JSON.stringify(scene)
        for (const id of ids) if (/^[A-Z]{3}$/.test(id) || /^[a-z-]+$/.test(id)) assert.ok(!text.includes(`"${id}"`), `the id ${id} is not in the select scene`)
        assert.ok(!/class":"[^"]*(mk-|role-|fl-|tn-)/.test(text.replace(/dg-[a-z-]+/g, "")), "no role class in a select scene")
      }
    })
  }
}

test("select mode loads no name table (L3)", async () => {
  G.setTableLoader(async () => {
    throw new Error("the names must not be loaded for a select figure")
  })
  const v = JSON.parse(readFileSync(new URL("test/fixtures/diagrams/types/map.json", root), "utf8")).vectors.find((x) => x.name === "map-south-america-neutral")
  await mods.map.prepare(v.data, { mode: "select" })
  const scene = mods.map.layout(v.data, { width: 390, fontPx: 20, subject: "geography", mode: "select", set: "areas" })
  assert.ok(!scene.error, scene.error?.message)
  assert.ok(scene.targets.length > 3)
  G.setTableLoader(async () => ({
    names: (await import("lesson/data/geo-names")).default.names,
    places: (await import("lesson/data/history-places")).default.places,
    regions: (await import("lesson/data/history-regions")).default.regions
  }))
})
