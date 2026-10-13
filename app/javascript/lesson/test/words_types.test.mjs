// The words family (WAVE2 2.6, T3), the browser's half of the vector files test/fixtures/diagrams/types/{word_parts,mirror}.json (Ruby runs the
// same: test/lib/lessons/words_types_test.rb): refused figures give { error } with the code and path of the Ruby finding, good ones draw at 320,
// 390, 768 and 1280 px and 18, 20 and 26 px in every state, and what each state prints and offers as select targets is what Ruby computed.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const doc = (path) => JSON.parse(readFileSync(new URL(path, root), "utf8"))
const MODULES = {
  word_parts: await import("lesson/diagrams/words/word_parts"),
  mirror: await import("lesson/diagrams/words/mirror")
}
const FILES = ["test/fixtures/diagrams/types/word_parts.json", "test/fixtures/diagrams/types/mirror.json"]
const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26]

for (const file of FILES) {
  const { vectors } = doc(file)
  for (const v of vectors) {
    const mod = MODULES[v.data.type]
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
      for (let state = 0; state < states; state++) {
        assert.ok(mod.describe(v.data, { state }).length > 20, "a description")
        for (const width of WIDTHS) {
          for (const fontPx of SIZES) {
            const scene = mod.layout(v.data, { width, fontPx, subject: v.subject, state })
            const where = `${v.name} ${width}/${fontPx}/state ${state}`
            assert.ok(!scene.error, `${where}: ${scene.error?.message}`)
            assert.equal(scene.width, width)
            assert.ok(scene.height > 0, where)
            for (const l of scene.labels) {
              assert.ok(l.px >= fontPx, `${where}: label size`)
              assert.ok(l.x >= -0.5 && l.x + l.w <= width + 0.5, `${where}: label inside (${l.text_it})`)
            }
            for (const s of scene.shapes) if (s.kind === "icon") assert.ok(s.x >= -1 && s.x + s.size <= width + 1, `${where}: icon inside`)
            for (const s of scene.shapes) if (s.kind === "rect") assert.ok(s.x >= -1 && s.x + s.w <= width + 1, `${where}: box inside (${s.key})`)
          }
        }
      }
      // what each state prints and what a select check can aim at: the numbers Ruby computed
      for (let state = 0; state < states; state++) assert.deepEqual(mod.printed(v.data, state), v.expect.printed[state], `${v.name}: printed, state ${state}`)
      for (const [set, ids] of Object.entries(v.expect.targets)) {
        const mine = mod.targets(v.data, set)
        assert.deepEqual(mine.map((t) => t.key), ids, `${v.name}: targets ${set}`)
        for (const t of mine) assert.ok(t.bbox && t.bbox.w > 0 && t.neutral_it, `${v.name}: ${t.key} has a box and a neutral description`)
      }
    })
  }
}

test("select mode: every candidate looks the same, carries a target, and shows no mark, link or note", () => {
  for (const file of FILES) {
    for (const v of doc(file).vectors.filter((x) => x.schema === "valid" && x.semantic === "ok")) {
      const mod = MODULES[v.data.type]
      for (const set of Object.keys(v.expect.targets)) {
        if (v.expect.targets[set].length < 2) continue
        const scene = mod.layout(mod.selectForm(v.data), { width: 700, fontPx: 20, subject: v.subject, mode: "select", set })
        assert.ok(!scene.error, `${v.name}: ${scene.error?.message}`)
        const targets = scene.shapes.filter((s) => s.target)
        assert.equal(targets.length, v.expect.targets[set].length, `${v.name} ${set}: one target for each id`)
        assert.equal(new Set(targets.map((s) => s.target)).size, targets.length)
        assert.equal(new Set(targets.map((s) => s.cls)).size, 1, `${v.name}: candidates in one style`)
        assert.ok(!scene.shapes.some((s) => /dg-mr-(shift|same|false)|dg-wp-ul|dg-wp-strong|dg-wp-dot|st-/.test(s.cls ?? "") && !s.target), `${v.name}: no mark, link or role in select mode`)
        assert.ok(!scene.labels.some((l) => /dg-wp-(meaning|key|caption|note)|dg-mr-(note|kind|key)/.test(l.cls)), `${v.name}: no note or key in select mode`)
      }
    }
  }
})
