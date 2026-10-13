// D-293: the figure fits its box at every width. Maps (the ancient base and the modern ones) and the climograph, laid out with a browser-like
// measure (wider than the node estimate: the compass words are bold): every label is inside the figure, no two labels overlap, the map
// scales to its box (a viewBox, no fixed pixel stage), and a climograph never draws more tick labels than its height can hold.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { pathToFileURL } from "node:url"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const G = await import("lesson/diagrams/maps/geo")
const map = await import("lesson/diagrams/maps/map")
const climograph = await import("lesson/diagrams/chart/climograph")
G.setBaseLoader((name) => import(pathToFileURL(new URL(`public/vendor/banco-maps@1/${name}.js`, root).pathname).href))
const stations = (await import("lesson/data/geo-stations")).default.stations
const read = (path) => JSON.parse(readFileSync(new URL(path, root), "utf8"))

// bold Atkinson-like text is about 0.62 em per character, wider than the estimator: a layout that fits this fits the browser
const measure = (text, px, maxW) => {
  const w = Math.ceil(String(text).length * px * 0.62)
  if (!maxW || w <= maxW) return { w, h: Math.ceil(px * 1.4) }
  const lines = Math.ceil(w / maxW)
  return { w: maxW, h: Math.ceil(px * 1.4) * lines }
}
const WIDTHS = [320, 390, 768, 1280, 1366]
const overlap = (a, b) => Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x) > 2 && Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y) > 2
const labelOverlaps = (labels) => {
  const out = []
  for (let i = 0; i < labels.length; i++) for (let j = i + 1; j < labels.length; j++) if (overlap(labels[i], labels[j])) out.push(`"${labels[i].text_it}" and "${labels[j].text_it}"`)
  return out
}

const mapDoc = read("test/fixtures/diagrams/types/map.json")
const goodMaps = mapDoc.vectors.filter((v) => v.semantic === "ok" && v.schema !== "invalid" && v.layout === "ok" && !v.name.includes("unknown-field"))

for (const v of goodMaps) {
  test(`${v.name}: labels inside the figure, none overlapping, the map scales to the box at 320 to 1366 px`, async () => {
    await map.prepare(v.data, {})
    const states = Array.isArray(v.data.states) && v.data.states.length > 0 ? v.data.states.length : 1
    for (const width of WIDTHS) {
      for (const fontPx of [20, 26]) {
        for (let state = 0; state < states; state++) {
          const scene = map.layout(v.data, { width, fontPx, measure, subject: v.subject, state })
          assert.ok(!scene.error, `${width}/${fontPx}: ${scene.error?.message}`)
          assert.equal(scene.width, width, "the scene is as wide as its box")
          for (const l of scene.labels) assert.ok(l.x >= -0.5 && l.x + l.w <= width + 0.5, `${width}/${fontPx}: "${l.text_it}" is outside the figure (${l.x}..${l.x + l.w})`)
          assert.deepEqual(labelOverlaps(scene.labels), [], `${width}/${fontPx}/${state}`)
          for (const l of scene.labels) assert.ok(l.px >= fontPx, "never under the reading size")
          const group = scene.shapes.find((s) => s.kind === "group" && s.cls === "dg-mapgroup")
          if (group && width <= 420) assert.ok(1000 * group.scale >= 0.55 * width, `${width}: the map is not tiny (${Math.round(1000 * group.scale)} px of ${width})`)
          if (group) assert.ok(group.at[0] + 1000 * group.scale <= width + 1, "the frame is inside the box")
        }
      }
    }
  })
}

test("the compass row of a map (Ovest, Nord, Est) sits inside the box at every width", async () => {
  const v = goodMaps.find((x) => x.name === "map-ancient-slider")
  await map.prepare(v.data, {})
  for (const width of WIDTHS) {
    const scene = map.layout(v.data, { width, fontPx: 20, measure, subject: v.subject, state: 0 })
    for (const word of ["Ovest", "Nord", "Est"]) {
      const l = scene.labels.find((x) => x.text_it === word)
      assert.ok(l, `${word} at ${width}`)
      assert.ok(l.x >= 0 && l.x + l.w <= width, `${word} at ${width}: ${l.x}..${l.x + l.w}`)
    }
  }
})

const climoDoc = read("test/fixtures/diagrams/types/climograph.json")
const resolve = (data) => {
  const row = (ref) => stations[ref.split(".")[1]]
  let out = data
  if (data.station && row(data.station)) {
    const r = row(data.station)
    out = { ...data, temp: r.temp, precip: r.precip, lat: r.lat, alt_m: r.alt_m, place_it: data.place_it ?? `${r.name_it} (${r.country_it})`, source_it: data.source_it ?? "Medie 1991-2020" }
  }
  if (data.compare?.station && row(data.compare.station)) {
    const r = row(data.compare.station)
    out = { ...out, compare: { ...data.compare, temp: r.temp, place_it: data.compare.place_it ?? `${r.name_it} (${r.country_it})` } }
  }
  return out
}
const goodClimo = climoDoc.vectors.filter((v) => v.semantic === "ok" && v.schema !== "invalid" && v.layout === "ok")

for (const v of goodClimo) {
  test(`${v.name}: the tick labels of both axes are legible at 320 and 390 px (no overlap, few enough for the height)`, () => {
    const data = resolve(v.data)
    for (const width of [320, 390, 1280]) {
      for (const fontPx of [20, 26]) {
        const scene = climograph.layout(data, { width, fontPx, measure, subject: v.subject ?? "geography", state: 0 })
        assert.ok(!scene.error, scene.error?.message)
        assert.deepEqual(labelOverlaps(scene.labels), [], `${width}/${fontPx}`)
        for (const l of scene.labels) assert.ok(l.x >= -0.5 && l.x + l.w <= width + 0.5, `${width}/${fontPx}: "${l.text_it}" outside`)
        // the numeric tick labels, per side of the plot, never more than the height holds
        const ticks = scene.labels.filter((l) => /^\d+$/.test(l.text_it))
        const rowH = Math.ceil(fontPx * 1.4)
        for (const side of [(l) => l.anchor === "end" || l.anchor === "middle", (l) => l.anchor === "start"]) {
          const mine = ticks.filter(side)
          if (mine.length) assert.ok(mine.length * rowH <= scene.height, `${width}/${fontPx}: ${mine.length} tick labels in ${scene.height} px`)
        }
      }
    }
  })
}
