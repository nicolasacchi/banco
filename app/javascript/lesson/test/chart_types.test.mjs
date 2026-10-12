// T6, the chart family in the browser's code: climograph, seats and bar_model against their vector files (test/fixtures/diagrams/types/TYPE.json)
// and the computations against the shared vectors (climate.json, seats.json). The Ruby twins run the same files in
// test/lib/lessons/chart_types_test.rb.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const read = (path) => JSON.parse(readFileSync(new URL(`../../../../${path}`, import.meta.url), "utf8"))
const N = await import("lesson/num")
const climograph = await import("lesson/diagrams/chart/climograph")
const seats = await import("lesson/diagrams/chart/seats")
const barModel = await import("lesson/diagrams/chart/bar_model")
const climate = await import("lesson/diagrams/chart/climate")
const { validate } = await import("lesson/schema")
const MODULES = { climograph, seats, bar_model: barModel }
const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26]

// the Ruby server resolves a station and cuts a hidden value; the page gets that form (Lessons::StudentBody)
const stations = (await import("lesson/data/geo-stations")).default.stations
const resolve = (data) => {
  const row = (ref) => stations[ref.split(".")[1]]
  let out = data
  if (data.station && row(data.station)) {
    const r = row(data.station)
    out = { ...data, temp: r.temp, precip: r.precip, lat: r.lat, alt_m: r.alt_m, place_it: data.place_it ?? `${r.name_it} (${r.country_it})`, source_it: data.source_it ?? "Medie 1991-2020 dei servizi meteorologici nazionali (OMM)" }
  }
  if (data.compare?.station && row(data.compare.station)) {
    const r = row(data.compare.station)
    out = { ...out, compare: { ...data.compare, temp: r.temp, place_it: data.compare.place_it ?? `${r.name_it} (${r.country_it})` } }
  }
  return out
}

for (const type of ["climograph", "seats", "bar_model"]) {
  const mod = MODULES[type]
  const doc = read(`test/fixtures/diagrams/types/${type}.json`)
  for (const v of doc.vectors) {
    if (v.schema === "invalid") {
      test(`${v.name}: refused by the compiled schema`, () => assert.ok(validate(mod.schema, v.data)))
      continue
    }
    const data = type === "climograph" ? resolve(v.data) : v.data
    if (v.layout === "error") {
      test(`${v.name}: layout answers the error of the semantic column`, () => {
        const r = mod.layout(data, { width: 390, fontPx: 20, subject: v.subject })
        assert.ok(r.error, "an error, not a scene")
        assert.equal(r.error.code, v.semantic.code, `${r.error.path}: ${r.error.message}`)
        assert.equal(r.error.path, v.semantic.path)
      })
      continue
    }
    if (v.layout !== "ok") continue
    test(`${v.name}: draws at every width and size, in every state, and describes itself`, () => {
      const n = data.states?.length ?? 1
      assert.ok(mod.describe(data).length > 20)
      for (const width of WIDTHS) {
        for (const fontPx of SIZES) {
          for (let state = 0; state < n; state++) {
            const scene = mod.layout(data, { width, fontPx, subject: v.subject, state })
            assert.ok(!scene.error, `${width}/${fontPx}/${state}: ${scene.error?.path} ${scene.error?.message}`)
            assert.equal(scene.width, width)
            assert.ok(scene.height > 40)
            for (const l of scene.labels) {
              assert.ok(l.px >= fontPx, `label size: ${l.text_it}`)
              assert.ok(l.x >= -0.5 && l.x + l.w <= width + 0.5, `label inside: ${l.text_it}`)
            }
            for (const sh of scene.shapes) for (const k of ["x", "y", "w", "h", "cx", "cy", "r"]) if (k in sh) assert.ok(Number.isFinite(sh[k]), `${k} of a ${sh.kind}`)
          }
        }
      }
    })
    if (v.printed) {
      test(`${v.name}: prints what the Ruby twin prints`, () => {
        v.printed.forEach((expected, state) => assert.deepEqual(mod.printed(data, state), expected, `state ${state}`))
      })
    }
    if (v.values) {
      test(`${v.name}: computes the values of the Ruby twin`, () => {
        v.values.forEach((expected, state) => {
          const eff = barModel.percentValues(state === 0 && !v.data.states ? v.data : { ...v.data, ...v.data.states[state] })
          assert.deepEqual(eff, expected, `state ${state}`)
        })
      })
    }
    for (const set of v.select ?? []) {
      test(`${v.name}: select targets ${set}`, () => {
        const t = mod.targets(data, set)
        assert.equal(t.length, 12)
        assert.deepEqual(t.map((x) => x.key), Array.from({ length: 12 }, (_, i) => `t${i + 1}`))
        assert.ok(t.every((x) => x.bbox.w > 0 && x.neutral_it))
      })
    }
    for (const [set, count] of Object.entries(v.targets ?? {})) {
      test(`${v.name}: select targets ${set}`, () => assert.equal(mod.targets(data, set).length, count))
    }
  }
}

test("the climate computations equal the shared vectors", () => {
  for (const c of read("test/fixtures/lesson2/climate.json").cases) {
    const s = climate.stats(c.temp.map((x) => N.parse(x)), c.precip.map((x) => N.parse(x)))
    assert.deepEqual(s.arid, c.expect.arid, c.name)
    assert.equal(N.canonical(s.total), c.expect.total, c.name)
    assert.equal(N.canonical(s.mean), c.expect.mean, c.name)
    assert.equal(s.warmest, c.expect.warmest, c.name)
    assert.equal(s.coldest, c.expect.coldest, c.name)
    assert.equal(N.canonical(s.range), c.expect.range, c.name)
  }
  assert.equal(climate.monthList([1, 2, 3, 4, 5, 11, 12]), "da gennaio a maggio, novembre e dicembre")
  assert.equal(climate.monthList([6, 7]), "giugno e luglio")
  assert.equal(climate.monthList([]), "")
})

test("the seats arithmetic equals the shared vectors", () => {
  for (const c of read("test/fixtures/lesson2/seats.json").cases) {
    const got = seats.thresholds(c.seats, c.present ?? undefined, c.yes ?? undefined, c.list)
    assert.deepEqual(got, c.expect, c.why)
    assert.equal(seats.approved(c.seats, c.present ?? undefined, c.yes ?? undefined, c.list), c.approved, c.name)
  }
})

test("a hidden part is drawn by its width and never named: the served null value reaches no label and no description", () => {
  const served = {
    type: "bar_model", alt_it: "Una barra con una parte nascosta da trovare.", view: "parts", total: { value: "913", label_it: "in tutto" },
    bars: [{ label_it: "Barra", parts: [{ value: "311", label_it: "uno" }, { value: null, label_it: "resto", hidden: true }] }]
  }
  const scene = barModel.layout(served, { width: 390, fontPx: 20, subject: "business" })
  assert.ok(!scene.error, scene.error?.message)
  const texts = scene.labels.map((l) => l.text_it).join("|")
  assert.ok(!texts.includes("602"))
  assert.ok(texts.includes("?"), "the hidden part shows a question mark")
  assert.ok(!barModel.describe(served).includes("602"))
  const hidden = scene.shapes.find((s) => s.cls?.includes("dgq-hidden"))
  const visible = scene.shapes.find((s) => s.cls?.includes("dgq-p0"))
  assert.ok(Math.abs(hidden.w / visible.w - 602 / 311) < 0.01, "the hidden part has the width of the rest: 602 against 311")
})

test("percent view: served values are drawn, a null is a question mark, and nothing is worked out from what shows", () => {
  const served = {
    type: "bar_model", alt_it: "Una scala doppia con il cento per cento nascosto e l'IVA visibile.", view: "percent", unit: "euro", hide: ["100"],
    marks: [{ pct: "22", label_it: "IVA", role: "tax" }], values: { 22: "1626,05", 100: null }, chain_values: undefined
  }
  const scene = barModel.layout(served, { width: 390, fontPx: 20, subject: "business" })
  assert.ok(!scene.error, scene.error?.message)
  const texts = scene.labels.map((l) => l.text_it)
  assert.ok(texts.some((t) => t.startsWith("1.626,05")), texts.join("|"))
  assert.ok(texts.includes("?"))
  assert.ok(!texts.join("|").includes("7391"))
})

test("seats: the sliders move the counts and the readout; the figure follows present and yes and never shows yes above present", () => {
  const data = read("test/fixtures/diagrams/types/seats.json").vectors[0].data
  const at = (controls) => seats.layout(data, { width: 390, fontPx: 20, subject: "law_economics", controls })
  const a = at({ present: 280, yes: 150 })
  assert.ok(a.live.includes("Presenti: 280"))
  assert.ok(a.live.includes("servono 141 sì. Ci sono.") && a.live.includes("Esito: approvata"), a.live)
  const b = at({ present: 310, yes: 200 })
  assert.ok(b.live.includes("servono 156 sì") && b.live.includes("Ci sono."), b.live)
  assert.ok(b.live.includes("Esito: approvata"))
  assert.deepEqual(seats.controls(data).map((c) => [c.id, c.kind, c.range, c.step]), [["present", "slider", ["280", "310"], "1"], ["yes", "slider", ["150", "200"], "1"]])
  const seatShapes = (scene) => scene.shapes.slice(0, 400) // the seats come first, then the legend's swatches
  const count = (scene, cls) => seatShapes(scene).filter((s) => s.cls?.includes(cls)).length
  assert.equal(count(a, "dgs-absent"), 400 - 280)
  assert.equal(count(a, "dgs-no"), 280 - 150)
  assert.equal(count(a, "dgs-yes"), 150, "the yes seats are drawn full")
  assert.equal(count(b, "dgs-absent"), 90)
  assert.equal(count(b, "dgs-no"), 110)
  assert.equal(count(b, "dgs-yes"), 200)
  const out = at({ present: 9999, yes: 9999 })
  assert.equal(out.live.includes("Presenti: 310"), true, "a value outside the declared range is held to it")
})

test("climograph: one scale at a time, the cursor reads only the shown layers, a select figure answers nothing", () => {
  const doc = read("test/fixtures/diagrams/types/climograph.json")
  const vec = (name) => resolve(doc.vectors.find((v) => v.name === name).data)
  const all = vec("climograph-station-all-layers")
  const barsOnly = climograph.layout({ ...all, show: ["bars"] }, { width: 390, fontPx: 20, subject: "geography" })
  const texts = barsOnly.labels.map((l) => l.text_it)
  assert.ok(texts.includes("mm") && !texts.includes("°C"), "only the rain axis")
  assert.ok(!barsOnly.shapes.some((s) => s.cls?.includes("dgc-line")))
  assert.deepEqual(barsOnly.values.header, ["", "Pioggia (mm)"])
  const reading = vec("climograph-inline-read-cursor")
  const cursor = climograph.layout(reading, { width: 390, fontPx: 20, subject: "geography", controls: { month: 3 }, mode: "student" })
  assert.equal(cursor.live, "Marzo: pioggia 169 millimetri, temperatura 21,4 gradi.")
  const noCursor = climograph.layout(reading, { width: 390, fontPx: 20, subject: "geography", controls: { month: 3 }, mode: "print" })
  assert.equal(noCursor.live, undefined)
  assert.deepEqual(climograph.controls(reading).map((c) => c.id), ["month"])
  assert.deepEqual(climograph.controls(all), [])
  const select = climograph.layout(all, { width: 390, fontPx: 20, subject: "geography", mode: "select" })
  assert.ok(!select.shapes.some((s) => s.cls?.includes("dgc-arid")), "no hatch in a select figure")
  assert.ok(!select.labels.some((l) => /caldo|Escursione|cadono/.test(l.text_it)), "no computed line in a select figure")
  assert.equal(select.shapes.filter((s) => s.target).length, 12)
  assert.equal(new Set(select.shapes.filter((s) => s.target).map((s) => s.cls)).size, 1, "every candidate has the same style")
  const arid = climograph.layout(all, { width: 390, fontPx: 20, subject: "geography" })
  assert.equal(arid.shapes.filter((s) => s.cls?.includes("dgc-arid") && s.pattern === "hatch" && s.key?.startsWith("arid")).length, 5, "Brasília: five arid months, May to September")
  assert.match(climograph.describe(all), /Mesi aridi, con la barra sotto la linea: da maggio a settembre/)
})
