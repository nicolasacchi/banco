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

// The outline of a path as points about 1 px apart, one list per subpath: the absolute M L H V Q A Z that pathOf, capsule, roundRect and blob write.
function samplePath(d) {
  const tokens = d.match(/[MLHVQAZ]|-?\d*\.?\d+(?:e-?\d+)?/gi)
  const subs = []
  let pts = null
  let [x, y] = [0, 0]
  let i = 0
  const num = () => Number(tokens[i++])
  const line = (x2, y2) => {
    const n = Math.max(1, Math.ceil(Math.hypot(x2 - x, y2 - y)))
    for (let k = 1; k <= n; k++) pts.push([x + ((x2 - x) * k) / n, y + ((y2 - y) * k) / n])
    ;[x, y] = [x2, y2]
  }
  while (i < tokens.length) {
    const c = tokens[i++]
    if (c === "M") {
      ;[x, y] = [num(), num()]
      pts = [[x, y]]
      subs.push(pts)
    } else if (c === "L") line(num(), num())
    else if (c === "H") line(num(), y)
    else if (c === "V") line(x, num())
    else if (c === "Q") {
      const [qx, qy, x2, y2] = [num(), num(), num(), num()]
      for (let k = 1; k <= 24; k++) {
        const t = k / 24
        pts.push([(1 - t) ** 2 * x + 2 * (1 - t) * t * qx + t * t * x2, (1 - t) ** 2 * y + 2 * (1 - t) * t * qy + t * t * y2])
      }
      ;[x, y] = [x2, y2]
    } else if (c === "A") {
      // the arcs of a capsule: no rotation; the centre from the endpoints (SVG F.6.5)
      let [rx, ry] = [num(), num()]
      num()
      const [large, sweep, x2, y2] = [num(), num(), num(), num()]
      const [hx, hy] = [(x - x2) / 2, (y - y2) / 2]
      const lambda = (hx * hx) / (rx * rx) + (hy * hy) / (ry * ry)
      if (lambda > 1) [rx, ry] = [rx * Math.sqrt(lambda), ry * Math.sqrt(lambda)]
      const sign = large === sweep ? -1 : 1
      const coef = sign * Math.sqrt(Math.max(0, (rx * rx * ry * ry - rx * rx * hy * hy - ry * ry * hx * hx) / (rx * rx * hy * hy + ry * ry * hx * hx)))
      const [cx, cy] = [(coef * rx * hy) / ry + (x + x2) / 2, (-coef * ry * hx) / rx + (y + y2) / 2]
      const a0 = Math.atan2((y - cy) / ry, (x - cx) / rx)
      let delta = Math.atan2((y2 - cy) / ry, (x2 - cx) / rx) - a0
      if (sweep && delta <= 0) delta += 2 * Math.PI
      if (!sweep && delta >= 0) delta -= 2 * Math.PI
      const n = Math.max(8, Math.ceil(Math.abs(delta) * Math.max(rx, ry)))
      for (let k = 1; k <= n; k++) pts.push([cx + rx * Math.cos(a0 + (delta * k) / n), cy + ry * Math.sin(a0 + (delta * k) / n)])
      ;[x, y] = [x2, y2]
    } else if (c === "Z") line(...pts[0])
  }
  return subs
}

const inside = (poly, [px, py]) => {
  let odd = false
  for (let a = 0, b = poly.length - 1; a < poly.length; b = a++) {
    const [[xa, ya], [xb, yb]] = [poly[a], poly[b]]
    if (ya > py !== yb > py && px < ((xb - xa) * (py - ya)) / (yb - ya) + xa) odd = !odd
  }
  return odd
}

test("cell: the samples of a path follow its outline (the test's own tool)", () => {
  const [ring] = samplePath("M10 0 H30 A10 10 0 0 1 30 20 H10 A10 10 0 0 1 10 0 Z")
  assert.ok(ring.every(([px, py]) => px >= -0.01 && px <= 40.01 && py >= -0.01 && py <= 20.01))
  assert.ok(ring.some(([px]) => px > 39.9) && ring.some(([px]) => px < 0.1), "both ends of the capsule")
  assert.ok(inside(ring, [20, 10]) && !inside(ring, [1, 1]))
})

test("cell: in a select figure the wall's target covers its band and never the membrane, the membrane's covers its line and never the band", () => {
  // the button the page draws over a target (draw.js selectTargets: at least 28 x 28, centred on the target)
  const button = (b) => {
    const [w, h] = [Math.max(b.w, 28), Math.max(b.h, 28)]
    return { x: b.x + b.w / 2 - w / 2, y: b.y + b.h / 2 - h / 2, w, h }
  }
  // a point within a box grown by the half-width of a neutral line (2 px)
  const within = (b, [px, py]) => px >= b.x - 1 && px <= b.x + b.w + 1 && py >= b.y - 1 && py <= b.y + b.h + 1
  const cases = vectors("cell").filter((v) => v.select_apart)
  assert.ok(cases.some((v) => v.name === "cell-select-two-walls") && cases.length >= 9)
  for (const v of cases) for (const width of WIDTHS) for (const fontPx of SIZES) {
    const at = `${v.name} ${width}/${fontPx}`
    const scene = lay(v.data, { width, fontPx, mode: "select", set: "parts" })
    assert.equal(scene.error, undefined, at)
    const ids = mods.cell.targetIds(v.data, "parts")
    // the shapes of each cell, in the order of the cells: one membrane each, one band for each cell with a wall
    const lines = scene.shapes.filter((s) => s.cls?.includes("dg-cp-edge")).map((s) => samplePath(s.d)[0])
    const bands = scene.shapes.filter((s) => s.cls?.includes("dg-cp-band")).map((s) => samplePath(s.d))
    const walled = v.data.cells.map((c, i) => v.data.cells.slice(0, i + 1).filter((x) => x.parts.includes("wall")).length - 1)
    for (const [wallId, membraneId] of v.select_apart) {
      const c = Number(wallId.slice(1, wallId.indexOf("."))) - 1
      const [band, membrane] = [bands[walled[c]], lines[c]]
      const wall = button(scene.targets[ids.indexOf(wallId)].bbox)
      const mem = button(scene.targets[ids.indexOf(membraneId)].bbox)
      assert.ok(!membrane.some((p) => within(wall, p)), `${at}: the wall's target reaches the membrane`)
      assert.ok(band.flat().some((p) => within(wall, p)), `${at}: the wall's target is on its band`)
      assert.ok(!band.flat().some((p) => within(mem, p)), `${at}: the membrane's target reaches the wall`)
      assert.ok(membrane.some((p) => within(mem, p)), `${at}: the membrane's target is on its line`)
      assert.ok(inside(band[1], [mem.x + mem.w / 2, mem.y + mem.h / 2]), `${at}: the membrane's target is inside the wall`)
      assert.ok(!inside(band[1], [wall.x + wall.w / 2, wall.y + wall.h / 2]), `${at}: the wall's target reaches out of the cell`)
      // the two bands are drawn apart: the gap between the wall's inner edge and the membrane is clear
      const every = (list, n) => list.filter((_, k) => k % n === 0)
      const gap = Math.min(...every(membrane, 3).map(([px, py]) => Math.min(...every(band[1], 2).map(([qx, qy]) => Math.hypot(px - qx, py - qy)))))
      assert.ok(gap >= 4, `${at}: the membrane is ${gap.toFixed(1)} px from the wall`)
    }
  }
})

test("cell: in a select figure no ribosome's dot lies under another part's target, and the ribosomes' target keeps its cluster", () => {
  for (const v of vectors("cell")) {
    if (!v.targets) continue
    const ids = v.targets.parts
    for (const width of WIDTHS) for (const fontPx of SIZES) {
      const scene = lay(v.data, { width, fontPx, mode: "select", set: "parts" })
      const dots = scene.shapes.filter((s) => s.cls?.includes("dg-cp-dot"))
      const touches = (b, s) => s.cx + s.r > b.x && s.cx - s.r < b.x + b.w && s.cy + s.r > b.y && s.cy - s.r < b.y + b.h
      scene.targets.forEach((t, k) => {
        const n = dots.filter((s) => touches(t.bbox, s)).length
        if (ids[k].endsWith(".ribosomes")) assert.ok(n >= 2, `${v.name} ${width}/${fontPx}: the ribosomes' target has ${n} dots`)
        else assert.equal(n, 0, `${v.name} ${width}/${fontPx}: a dot under ${ids[k]}`)
      })
    }
  }
})

test("cell: all and tap: every shape of a part, and the pads along its thin lines, read that part's tap; a figure that names nothing has none", () => {
  for (const name of ["cell-tap-notes", "cell-plant-full", "cell-animal-full", "cell-compare-animal-plant", "cell-bacterium-all", "cell-highlight-dna-eukaryote"]) {
    const data = named("cell", name)
    for (const width of [360, 738]) {
      const scene = lay(data, { width })
      const keys = new Set(scene.hits.map((h) => h.key))
      const drawn = scene.shapes.filter((s) => /^dg-cp dg-cp-/.test(s.cls ?? ""))
      assert.ok(drawn.every((s) => keys.has(s.hitFor)), `${name} ${width}: a shape that reads no part`)
      for (const s of drawn) {
        const part = s.cls.match(/^dg-cp dg-cp-(\w+)/)[1]
        const [, cellIndex, hitPart] = s.hitFor.split(":")
        assert.ok(hitPart === part || (part === "dna" && hitPart === "nucleus"), `${name}: a ${part} shape reads ${s.hitFor}`)
        assert.ok(data.cells[Number(cellIndex)].parts.includes(hitPart) || hitPart === "dna", `${name}: ${s.hitFor} is a part of its cell`)
      }
      const pads = scene.shapes.filter((s) => s.cls?.startsWith("dg-cp-pad"))
      for (const part of ["membrane", "ribosomes"]) assert.ok(pads.some((p) => p.hitFor.endsWith(`:${part}`)), `${name}: a pad for the ${part}`)
      assert.ok(pads.every((p) => keys.has(p.hitFor)))
    }
  }
  const none = lay(named("cell", "cell-labels-none"))
  assert.ok(!none.shapes.some((s) => s.hitFor || s.cls?.startsWith("dg-cp-pad")), "labels none: nothing to tap")
  const select = lay(named("cell", "cell-plant-full"), { mode: "select", set: "parts" })
  assert.ok(!select.shapes.some((s) => s.hitFor || s.cls?.startsWith("dg-cp-pad")), "a select figure: no key of a part in the page")
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
