// cell (T7) and nested (T4b), D-312: the browser side of test/fixtures/diagrams/types/{cell,nested}.json (the Ruby side is
// test/content/cell_nested_types_test.rb) and what vectors cannot say: zones apart, neutral select scenes, dimming, the DNA label, the comparison,
// the water of the vacuole, boxes inside boxes.
import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const root = new URL("../../../../", import.meta.url)
const vectors = (type) => JSON.parse(readFileSync(new URL(`test/fixtures/diagrams/types/${type}.json`, root), "utf8")).vectors
const { validate } = await import("lesson/schema")
const { checkModule, checkControls } = await import("lesson/diagrams/contract")
const registry = await import("lesson/diagrams/registry")
const mods = { cell: await import("lesson/diagrams/science/cell"), nested: await import("lesson/diagrams/graph/nested") }
const TABLE = (await import("lesson/data/bio-cell_parts")).default
const TYPES = ["cell", "nested"]
const SET = { cell: "parts", nested: "levels" }
const WIDTHS = [290, 360, 738, 1250]
const SIZES = [18, 20, 26]
const lay = (data, over = {}) => mods[data.type].layout(data, { width: 360, fontPx: 20, subject: "biology", state: 0, ...over })
const named = (type, name) => vectors(type).find((v) => v.name === name).data
const texts = (scene) => scene.labels.map((l) => l.text_it)
const apart = (p, q) => p.x + p.w <= q.x + 0.5 || q.x + q.w <= p.x + 0.5 || p.y + p.h <= q.y + 0.5 || q.y + q.h <= p.y + 0.5
const PART_CLASS = new RegExp(`dg-cp-(${Object.keys(TABLE.parts).join("|")})\\b`)

test("both types are in the registry as available modules that keep the contract; cell draws in the biology palette", async () => {
  for (const type of TYPES) {
    assert.equal(registry.STATUS[type], "available")
    assert.equal(await registry.load(type), mods[type])
    assert.deepEqual(checkModule(mods[type]), [], type)
  }
  assert.equal(registry.HOME_PALETTE.cell, "biology")
  assert.equal(registry.HOME_PALETTE.nested, undefined)
  assert.deepEqual(registry.HELD_BACK.cell, { true_scale: { true: "draft" } })
})

test("the schema and semantic columns: layout reports the first finding the file names", () => {
  for (const type of TYPES) for (const v of vectors(type)) {
    const schemaErrors = validate(mods[type].schema, v.data)
    if (v.schema === "invalid") {
      assert.ok(schemaErrors, `${v.name} is refused by the schema`)
      continue
    }
    assert.equal(schemaErrors, null, `${v.name} passes the schema`)
    const out = lay(v.data)
    if (v.semantic === "ok") assert.equal(out.error, undefined, `${v.name}: ${JSON.stringify(out.error)}`)
    else assert.deepEqual({ code: out.error?.code, path: out.error?.path }, v.semantic, `${v.name}: ${out.error?.message}`)
  }
})

test("the layout column: every good case is drawn at four widths and three text sizes, in every state and with the comparison on, with no finding", () => {
  for (const type of TYPES) for (const v of vectors(type)) {
    if (v.schema !== "valid" || v.semantic !== "ok") continue
    assert.equal(v.layout, "ok", v.name)
    const count = Math.max(1, v.data.states?.length ?? 1)
    const controls = mods[type].controls?.(v.data)?.length ? [{}, { compare: ["diff"] }] : [{}]
    for (const width of WIDTHS) for (const fontPx of SIZES) for (let state = 0; state < count; state++) for (const c of controls) {
      const out = lay(v.data, { width, fontPx, state, controls: c })
      assert.equal(out.error, undefined, `${v.name} ${width}px ${fontPx}px state ${state}: ${JSON.stringify(out.error)}`)
      assert.ok(out.height > 20 && out.width === width, `${v.name}: a scene`)
      // the tap zones of a part never touch one another and stay inside the scene (A3: at least 24 px)
      const hits = out.hits ?? []
      for (const h of hits) assert.ok(h.w >= 24 && h.h >= 24 && h.x >= 0 && h.x + h.w <= width + 0.5, `${v.name} ${width}/${fontPx}: ${h.id}`)
      for (let a = 0; a < hits.length; a++) for (let b = a + 1; b < hits.length; b++) {
        if (hits[a].key.split(":")[1] !== hits[b].key.split(":")[1]) continue
        assert.ok(apart(hits[a], hits[b]), `${v.name} ${width}px ${fontPx}px: the zones of ${hits[a].id} and ${hits[b].id} touch`)
      }
    }
  }
})

test("the printed column: the same strings as Ruby, for the first and the last state", () => {
  for (const type of TYPES) for (const v of vectors(type)) {
    if (v.schema !== "valid" || v.semantic !== "ok") continue
    assert.deepEqual([...mods[type].printed(v.data, 0)].sort(), v.printed, `${type}/${v.name}`)
    const last = (v.data.states?.length ?? 1) - 1
    if (v.printed_last) assert.deepEqual([...mods[type].printed(v.data, last)].sort(), v.printed_last, `${type}/${v.name} last`)
  }
})

test("the targets column: ids in reading order, boxes of at least 24 px and apart, all neutral, no name and no part class in the select scene", () => {
  for (const type of TYPES) for (const v of vectors(type)) {
    for (const [set, ids] of Object.entries(v.targets ?? {})) {
      for (const width of WIDTHS) for (const fontPx of SIZES) {
        const list = mods[type].targets(v.data, set, { width, fontPx })
        assert.deepEqual(list.map((t) => t.key), ids, `${type}/${v.name} ${set}`)
        for (const t of list) {
          assert.ok(t.bbox.w >= 24 && t.bbox.h >= 24 && t.bbox.x >= 0 && t.bbox.x + t.bbox.w <= width + 0.5, `${v.name} ${t.key} at ${width}/${fontPx}: ${JSON.stringify(t.bbox)}`)
          assert.match(t.neutral_it, /^\S+ \d+ di \d+$/, "no content in the words of a target")
        }
        for (let a = 0; a < list.length; a++) for (let b = a + 1; b < list.length; b++) assert.ok(apart(list[a].bbox, list[b].bbox), `${v.name} ${width}/${fontPx}: ${list[a].key} and ${list[b].key} overlap`)
      }
      const scene = lay(v.data, { mode: "select", set })
      assert.deepEqual(scene.targets.map((t) => t.target), ids.map((_, i) => `t${i + 1}`))
      assert.ok(!scene.shapes.some((s) => /(?:^| )(?:st|mk|fl)-/.test(s.cls ?? "") || PART_CLASS.test(s.cls ?? "")), `${v.name}: a candidate carries a role or a part's name`)
      assert.ok(!scene.shapes.some((s) => s.key), `${v.name}: no key (a key would name a part in the page)`)
      assert.ok(!scene.labels.some((l) => l.role), `${v.name}: a label carries a role`)
      const words = texts(scene).join(" | ")
      for (const p of Object.values(TABLE.parts)) if (type === "cell") assert.ok(!words.includes(p.name_it), `${v.name}: the select scene names ${p.name_it}`)
      if (type === "nested") for (const lv of v.data.levels) assert.ok(!texts(scene).includes(lv.label_it), `${v.name}: the select scene names ${lv.label_it}`)
    }
  }
})

// ---- cell ---------------------------------------------------------------------------------------------------------------------------------

test("cell: the browser reads the same table as Ruby, and every kind has the four shared parts", () => {
  assert.deepEqual(Object.keys(TABLE.kinds).sort(), ["animal", "bacterium", "plant"])
  for (const [kind, parts] of Object.entries(TABLE.kinds)) {
    for (const p of ["membrane", "cytoplasm", "ribosomes"]) assert.ok(parts.includes(p), `${kind} ${p}`)
    assert.ok(parts.includes("nucleoid") !== parts.includes("nucleus"), kind)
  }
  assert.equal(mods.cell.partProblem("bacterium", "nucleus"), "a bacterium has no nucleus: its DNA lies in the cytoplasm (nucleoid)")
  assert.equal(mods.cell.partProblem("animal", "wall"), "an animal cell has no wall: only the plant cell and the bacterium have one")
  assert.equal(mods.cell.partProblem("plant", "vacuole"), null)
})

test("cell: names in two columns on a wide page, numbers and one key on a phone, the same number for the same part in both cells", () => {
  const data = named("cell", "cell-animal-full")
  const wide = lay(data, { width: 738 })
  assert.equal(wide.style, "sides")
  assert.ok(texts(wide).includes("mitocondri") && texts(wide).includes("apparato di Golgi"))
  assert.ok(wide.shapes.filter((s) => s.cls?.startsWith("dg-cleader ") || s.cls === "dg-cleader").length >= 8, "a leader line per name")
  const phone = lay(data, { width: 360 })
  assert.equal(phone.style, "numbers")
  const two = lay(named("cell", "cell-compare-animal-plant"), { width: 738 })
  assert.equal(two.style, "numbers")
  const nucleusNumbers = two.labels.filter((l) => /:nucleus:num$/.test(l.key ?? "")).map((l) => l.text_it)
  assert.deepEqual(nucleusNumbers, ["4", "4"], "the nucleus is 4 in both cells")
  assert.equal(texts(two).filter((t) => t === "nucleo").length, 1, "one key for the figure")
})

test("cell: a highlight lights its parts with a halo and dims the others, in both cells; the DNA of a eukaryotic cell gets its own label", () => {
  const data = named("cell", "cell-highlight-dna-eukaryote")
  const before = lay(data, { width: 738, state: 0 })
  assert.ok(!before.shapes.some((s) => / is-(lit|dim)\b/.test(s.cls ?? "")), "nothing lit in the first state")
  const after = lay(data, { width: 738, state: 1 })
  assert.ok(after.shapes.some((s) => s.cls?.includes("dg-cp-dna") && s.cls.includes("is-lit")), "the threads in the nucleus are lit")
  assert.ok(after.shapes.some((s) => s.cls?.includes("dg-cp-nucleoid") && s.cls.includes("is-lit")), "the nucleoid is the bacterium's DNA")
  assert.ok(after.shapes.some((s) => s.cls?.includes("dg-cp-mitochondria") && s.cls.includes("is-dim")), "the rest dims")
  assert.ok(after.shapes.some((s) => s.cls?.startsWith("dg-cp-halo")), "a halo: never colour alone")
  assert.ok(texts(before).includes("DNA") && texts(after).includes("DNA"), "the DNA is labelled in both states: the numbers never change")
  assert.match(mods.cell.describe(data, { state: 1 }), /Evidenziate: membrana, citoplasma, DNA e ribosomi\./)
})

test("cell: two cells with different parts offer 'Solo le differenze'; on, it lights what one has and the other has not and says it", () => {
  const data = named("cell", "cell-compare-animal-plant")
  const list = mods.cell.controls(data)
  assert.deepEqual(checkControls(list), [])
  assert.equal(list[0].kind, "chips")
  assert.deepEqual(mods.cell.differences(data.cells), ["wall", "chloroplasts", "vacuole"])
  const on = lay(data, { width: 738, controls: { compare: ["diff"] } })
  assert.equal(on.live, "Accese le parti che ha solo una delle due cellule: parete cellulare, cloroplasti e vacuolo.")
  assert.ok(on.shapes.some((s) => s.cls?.includes("dg-cp-vacuole") && s.cls.includes("is-lit")))
  assert.ok(on.shapes.filter((s) => s.cls?.includes("dg-cp-nucleus")).every((s) => s.cls.includes("is-dim")), "the shared parts dim in both cells")
  assert.match(mods.cell.describe(data, { controls: { compare: ["diff"] } }), /Accese solo le differenze: parete cellulare, cloroplasti e vacuolo\./)
  assert.deepEqual(mods.cell.controls(named("cell", "cell-labels-none")), [], "one cell: no comparison")
  assert.deepEqual(mods.cell.controls({ ...data, labels: "none" }), [], "a figure that names nothing (a select check's own) offers none")
})

test("cell: a cell's label stands for its kind in the description and on its tap buttons, so an example can ask which kind it is", () => {
  const data = named("cell", "cell-compare-animal-plant")
  const plain = { ...data, cells: data.cells.map(({ label_it, ...c }) => c) }
  assert.match(mods.cell.describe(plain, {}), /La prima, una cellula animale: .*La seconda, una cellula vegetale: /)
  assert.equal(lay(plain, { width: 738 }).hits.find((h) => h.id === "c1.nucleus").text, "nella cellula animale")
  const asked = { ...data, cells: data.cells.map((c, i) => ({ ...c, label_it: i ? "Seconda cellula" : "Prima cellula" })) }
  const said = mods.cell.describe(asked, {})
  assert.match(said, /La prima, Prima cellula: .*La seconda, Seconda cellula: /)
  assert.ok(!/animale|vegetale/.test(said), said)
  for (const h of lay(asked, { width: 738 }).hits) assert.ok(!/animale|vegetale/.test(h.text), `${h.id}: ${h.text}`)
  assert.equal(mods.cell.describe({ ...plain, cells: [plain.cells[0]] }, {}).split(".")[0], "Una cellula: una cellula animale")
})

test("cell: the water of the vacuole: low pulls the membrane away from the wall and shrinks the vacuole", () => {
  const data = named("cell", "cell-plant-water")
  const box = (scene, part) => {
    const s = scene.shapes.find((x) => x.cls?.includes(`dg-cp-${part} `) || x.cls?.endsWith(`dg-cp-${part}`))
    const nums = s.d.match(/-?\d+(\.\d+)?/g).map(Number)
    const xs = nums.filter((_, i) => i % 2 === 0)
    return Math.max(...xs) - Math.min(...xs)
  }
  const full = lay(data, { width: 738, state: 0 })
  const empty = lay(data, { width: 738, state: 2 })
  assert.ok(box(empty, "vacuole") < box(full, "vacuole") * 0.7, "the vacuole shrinks")
  assert.ok(box(empty, "cytoplasm") < box(full, "cytoplasm") * 0.95, "the membrane pulls away from the wall")
  assert.match(mods.cell.describe(data, { state: 2 }), /Il vacuolo è quasi vuoto: la membrana si stacca dalla parete\./)
})

test("cell: a tap says the name and the job, or the author's note; tap hides the names until then; none has no tap and says shapes", () => {
  const tap = lay(named("cell", "cell-tap-notes"))
  assert.ok(!texts(tap).some((t) => t === "membrana"), "no name drawn")
  assert.ok(texts(tap).includes("Tocca una parte per leggere il suo nome e che cosa fa."))
  const nucleoid = tap.hits.find((h) => h.id === "c1.nucleoid")
  assert.equal(nucleoid.name, "DNA (nucleoide)")
  assert.equal(nucleoid.note_it, "Il DNA del batterio è un filo chiuso ad anello.", "a note on dna is the nucleoid's in a bacterium")
  assert.equal(tap.hits.find((h) => h.id === "c1.ribosomes").note_it, "Costruiscono le proteine.")
  const none = lay(named("cell", "cell-labels-none"))
  assert.equal(none.hits.length, 0)
  const said = mods.cell.describe(named("cell", "cell-labels-none"), {})
  assert.match(said, /un groviglio di filo/)
  for (const p of Object.values(TABLE.parts)) assert.ok(!said.includes(p.name_it), `labels none: the description does not say ${p.name_it}`)
})

test("cell: the select scene is a neutral line drawing whose description names nothing", () => {
  const data = named("cell", "cell-plant-full")
  const scene = lay(data, { mode: "select", set: "parts" })
  assert.ok(scene.shapes.filter((s) => s.cls?.startsWith("dg-cp ")).every((s) => s.cls.includes("dg-cp-neutral")))
  assert.equal(scene.targets.length, 11)
  const said = mods.cell.describe(data, { mode: "select" })
  assert.equal(said, "Una cellula senza scritte: ci sono 11 parti da toccare.")
})

test("cell: an arrow between two parts of one cell, with its label beside it or under the figure; never on a part's zone", () => {
  for (const width of WIDTHS) for (const fontPx of SIZES) {
    const scene = lay(named("cell", "cell-three-paths"), { width, fontPx })
    assert.equal(scene.shapes.filter((s) => s.cls === "dg-cpath").length, 3)
    assert.equal(scene.shapes.filter((s) => s.cls === "dg-cpathhead").length, 3)
    const words = texts(scene)
    assert.ok(words.includes("zuccheri") || words.includes("→ zuccheri"), `${width}/${fontPx}`)
    for (const l of scene.labels.filter((x) => x.cls === "dg-cpathtext" && !x.text_it.startsWith("→"))) {
      for (const h of scene.hits) assert.ok(apart(l, h), `${width}/${fontPx}: ${l.text_it} covers ${h.id}`)
    }
  }
})

// ---- nested -------------------------------------------------------------------------------------------------------------------------------

test("nested: each level is a box inside the next one, the outermost first; the inside box is dashed in the innermost; focus lights one", () => {
  const data = named("nested", "nested-body-levels")
  for (const width of WIDTHS) for (const fontPx of SIZES) {
    const scene = lay(data, { width, fontPx, state: 1 })
    const boxes = scene.shapes.filter((s) => s.cls?.startsWith("dg-nbox"))
    assert.equal(boxes.length, 5)
    for (let i = 1; i < boxes.length; i++) {
      const [o, n] = [boxes[i - 1], boxes[i]]
      assert.ok(n.x > o.x && n.y > o.y && n.x + n.w < o.x + o.w && n.y + n.h < o.y + o.h, `${width}/${fontPx}: level ${i} inside level ${i - 1}`)
    }
    assert.equal(boxes.filter((b) => b.cls.includes("is-focus")).length, 1)
    assert.ok(boxes[3].cls.includes("is-focus"), "tessuto is the fourth box from the outside")
    assert.ok(scene.shapes.some((s) => s.cls === "dg-ninside"))
    assert.deepEqual(texts(scene).filter((t) => ["organismo", "apparato", "organo", "tessuto", "cellula"].includes(t)), ["organismo", "apparato", "organo", "tessuto", "cellula"])
  }
  assert.match(mods.nested.describe(data, { state: 1 }), /^Passo 2\. Tante cellule simili\. Riquadri uno dentro l'altro, dal più grande al più piccolo: organismo \(corpo umano\), apparato/)
  assert.match(mods.nested.describe(data, { state: 1 }), /In evidenza: tessuto\.$/)
})

test("nested: the select scene keeps the examples, drops the names, the focus and the inside box", () => {
  const data = named("nested", "nested-body-levels")
  const scene = lay(data, { mode: "select", set: "levels" })
  assert.ok(texts(scene).includes("cuore") && !texts(scene).includes("organo"))
  assert.ok(!scene.shapes.some((s) => s.cls === "dg-ninside" || s.cls?.includes("is-focus")))
  assert.deepEqual(mods.nested.targets(data, "levels").map((t) => t.key), ["organism", "system", "organ", "tissue", "cell"])
  assert.match(mods.nested.describe(data, { mode: "select" }), /^Riquadri uno dentro l'altro, senza i nomi: ci sono 5 riquadri da toccare\./)
})

test("nested: the page's select figure (positional ids, one neutral label: the server's projection) is drawn in select mode alone", () => {
  const cases = vectors("nested").filter((v) => v.select_layout === "ok")
  assert.deepEqual(cases.map((v) => v.name), ["nested-select-served"])
  for (const v of cases) {
    assert.ok(lay(v.data).error, "as a figure of the lesson two levels with one name are refused")
    for (const width of WIDTHS) for (const fontPx of SIZES) {
      const scene = lay(v.data, { width, fontPx, mode: "select", set: "levels" })
      assert.equal(scene.error, undefined, `${v.name} ${width}/${fontPx}: ${JSON.stringify(scene.error)}`)
      assert.equal(scene.targets.length, v.data.levels.length)
      assert.ok(!texts(scene).includes("·"), "the neutral label is never drawn")
      assert.deepEqual(texts(scene), [...v.data.levels].reverse().map((l) => l.example_it), "the examples, outermost first")
    }
    assert.deepEqual(mods.nested.targets(v.data, "levels").map((t) => t.neutral_it), ["Riquadro 1 di 5", "Riquadro 2 di 5", "Riquadro 3 di 5", "Riquadro 4 di 5", "Riquadro 5 di 5"])
    assert.match(mods.nested.describe(v.data, { mode: "select" }), /Gli esempi, dal più grande al più piccolo: corpo umano, apparato circolatorio/)
  }
})
