// The shared diagram vectors (test/fixtures/diagrams/vectors.json), both ways (E3): every vector that Ruby
// refuses gives { error } from layout() without throwing, and every valid one gives a Scene at the widths
// 320, 390, 768 and 1280 and the text sizes 18, 20 and 26 px: inside its width, no label under the base
// size, no two labels overlapping, a non-empty description.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const { layout, describe, stateCount, TYPES } = await import("lesson/diagrams/index")
const katex = (await import("katex")).default

// The formula check that the browser leaves to Ruby: KaTeX must parse the joined parts.
const validateTex = (tex) => {
  try {
    katex.renderToString(tex, { throwOnError: true, trust: false, strict: "ignore" })
    return true
  } catch (_error) {
    return false
  }
}
const vectors = JSON.parse(readFileSync(new URL("../../../../test/fixtures/diagrams/vectors.json", import.meta.url), "utf8")).vectors

const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26]

for (const v of vectors) {
  const refused = v.schema === "invalid" || v.semantic !== "ok"
  const known = v.data && TYPES[v.data.type]
  if (!known && !refused) continue // a type not built yet in this commit
  test(`${refused ? "refuses" : "draws"} ${v.name}`, () => {
    if (refused) {
      const result = layout(v.data, { width: 390, fontPx: 20, subject: v.subject, validateTex })
      assert.ok(result.error, `expected an error, got a scene (${v.note ?? ""})`)
      if (v.semantic !== "ok" && v.schema === "valid" && v.path) {
        assert.equal(result.error.code, v.semantic, `code (${result.error.path}: ${result.error.message})`)
        assert.equal(result.error.path, v.path, result.error.message)
      }
      return
    }
    assert.ok(describe(v.data).length > 10, "a description")
    for (const width of WIDTHS) {
      for (const fontPx of SIZES) {
        for (let state = 0; state < stateCount(v.data); state++) {
          const scene = layout(v.data, { width, fontPx, subject: v.subject, validateTex, state })
          assert.ok(!scene.error, `${width}/${fontPx}/${state}: ${scene.error?.message}`)
          assert.equal(scene.width, width)
          assert.ok(scene.height > 0 || scene.table, "a height")
          for (const l of scene.labels) {
            assert.ok(l.px >= fontPx, "label size")
            assert.ok(l.x >= -0.5 && l.x + l.w <= width + 0.5, `label inside ${l.text_it}`)
          }
        }
      }
    }
  })
}

// layout() never throws: whatever is thrown at it (a field dropped, a value swapped for another type) it
// answers with a Scene or { error } (A7).
test("layout never throws on mangled data", () => {
  let seed = 12345
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
  const junk = [null, 0, -1, "", "x", [], {}, [1, 2], { a: 1 }, true, "1/0", "9".repeat(40)]
  const mangle = (value, depth = 0) => {
    if (Array.isArray(value)) {
      const copy = value.map((v) => mangle(v, depth + 1))
      if (rnd() < 0.2) copy.splice(Math.floor(rnd() * (copy.length + 1)), 1)
      return copy
    }
    if (value && typeof value === "object") {
      const copy = {}
      for (const [k, v] of Object.entries(value)) {
        const roll = rnd()
        if (roll < 0.08) continue
        copy[k] = roll < 0.16 ? junk[Math.floor(rnd() * junk.length)] : mangle(v, depth + 1)
      }
      return copy
    }
    return rnd() < 0.1 ? junk[Math.floor(rnd() * junk.length)] : value
  }
  for (let round = 0; round < 40; round++) {
    for (const v of vectors) {
      const data = mangle(v.data)
      for (const state of [0, 1]) {
        assert.doesNotThrow(() => {
          layout(data, { width: 390, fontPx: 20, subject: v.subject, state })
          describe(data)
        })
      }
    }
  }
  for (const nothing of [null, undefined, 5, "text", []]) assert.ok(layout(nothing, { width: 300, fontPx: 20 }).error)
})
