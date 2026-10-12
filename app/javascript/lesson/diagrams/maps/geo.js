// The shared geometry, data and wording of the maps family (T5, W2-1, D-272): the vendored bases (public/vendor/banco-maps@1) and the
// name tables, ids resolved per base, the units a detail draws, reading order, compass words, and the numbers and words that map,
// insolation and cross_section print. The Ruby twins are lib/maps/base.rb and lib/lessons/diagrams/geo_format.rb; both are run by
// test/fixtures/diagrams/types/{map,insolation,cross_section}.json. Pure, except that the assets are loaded once by `prepare`.
import * as N from "lesson/num"
import { project } from "lesson/lib/map_projection"

export const SETS = ["areas", "places", "bands", "lines", "points"]
export const TOO_SMALL = 45 // viewBox units: the default candidates of an `areas` set are at least this wide and high

// ---- assets -------------------------------------------------------------------------------------------------------------

const assets = { bases: new Map(), tables: null }

// How a base module is read. The page imports it from /vendor (served as it is, with its SHA256SUMS); the tests set a loader of their own.
let loader = (name) => import(/* @vite-ignore */ `/vendor/banco-maps@1/${name}.js`)
export function setBaseLoader(fn) {
  loader = fn
  assets.bases.clear()
}

// The name tables come from the app's own data modules and are loaded only when a figure draws names: never for a select figure (L3).
let tableLoader = async () => ({
  names: (await import("lesson/data/geo-names")).default.names,
  places: (await import("lesson/data/history-places")).default.places,
  regions: (await import("lesson/data/history-regions")).default.regions
})
export function setTableLoader(fn) {
  tableLoader = fn
  assets.tables = null
}

// Loads what a figure of base +name+ needs: its base and the name tables, or, for a select figure (names false), its select plate only:
// the same geometry with opaque keys in place of every gazetteer id, and no name table (L3: nothing the page loads says which shape is which).
export async function prepare(name, { names = true } = {}) {
  const key = names ? name : `select/${name}`
  if (!assets.bases.has(key)) assets.bases.set(key, (await loader(key)).default)
  if (names && !assets.tables) assets.tables = await tableLoader()
}

export const baseOf = (name, select = false) => assets.bases.get(select ? `select/${name}` : name) ?? null
export const tablesLoaded = () => assets.tables !== null

// The name of an id, read from the table the base declares for the collection ("geo/names", "history/places", "history/regions").
export function nameOf(doc, collection, id) {
  const table = doc.reads?.[collection]
  const t = assets.tables
  if (!t) return null
  const row = table === "geo/names" ? t.names[id] : table === "history/places" ? t.places[id] : table === "history/regions" ? t.regions[id] : null
  return row?.name_it ?? null
}

// ---- the base ---------------------------------------------------------------------------------------------------------------

export const historical = (doc) => doc.detail === "historical"
export const polar = (doc) => doc.projection.type === "lambert_azimuthal"

export function defaultDetail(doc) {
  if (historical(doc)) return null
  return doc.base === "world" ? "continents" : doc.base === "italy" ? "regions" : "states"
}

export function detailsOf(doc) {
  if (historical(doc)) return []
  return doc.base === "italy" ? ["regions", "states"] : ["continents", "states"]
}

// [x0, y0, x1, y1] of a path of M and l commands (the format of the bases), or null.
export function boxOf(path) {
  let x = 0
  let y = 0
  let x0 = Infinity
  let y0 = Infinity
  let x1 = -Infinity
  let y1 = -Infinity
  let cmd = null
  let nums = []
  const add = () => {
    x0 = Math.min(x0, x)
    x1 = Math.max(x1, x)
    y0 = Math.min(y0, y)
    y1 = Math.max(y1, y)
  }
  const flush = () => {
    if (cmd === "M") {
      for (let i = 0; i + 1 < nums.length; i += 2) {
        x = nums[i]
        y = nums[i + 1]
        add()
      }
    } else if (cmd === "l") {
      for (let i = 0; i + 1 < nums.length; i += 2) {
        x += nums[i]
        y += nums[i + 1]
        add()
      }
    }
    nums = []
  }
  for (const tok of String(path ?? "").match(/[Mlz]|-?\d*\.?\d+/g) ?? []) {
    if (/^[Mlz]$/.test(tok)) {
      flush()
      cmd = tok
    } else nums.push(Number(tok))
  }
  flush()
  return x0 === Infinity ? null : [x0, y0, x1, y1]
}

const areaUnit = (a, target) => ({ id: a.id, kind: a.kind, members: [a.id], anchor: a.anchor, bbox: a.bbox, target })

function groupUnit(g, byId, target) {
  const boxes = g.members.map((m) => byId.get(m)?.bbox).filter(Boolean)
  const bbox = g.bbox ?? [Math.min(...boxes.map((b) => b[0])), Math.min(...boxes.map((b) => b[1])), Math.max(...boxes.map((b) => b[2])), Math.max(...boxes.map((b) => b[3]))]
  return { id: g.id, kind: g.kind, members: g.members, anchor: g.anchor, bbox, target }
}

const unitCache = new WeakMap()

// The units a figure of detail +detail+ draws and can pick. A unit with target false is context (a neighbour on the regions of Italy).
export function units(doc, detail) {
  const cache = unitCache.get(doc) ?? new Map()
  unitCache.set(doc, cache)
  const key = detail ?? ""
  if (cache.has(key)) return cache.get(key)
  const byId = new Map(doc.areas.map((a) => [a.id, a]))
  let out = []
  if (historical(doc)) out = doc.areas.map((a) => ({ id: a.id, kind: "region", members: [a.id], anchor: a.anchor, bbox: a.bbox, target: true }))
  else {
    const groups = doc.groups ?? []
    if (detail === "continents") {
      for (const g of groups.filter((x) => x.kind === "continent")) out.push(groupUnit(g, byId, true))
      const covered = new Set(out.flatMap((u) => u.members))
      for (const a of doc.areas.filter((x) => !covered.has(x.id))) out.push(areaUnit(a, false))
    } else if (detail === "regions") {
      for (const a of doc.areas) out.push(areaUnit(a, a.kind === "region"))
    } else {
      const merged = groups.filter((g) => g.kind === "country")
      const hidden = new Set(merged.flatMap((g) => g.members))
      for (const a of doc.areas.filter((x) => !hidden.has(x.id))) out.push(areaUnit(a, a.kind !== "region"))
      for (const g of merged) out.push(groupUnit(g, byId, true))
    }
  }
  cache.set(key, out)
  return out
}

// The unit named by +id+ at +detail+, or the group of that id (drawn as its members, never a candidate), or null.
export function resolveArea(doc, detail, id) {
  const found = units(doc, detail).find((u) => u.id === id)
  if (found) return found
  const g = (doc.groups ?? []).find((x) => x.id === id)
  return g ? groupUnit(g, new Map(doc.areas.map((a) => [a.id, a])), false) : null
}

export const placeOf = (doc, id) => doc.places.find((p) => p.id === id) ?? null
export const lineOf = (doc, id) => (doc.lines ?? []).find((l) => l.id === id) ?? null

// [x, y] in the base's viewBox of a latitude and a longitude (degrees as floats).
export const projectOf = (doc, lat, lon) => project(doc.projection, lon, lat)

export function compass(doc, x, y) {
  const w = doc.viewBox[2]
  const h = doc.viewBox[3]
  const col = x < w / 3 ? 0 : x > (w * 2) / 3 ? 2 : 1
  const row = y < h / 3 ? 0 : y > (h * 2) / 3 ? 2 : 1
  if (polar(doc)) {
    const v = ["in alto", null, "in basso"][row]
    const hz = ["a sinistra", null, "a destra"][col]
    if (v === null && hz === null) return "al centro"
    return [v, hz].filter(Boolean).join(" ")
  }
  return [["a nord-ovest", "a nord", "a nord-est"], ["a ovest", "al centro", "a est"], ["a sud-ovest", "a sud", "a sud-est"]][row][col]
}

// Reading order of the targets: north to south (rows of one viewBox unit), then west to east, then the id.
export const readingKey = (x, y, tie) => [Math.floor(y + 0.5), Math.floor(x + 0.5), String(tie)]
export function byReading(a, b) {
  const ka = readingKey(a.x, a.y, a.id)
  const kb = readingKey(b.x, b.y, b.id)
  return ka[0] - kb[0] || ka[1] - kb[1] || (ka[2] < kb[2] ? -1 : ka[2] > kb[2] ? 1 : 0)
}

// ---- numbers and words ----------------------------------------------------------------------------------------------------

export const num = (text) => N.parse(text)
export const flt = (text) => {
  const v = N.parse(text)
  return v === null ? null : N.toNumber(v)
}

export const fmt = (r) => N.format(r)

// r rounded half away from zero to one decimal, with a comma: "1,2", "26,0"; trim drops a final ",0".
export function fmt1(r, { trim = false } = {}) {
  const neg = r.n < 0n
  const abs = (neg ? -r.n : r.n) * 10n
  let q = abs / r.d
  if (2n * (abs % r.d) >= r.d) q += 1n
  const whole = q / 10n
  const frac = q % 10n
  const sign = neg && q !== 0n ? "−" : ""
  return trim && frac === 0n ? `${sign}${whole}` : `${sign}${whole},${frac}`
}

// A positive float rounded half up to one decimal, with a comma (a spread, never a stored value).
export function fmt1f(v) {
  const tenths = Math.floor(v * 10 + 0.5)
  return `${Math.floor(tenths / 10)},${tenths % 10}`
}

const absOf = (r) => N.make(r.n < 0n ? -r.n : r.n, r.d)
function deg(r, positive, negative) {
  if (N.isZero(r)) return "0°"
  return `${fmt(absOf(r))}° ${r.n > 0n ? positive : negative}`
}
export const latWord = (r) => deg(r, "nord", "sud")
export const lonWord = (r) => deg(r, "est", "ovest")
export const yearWord = (y) => (y < 0 ? `${-y} a.C.` : `${y} d.C.`)
export const capital = (text) => (text ? text.charAt(0).toUpperCase() + text.slice(1) : "")
export { listIt } from "lesson/diagrams/common"

export const PATTERNS = ["solid", "hatch", "dots", "cross", "grid"]

// The pattern of item +index+: the author's, else by the order of the distinct roles of the list (colour is never alone, A4).
export function patternOf(items, index) {
  if (items[index].pattern) return items[index].pattern
  const roles = []
  for (const h of items) if (!roles.includes(h.role ?? "muted")) roles.push(h.role ?? "muted")
  return PATTERNS[roles.indexOf(items[index].role ?? "muted") % PATTERNS.length]
}

// The effective state i of a figure (the top level overlaid by states[i]; no states member).
export function effective(data, i) {
  const { states, ...top } = data
  if (!Array.isArray(states) || states.length === 0) return top
  return { ...top, ...states[Math.min(i, states.length - 1)] }
}

export const hasStates = (data) => Array.isArray(data.states) && data.states.length > 0

// A year as an integer, the years of a slider without year 0.
export const yearList = (sl) => {
  const out = []
  for (let y = Number(sl.from); y <= Number(sl.to); y++) if (y !== 0) out.push(y)
  return out
}
