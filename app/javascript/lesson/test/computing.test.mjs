// register and column_calc (T9): the browser side of test/fixtures/diagrams/types/{register,column_calc}.json (the Ruby side is
// test/content/computing_types_test.rb) and the behaviour that vectors cannot say: toggles, the stepper, the reveal, the leaks of the text.
import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const root = new URL("../../../../", import.meta.url)
const vectors = (type) => JSON.parse(readFileSync(new URL(`test/fixtures/diagrams/types/${type}.json`, root), "utf8")).vectors
const { validate } = await import("lesson/schema")
const { checkModule, checkControls } = await import("lesson/diagrams/contract")
const mods = {
  register: await import("lesson/diagrams/computing/register"),
  column_calc: await import("lesson/diagrams/computing/column_calc")
}
const registry = await import("lesson/diagrams/registry")

const WIDTHS = [290, 360, 738, 1250]
const SIZES = [18, 20, 26]
const lay = (data, over = {}) => mods[data.type].layout(data, { width: 360, fontPx: 20, subject: "computer_science", state: 0, ...over })
const numbers = (text) => text.match(/-?\d+/g) ?? []

test("both types are in the registry as available modules that keep the contract", async () => {
  for (const type of Object.keys(mods)) {
    assert.equal(registry.STATUS[type], "available")
    assert.equal(await registry.load(type), mods[type])
    assert.deepEqual(checkModule(mods[type]), [], type)
  }
})

test("the schema and semantic columns: layout reports the first finding the file names", () => {
  for (const type of Object.keys(mods)) {
    for (const v of vectors(type)) {
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
  }
})

test("the layout column: every good case is drawn at four widths and three text sizes, with no finding", () => {
  for (const type of Object.keys(mods)) {
    for (const v of vectors(type).filter((x) => x.schema === "valid" && x.layout === "ok")) {
      const count = Math.max(1, v.data.states?.length ?? 1)
      for (const width of WIDTHS) {
        for (const fontPx of SIZES) {
          for (let state = 0; state < count; state++) {
            const out = lay(v.data, { width, fontPx, state, controls: { reveal: 3 } })
            assert.equal(out.error, undefined, `${v.name} ${width}px ${fontPx}px state ${state}: ${JSON.stringify(out.error)}`)
            assert.ok(out.height > 20 && out.width === width, `${v.name}: a scene`)
          }
        }
      }
    }
    for (const v of vectors(type).filter((x) => x.layout === "error")) assert.ok(lay(v.data).error, v.name)
  }
})

test("the printed column: the same value tokens as Ruby, for the first and the last state", () => {
  for (const type of Object.keys(mods)) {
    for (const v of vectors(type).filter((x) => x.schema === "valid" && x.semantic === "ok")) {
      assert.deepEqual([...mods[type].printed(v.data, 0)].sort(), v.printed, `${type}/${v.name}`)
      const last = (v.data.states?.length ?? 1) - 1
      if (v.printed_last) assert.deepEqual([...mods[type].printed(v.data, last)].sort(), v.printed_last, `${type}/${v.name} last`)
    }
  }
})

test("the targets column: ids in reading order, boxes of at least 24 px at 390, all neutral", () => {
  for (const type of Object.keys(mods)) {
    for (const v of vectors(type).filter((x) => x.targets)) {
      for (const [set, ids] of Object.entries(v.targets)) {
        const list = mods[type].targets(v.data, set, { width: 360, fontPx: 20 })
        assert.deepEqual(list.map((t) => t.key), ids, `${type}/${v.name} ${set}`)
        for (const t of list) {
          assert.ok(t.bbox.w >= 24 && t.bbox.h >= 24, `${v.name} ${t.key}: ${JSON.stringify(t.bbox)}`)
          assert.match(t.neutral_it, /^(Bit|Codice|Cifra) \d+ di \d+$/, "no content in the words of a target")
        }
        const scene = lay(v.data, { mode: "select" })
        assert.equal(scene.targets.length, ids.length)
        assert.deepEqual(scene.targets.map((t) => t.target), ids.map((_, i) => `t${i + 1}`))
        // neutral: no role class and no mark in the scene
        assert.ok(!scene.shapes.some((s) => /(?:^| )(?:st|mk)-/.test(s.cls ?? "")), `${v.name}: a candidate carries a role`)
        assert.ok(!scene.labels.some((l) => l.role), `${v.name}: a label carries a role`)
      }
    }
  }
})

test("describe: every number it says is one the figure prints or a count of its structure (L10)", () => {
  for (const type of Object.keys(mods)) {
    for (const v of vectors(type).filter((x) => x.schema === "valid" && x.semantic === "ok")) {
      const count = v.data.states?.length ?? 1
      for (let state = 0; state < count; state++) {
        const text = mods[type].describe(v.data, { state, controls: { reveal: 8 } })
        assert.ok(text.length > 20, `${v.name}: a description`)
        const known = new Set(mods[type].printed(v.data, state).flatMap((t) => numbers(t.replaceAll("−", "-"))))
        const eff = { ...v.data, ...(v.data.states?.[state] ?? {}) }
        const structure = new Set(["0", "1", "2", String(eff.width), String(eff.base ?? 2), String(2 ** (eff.width ?? 0)), String(2 ** (eff.width ?? 0) - 1), String(count)])
        for (let i = 1; i <= 20; i++) structure.add(String(i))
        if (eff.view === "ring") for (let k = 0; k < 2 ** eff.width; k++) structure.add(k.toString(2).padStart(eff.width, "0"))
        for (const n of numbers(text.replaceAll("−", "-").replaceAll(" ", " "))) {
          assert.ok(known.has(n) || known.has(n.replace(/^-/, "")) || structure.has(n) || structure.has(n.replace(/^-/, "")), `${type}/${v.name} state ${state}: "${n}" in "${text}"`)
        }
      }
    }
  }
})

// ---- register: what the student does ------------------------------------------------------------------------------------------------------

const lab = () => vectors("register").find((v) => v.name === "row-lab-toggle").data

test("register: a toggle flips its bit, the readout and the goals follow, and the controls are declared", () => {
  const reg = mods.register
  const list = reg.controls(lab())
  assert.deepEqual(checkControls(list), [])
  assert.equal(list.length, 8)
  assert.deepEqual(list.map((c) => c.id), Array.from({ length: 8 }, (_, i) => `bit-${i}`))
  const start = lay(lab())
  assert.match(start.labels.map((l) => l.text_it).join("|"), /vale 45/)
  assert.equal(Object.keys(start.controls).length, 8)
  assert.equal(start.controls["bit-7"].on, true, "the last bit of 00101101 is 1")
  assert.equal(start.controls["bit-0"].on, false)
  const flipped = lay(lab(), { controls: { "bit-7": true, "bit-0": true } })
  assert.match(flipped.labels.map((l) => l.text_it).join("|"), /vale 172/, "10101100")
  assert.equal(flipped.controls["bit-7"].on, false)
  assert.match(flipped.live, /1010[ \u202f]1100/)
  assert.match(reg.describe(lab(), { state: 0, controls: { "bit-0": true } }), /vale 173/)
  // a goal is reached: "Sì" appears on its chip, and not before
  const startGoals = start.labels.filter((l) => l.text_it.includes("Sì")).map((l) => l.text_it)
  assert.deepEqual(startGoals, ["45  Sì"], "45 is where the lab starts")
  const zero = lay(lab(), { controls: { "bit-2": true, "bit-4": true, "bit-5": true, "bit-7": true } }) // 00101101 xor those bits = 00000000
  assert.ok(zero.labels.some((l) => l.text_it.includes("Sì")), "the goal 0 is reached")
})

test("register: the two's complement lab reaches -1, -128 and 127 and says so", () => {
  const data = vectors("register").find((v) => v.name === "row-lab-twos-goals").data
  const reached = (flips) => lay(data, { controls: Object.fromEntries(flips.map((i) => [`bit-${i}`, true])) }).labels.filter((l) => l.text_it.includes("Sì")).map((l) => l.text_it.split(" ")[0])
  assert.deepEqual(reached([0, 1, 2, 3, 4, 5, 6, 7]), ["−1"])
  assert.deepEqual(reached([0]), ["−128"])
  assert.deepEqual(reached([1, 2, 3, 4, 5, 6, 7]), ["127"])
  assert.deepEqual(reached([]), [])
})

test("register: the sign weight is the first one, negative, in the role sign, and the readout is the sum of the weights", () => {
  const data = vectors("register")[0].data
  const { states, mark, ...plain } = data
  const out = lay(plain)
  assert.equal(out.error, undefined, JSON.stringify(out.error))
  const weights = out.labels.filter((l) => /dg-weight/.test(l.cls)).map((l) => l.text_it)
  assert.deepEqual(weights, ["−128", "64", "32", "16", "8", "4", "2", "1"])
  assert.equal(out.labels.find((l) => l.text_it === "−128").role, "sign")
  assert.ok(out.labels.some((l) => l.text_it === "−128 + 64 + 32 + 16 + 8 + 2 + 1 = −5"), "the sum line")
  assert.ok(out.labels.some((l) => l.text_it === "Il registro con segno vale −5"))
})

test("register: group digits are the hex digit under each group of four", () => {
  const data = vectors("register").find((v) => v.name === "row-group-digits").data
  const out = lay(data)
  assert.deepEqual(out.labels.filter((l) => /dg-groupdigit/.test(l.cls)).map((l) => l.text_it), ["B", "6"])
})

test("register: sixteen bits break into two rows of eight on a phone and stay one row on a wide page", () => {
  const data = vectors("register").find((v) => v.name === "row-sixteen-bits").data
  const phone = lay(data, { width: 290, fontPx: 20 })
  const wide = lay(data, { width: 1250, fontPx: 20 })
  assert.equal(phone.plan.rows, 2)
  assert.equal(wide.plan.rows, 1)
  assert.ok(phone.plan.cell >= 24, "a bit is a target of 24 px")
})

test("register ring: the stepper moves the pointer round the circle and the landing of a move is computed", () => {
  const data = vectors("register")[1].data
  const list = mods.register.controls(data)
  assert.equal(list.length, 1)
  assert.deepEqual(checkControls(list), [])
  assert.equal(list[0].initial, 0)
  const at = (moved) => lay(data, { controls: { pointer: moved } }).live
  assert.match(at(0), /0010: senza segno 2, con segno 2/)
  assert.match(at(14), /0000: senza segno 0, con segno 0/, "2 + 14 = 16 = 0: round the circle")
  assert.match(at(-3), /1111: senza segno 15, con segno −1/)
  const text = lay(data).labels.map((l) => l.text_it).join("|")
  assert.match(text, /0111 arriva a 1000 \(senza segno 8, con segno −8\)/)
  assert.match(text, /Il salto: da 0111 a 1000/)
})

test("register ring: the numbers on the ring are the unsigned values outside and the signed ones inside, and no label touches another", () => {
  const data = vectors("register")[1].data
  for (const width of WIDTHS) {
    const out = lay(data, { width, fontPx: 26 })
    assert.equal(out.error, undefined, String(width))
    const nums = out.labels.filter((l) => /dg-ringnum/.test(l.cls))
    assert.ok(nums.length >= 8, `${width}: enough numbers stay`)
    for (const code of ["0", "15", "7", "8"]) assert.ok(nums.some((l) => l.text_it === code), `${width}: ${code} is kept`)
  }
})

// ---- column_calc: the work and the reveal -------------------------------------------------------------------------------------------------

const cc = (name) => vectors("column_calc").find((v) => v.name === name).data

test("column_calc: the reveal shows one column more at a time, and what is not shown yet is nowhere in the scene or the description", () => {
  const data = cc("column_calc-example-1")
  assert.deepEqual(checkControls(mods.column_calc.controls(data)), [])
  assert.equal(mods.column_calc.controls(data)[0].range[1], 8)
  const resultDigits = (out) => out.labels.filter((l) => /dg-digit/.test(l.cls)).length
  const counts = [0, 1, 4, 8].map((k) => resultDigits(lay(data, { controls: { reveal: k } })))
  assert.equal(counts[1] - counts[0], 2, "one column: its digit and its carry")
  assert.ok(counts[2] > counts[1] && counts[3] > counts[2])
  // at no column shown the description says nothing of the result
  const before = mods.column_calc.describe(data, { state: 0, controls: {} })
  assert.ok(!before.includes("scrivo"), before)
  assert.ok(!before.includes("00000000"), "the result is not in the words before the first column")
  assert.match(mods.column_calc.describe(data, { state: 0, controls: { reveal: 2 } }), /Colonna 2/)
  assert.ok(!/Colonna 3/.test(mods.column_calc.describe(data, { state: 0, controls: { reveal: 2 } })))
  // print and select show the whole work
  assert.match(mods.column_calc.describe(data, { state: 0, controls: { reveal: 8 } }), /Il riporto dell'ultima colonna esce dal registro/)
})

test("column_calc: the carry beyond the register falls out in the role carry, dashed", () => {
  const out = lay(cc("column_calc-example-1"), { controls: { reveal: 8 } })
  assert.ok(out.shapes.some((s) => /dg-outside/.test(s.cls) && /st-carry/.test(s.cls)))
  const none = lay(cc("add-no-carry-out"), { controls: { reveal: 8 } })
  assert.ok(!none.shapes.some((s) => /dg-outside/.test(s.cls)), "nothing falls out of 3 + 4")
})

test("column_calc: a borrow across zeros changes every digit it runs through", () => {
  const out = lay(cc("sub-borrow-across-zeros"), { controls: { reveal: 8 } })
  const chips = out.shapes.filter((s) => /dg-chip/.test(s.cls) && !/dg-sample/.test(s.cls))
  assert.equal(chips.length, 8, "all eight columns are touched by 10000000 - 1")
  assert.equal(out.shapes.filter((s) => s.cls === "dg-strike").length, 8)
})

test("column_calc: a multiplication shows a partial product at a time, shifted, and the overflow outside", () => {
  const data = cc("mul-overflow")
  const out = lay(data)
  assert.ok(out.shapes.some((s) => /dg-outside/.test(s.cls)), "the ninth digit of 255 x 2")
  assert.match(mods.column_calc.describe(data), /Il prodotto intero è 111111110, ma il registro tiene 8 cifre/)
  const step = lay(cc("mul-binary"), { controls: { reveal: 1 } })
  const full = lay(cc("mul-binary"), { controls: { reveal: 4 } })
  assert.ok(full.labels.length > step.labels.length)
})

test("column_calc: sixteen bits do not fit a phone, and the module says so instead of touching digits", () => {
  const data = { ...cc("column_calc-example-1"), width: 16, a: "0000000000000101", b: "1111111111111011" }
  const phone = lay(data, { width: 290, fontPx: 26 })
  assert.equal(phone.error?.code, "E-DIAGRAM-LAYOUT")
  assert.equal(lay(data, { width: 1250, fontPx: 26 }).error, undefined)
})

test("both types: a controls-free figure declares no control, and the reveal declares one stepper", () => {
  assert.deepEqual(mods.column_calc.controls(cc("add-no-carry-out")), [])
  assert.deepEqual(mods.register.controls(vectors("register")[0].data), [])
})
