// A map figure waits for its base (T5, D-272): a base that is served late (a busy machine, a render check under load) is no reason for
// «the base X is not loaded». preloadFor fetches every base a lesson's map figures name before the first card; a figure that is drawn
// meanwhile (a relayout, a resize) waits for it instead of failing; a base that does not exist still says so.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { pathToFileURL } from "node:url"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const G = await import("lesson/diagrams/maps/geo")
const map = await import("lesson/diagrams/maps/map")
const { preloadFor, usedBy } = await import("lesson/preload")

const vector = JSON.parse(readFileSync(new URL("test/fixtures/diagrams/types/map.json", root), "utf8")).vectors.find((v) => v.name === "map-world-continents")
const data = vector.data
const fromDisk = (name) => import(pathToFileURL(new URL(`public/vendor/banco-maps@1/${name}.js`, root).pathname).href)
const late = (ms) => (name) => new Promise((resolve) => setTimeout(resolve, ms)).then(() => fromDisk(name))
const opts = { width: 390, fontPx: 20, subject: "geography", state: 0 }

test("laid out before the base arrives, the figure says the base is not loaded; once awaited it draws", async () => {
  G.setBaseLoader(late(80))
  assert.equal(map.layout(data, opts).error.message, `the base ${data.base} is not loaded`)
  const waiting = map.prepare(data, {})
  assert.equal(G.baseOf(data.base), null, "the fetch is still on its way")
  await waiting
  assert.ok(G.baseOf(data.base))
  const scene = map.layout(data, opts)
  assert.ok(!scene.error, scene.error?.message)
})

test("preloadFor awaits the base of every map figure of the lesson, and of a select check, before the first card", async () => {
  G.setBaseLoader(late(60))
  const body = {
    subject: "geography",
    cards: [{ blocks: [{ type: "diagram", diagram: data }, { type: "check", component: "select", diagram: { type: "map", base: "italy", alt_it: "x" }, targets: [] }] }]
  }
  const { figures } = usedBy(body)
  assert.deepEqual(figures.map((f) => [f.data.base, f.mode]), [["world", "student"], ["italy", "select"]])
  assert.equal(G.baseOf("world"), null)
  await preloadFor(body)
  assert.ok(G.baseOf("world") && G.tablesLoaded(), "the base and the names of the figure are loaded")
  assert.ok(G.baseOf("italy", true), "the select plate of the select check is loaded")
})

test("a base that does not exist still fails, and preloadFor does not stop on it", async () => {
  G.setBaseLoader(fromDisk)
  await preloadFor({ cards: [{ blocks: [{ type: "diagram", diagram: { ...data, base: "atlantide" } }] }] })
  assert.equal(G.baseOf("atlantide"), null)
  const result = map.layout({ ...data, base: "atlantide" }, opts)
  assert.ok(result.error)
})

// ---- the figure itself: draw.js keeps its hands off the layout until the base is there ---------------------------------------------

// A stand-in for the document that takes anything (the figure only has to reach `layout`, not to paint): a node that accepts every call.
const node = (tag = "div") => {
  const own = { tag, children: [], attrs: {}, dataset: {}, style: {}, classList: { add() {}, remove() {}, toggle() {}, contains: () => false } }
  return new Proxy(own, {
    get(target, key) {
      if (key in target) return target[key]
      if (key === "clientWidth" || key === "clientHeight" || key === "offsetWidth") return 390
      if (key === "querySelector" || key === "closest") return () => null
      if (key === "querySelectorAll") return () => []
      if (key === "getBoundingClientRect") return () => ({ left: 0, top: 0, right: 390, bottom: 20, width: 390, height: 20 })
      if (key === "firstChild" || key === "parentNode") return null
      if (key === "setAttribute") return (name, value) => { target.attrs[name] = value }
      if (key === "getAttribute") return (name) => target.attrs[name] ?? null
      if (key === "appendChild" || key === "insertBefore" || key === "append") return (...n) => { target.children.push(...n); return n[0] }
      return () => undefined
    },
    set(target, key, value) { target[key] = value; return true }
  })
}

test("a figure relaid out while its base is on the way waits, then draws once, with no error", async () => {
  globalThis.document = { createElement: node, createElementNS: (_ns, tag) => node(tag), createTextNode: (text) => ({ nodeType: 3, textContent: String(text) }), createDocumentFragment: () => node("#fragment"), fonts: undefined }
  globalThis.window = { addEventListener() {}, removeEventListener() {}, matchMedia: () => ({ matches: false }) }
  try {
    G.setBaseLoader(late(80))
    const { mountDiagram } = await import("lesson/diagrams/draw")
    const t = new Proxy({}, { get: (_t, key) => String(key) })
    const api = mountDiagram(data, { subject: "geography", t, fontPx: () => 20, reduced: () => true, mount() {}, track() {} }, {})
    api.mounted()
    api.relayout() // what renderAll does at once
    api.setState(0)
    assert.equal(api.element.dataset.error, undefined, "no error while the base is on the way")
    assert.equal(api.element.dataset.drawn, undefined, "nothing is drawn yet")
    await api.settled
    assert.equal(api.element.dataset.drawn, "1", "drawn once, after the base")
    // the stand-in cannot measure a label, so the layout may refuse the text; it must not say that the base is missing
    assert.doesNotMatch(api.element.dataset.error ?? "", /not loaded/)
  } finally {
    delete globalThis.document
    delete globalThis.window
  }
})
