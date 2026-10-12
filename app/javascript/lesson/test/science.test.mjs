// formula, molecule, periodic_table and strand (T7): the browser side of test/fixtures/diagrams/types/{formula,molecule,periodic_table,strand}.json
// (the Ruby side is test/content/science_types_test.rb) and what vectors cannot say: pieces, arrows, hidden bases, taps, the leak sentinels.
import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const root = new URL("../../../../", import.meta.url)
const vectors = (type) => JSON.parse(readFileSync(new URL(`test/fixtures/diagrams/types/${type}.json`, root), "utf8")).vectors
const { validate } = await import("lesson/schema")
const { checkModule, checkControls } = await import("lesson/diagrams/contract")
const registry = await import("lesson/diagrams/registry")
const TYPES = ["formula", "molecule"]
const mods = {}
for (const t of TYPES) mods[t] = await import(`lesson/diagrams/science/${t}`)
const HOME = { formula: "chemistry", molecule: "chemistry", periodic_table: "chemistry", strand: "biology" }

const OVERLAP_CHECKED = ["formula", "molecule"] // the types whose targets are laid out apart (the others touch by design: bonded atoms, cells of a grid)
const WIDTHS = [290, 360, 738, 1250]
const SIZES = [18, 20, 26]
const lay = (data, over = {}) => mods[data.type].layout(data, { width: 360, fontPx: 20, subject: HOME[data.type], state: 0, ...over })
const eachVector = (fn) => { for (const type of TYPES) for (const v of vectors(type)) fn(type, v) }

test("every type is in the registry as an available module that keeps the contract", async () => {
  for (const type of TYPES) {
    assert.equal(registry.STATUS[type], "available")
    assert.equal(await registry.load(type), mods[type])
    assert.deepEqual(checkModule(mods[type]), [], type)
    assert.equal(registry.HOME_PALETTE[type], HOME[type])
  }
})

test("the schema and semantic columns: layout reports the first finding the file names", () => {
  eachVector((type, v) => {
    const schemaErrors = validate(mods[type].schema, v.data)
    if (v.schema === "invalid") return assert.ok(schemaErrors, `${v.name} is refused by the schema`)
    assert.equal(schemaErrors, null, `${v.name} passes the schema`)
    const out = lay(v.data)
    if (v.semantic === "ok") assert.equal(out.error, undefined, `${v.name}: ${JSON.stringify(out.error)}`)
    else assert.deepEqual({ code: out.error?.code, path: out.error?.path }, v.semantic, `${v.name}: ${out.error?.message}`)
  })
})

test("the layout column: every good case is drawn at four widths and three text sizes, in every state, with no finding", () => {
  eachVector((type, v) => {
    if (v.schema !== "valid") return
    if (v.layout === "error") return assert.ok(lay(v.data).error, v.name)
    const count = Math.max(1, v.data.states?.length ?? 1)
    for (const width of WIDTHS) for (const fontPx of SIZES) for (let state = 0; state < count; state++) {
      const out = lay(v.data, { width, fontPx, state })
      assert.equal(out.error, undefined, `${v.name} ${width}px ${fontPx}px state ${state}: ${JSON.stringify(out.error)}`)
      assert.ok(out.height > 20 && out.width === width, `${v.name}: a scene`)
    }
  })
})

test("the printed column: the same strings as Ruby, for the first and the last state", () => {
  eachVector((type, v) => {
    if (v.schema !== "valid" || v.semantic !== "ok") return
    assert.deepEqual([...mods[type].printed(v.data, 0)].sort(), v.printed, `${type}/${v.name}`)
    const last = (v.data.states?.length ?? 1) - 1
    if (v.printed_last) assert.deepEqual([...mods[type].printed(v.data, last)].sort(), v.printed_last, `${type}/${v.name} last`)
  })
})

test("the targets column: ids in reading order, boxes of at least 24 px, all neutral, nothing named in the words of a target", () => {
  eachVector((type, v) => {
    for (const [set, ids] of Object.entries(v.targets ?? {})) {
      const list = mods[type].targets(v.data, set, { width: 360, fontPx: 20 })
      assert.deepEqual(list.map((t) => t.key), ids, `${type}/${v.name} ${set}`)
      for (const t of list) {
        assert.ok(t.bbox.w >= 24 && t.bbox.h >= 24, `${v.name} ${t.key}: ${JSON.stringify(t.bbox)}`)
        assert.match(t.neutral_it, /^\S+ \d+ di \d+$/, "no content in the words of a target")
      }
      for (let a = 0; a < list.length; a++) for (let b = a + 1; b < list.length; b++) {
        const p = list[a].bbox
        const q = list[b].bbox
        const apart = p.x + p.w <= q.x + 0.5 || q.x + q.w <= p.x + 0.5 || p.y + p.h <= q.y + 0.5 || q.y + q.h <= p.y + 0.5
        assert.ok(apart || !OVERLAP_CHECKED.includes(type), `${type}/${v.name}: the targets ${list[a].key} and ${list[b].key} overlap`)
      }
      const scene = lay(v.data, { mode: "select", set })
      assert.equal(scene.targets.length, ids.length)
      assert.deepEqual(scene.targets.map((t) => t.target), ids.map((_, i) => `t${i + 1}`))
      assert.ok(!scene.shapes.some((s) => /(?:^| )(?:st|mk|fl)-/.test(s.cls ?? "")), `${v.name}: a candidate carries a role`)
      assert.ok(!scene.labels.some((l) => l.role), `${v.name}: a label carries a role`)
    }
  })
})

// ---- formula ---------------------------------------------------------------------------------------------------------------------------

const named = (type, name) => vectors(type).find((v) => v.name === name).data
const texts = (scene) => scene.labels.map((l) => l.text_it)

test("formula: the pieces are labelled once per kind, the arrows point back from the subscripts, the count is computed", () => {
  const data = named("formula", "formula-brackets-and-count")
  const scene = lay(data, { width: 738 })
  const all = texts(scene).join("|")
  for (const word of ["coefficiente", "simbolo", "pedice", "pacchetto", "Atomi in tutto"]) assert.match(all, new RegExp(word))
  assert.equal(texts(scene).filter((t) => t.startsWith("[[subscript:pedice]]")).length, 1, "one row of the key per kind")
  assert.equal(scene.shapes.filter((s) => s.cls === "dg-arrow").length, 2, "one arrow per subscript: the 3 of NO3 and the 2 of the bracket")
  // 2 Ca(NO3)2: Ca 2, N 4, O 12 (the three products are the chain of the row)
  assert.ok(texts(scene).includes("[[subscript:3]] × [[group:2]] × [[coefficient:2]] = 12"))
  assert.ok(texts(scene).includes("[[subscript:1]] × [[coefficient:2]] = 2") || texts(scene).includes("1 × [[coefficient:2]] = 2"))
  assert.ok(scene.shapes.some((s) => s.cls === "dg-focus"), "the focus O is highlighted")
})

test("formula: no count is typed by the author, molecules come from the library and copy the coefficient", () => {
  const scene = lay(named("formula", "formula-example-1"), { width: 738, state: 0 })
  assert.ok(!texts(scene).some((t) => t.includes("Atomi")), "the first state shows the parts only")
  const full = lay(named("formula", "formula-three-steps"), { width: 738, state: 2 })
  const atoms = full.shapes.filter((s) => /dg-atom /.test(s.cls ?? ""))
  assert.equal(atoms.length, 9, "three molecules of three atoms")
  assert.equal(texts(full).filter((t) => t === "O").length, 3 + 1 + 1, "an O inside each of the three oxygen atoms, one in the large formula, one in the count")
})

test("formula: the speech reads the meaning and never the letters", () => {
  const seg = mods.formula.speechSegments(named("formula", "formula-three-steps"), { state: 2 })
  assert.equal(seg.length, 1)
  assert.match(seg[0].text, /^tre molecole d'acqua\. In tutto 6 atomi di idrogeno e 3 di ossigeno\.$/)
  assert.doesNotMatch(seg[0].text, /H2O/)
  assert.match(mods.formula.describe(named("formula", "formula-ionic-unit"), {}), /un'unità di cloruro di sodio/)
  assert.match(mods.formula.describe(named("formula", "formula-brackets-and-count"), {}), /2 atomi di calcio, 4 di azoto e 12 di ossigeno/)
})

test("formula: describe says only what the state shows (L10)", () => {
  const data = named("formula", "formula-three-steps")
  assert.doesNotMatch(mods.formula.describe(data, { state: 0 }), /In tutto|molecole/)
  assert.match(mods.formula.describe(data, { state: 1 }), /In tutto 6 atomi/)
  assert.doesNotMatch(mods.formula.describe(data, { state: 1 }), /molecole d'acqua/)
  assert.match(mods.formula.describe(data, { state: 2 }), /molecole d'acqua/)
})
