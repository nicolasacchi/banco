// map (T5, W2-1, D-272): one type, a registry of vendored bases (public/vendor/banco-maps@1). The author writes gazetteer ids, never
// coordinates on a historical base; the base says where everything is. Ruby twin: lib/lessons/diagrams/map.rb; both run
// test/fixtures/diagrams/types/map.json.
//
// Built in W2-1: the modern bases and mediterraneo_antico, detail, graticule, highlight (patterns), bands, places, points (labels),
// lines (a base line, a meridian or a parallel), routes, the year slider with regions_since (historical bases), candidates, states and the
// select targets (areas, places, bands, lines, points). Held back for the map layers of W2-2 and refused with a clear message: arrows,
// proportional circles (points[].value), compare, inset, mercator on a base that is not built in Mercator.
//
// Always drawn by us: "Ovest" and "Est" at the sides and a north arrow (not on the polar bases), the legend list under the map, a pattern
// as well as a colour on every highlighted area, and "Confini approssimativi" on the ancient base. Labels are drawn only when at most 8
// and all fit; otherwise every label is a numbered callout and the legend list names them (A3: never smaller text).
//
// Select mode (L3): the figure of a select check is drawn from the base alone: the targets of ctx.set (the check's `targets`) in one
// neutral style, in reading order t1..tN with a compass phrase, no label, no role, no pattern, no highlight, and no name table loaded.
import schema from "lesson/diagram_schemas/map"
import * as N from "lesson/num"
import * as G from "lesson/diagrams/maps/geo"
import { fail, finish, label, labelNear, listIt, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const type = "map"
export { schema }

const HELD_BACK = ["compare", "inset"]
const GRATICULE = { equator: "l'equatore", tropics: "i tropici", polar_circles: "i circoli polari", greenwich: "il meridiano di Greenwich" }
const LABELS_DRAWN = 8 // validation_rules lesson2.types.map.labels_drawn
const STEP = 2 // degrees between the samples of a parallel or a meridian

// Loads the base (and, unless the figure is a select one, the names) before the first layout. The page awaits it; the tests do too.
export const prepare = (data, ctx = {}) => G.prepare(data.base, { names: ctx.mode !== "select" })

// ---- semantic checks (the mirror of Lessons::Diagrams::Map.static) ----------------------------------------------------------

export function semanticAll(data) {
  const doc = G.baseOf(data.base)
  if (!doc) return [{ path: "/base", message: `the base ${data.base} is not loaded`, code: "E-DIAGRAM-LAYOUT" }]
  const out = []
  const add = (path, message) => out.push({ path, message })
  const hist = G.historical(doc)
  const detail = data.detail ?? G.defaultDetail(doc)
  if (data.detail) {
    if (hist) add("/detail", `the base ${data.base} has no detail: its regions are the historical ones`)
    else if (!G.detailsOf(doc).includes(data.detail)) add("/detail", `the base ${data.base} has the details ${G.detailsOf(doc).join(", ")}, not ${data.detail}`)
  }
  if (data.mercator && !hist) add("/mercator", "mercator: true needs a base built in Mercator (the bases are built once): only mediterraneo_antico is")
  for (const k of HELD_BACK) if (k in data) add(`/${k}`, `${k} arrives with the map layers (W2-2): it is not available yet`)
  ;(data.graticule ?? []).forEach((g, i) => {
    const v = doc.graticule?.[g]
    const drawn = Array.isArray(v) ? v.length > 0 : v !== undefined && v !== null && v !== ""
    if (!drawn) add(`/graticule/${i}`, `the base ${data.base} does not draw ${g}`)
  })
  const cands = data.candidates ?? []
  cands.forEach((id, i) => {
    if (!G.units(doc, detail).some((u) => u.id === id && u.target)) add(`/candidates/${i}`, `${id} is not an area you can pick on ${data.base} at the detail ${detail ?? "historical"}`)
  })
  if (new Set(cands).size !== cands.length) add("/candidates", "a candidate is listed twice")
  layers(data, add, "", doc, hist, detail)
  ;(data.states ?? []).forEach((s, i) => {
    if (s && typeof s === "object") layers(s, add, `/states/${i}`, doc, hist, detail)
  })
  return out
}

export const semantic = (data) => semanticAll(data)[0] ?? null

const lab = (add, path, text) => {
  if (text !== undefined && words(text) > 6) add(path, `a label has ${words(text)} words (at most 6)`)
}

function layers(src, add, path, doc, hist, detail) {
  const hl = src.highlight ?? []
  hl.forEach((h, i) => {
    if (!G.resolveArea(doc, detail, h.id)) add(`${path}/highlight/${i}/id`, `${h.id} is not an area of ${doc.base} at the detail ${detail ?? "historical"}`)
  })
  if (new Set(hl.map((h) => h.id)).size !== hl.length) add(`${path}/highlight`, "an area is highlighted twice")
  ;(src.bands ?? []).forEach((b, i) => checkBand(b, add, `${path}/bands/${i}`, doc, hist))
  const seen = []
  ;(src.places ?? []).forEach((p, i) => {
    const at = `${path}/places/${i}/id`
    if (!G.placeOf(doc, p.id)) add(at, `${p.id} is not a place of ${doc.base}`)
    if (seen.includes(p.id)) add(at, `the place ${p.id} is listed twice`)
    seen.push(p.id)
  })
  ;(src.points ?? []).forEach((p, i) => checkPoint(p, add, `${path}/points/${i}`, doc, hist))
  ;(src.lines ?? []).forEach((l, i) => checkLine(l, add, `${path}/lines/${i}`, doc, hist))
  ;(src.routes ?? []).forEach((r, i) => {
    const at = `${path}/routes/${i}`
    ;(r.via ?? []).forEach((id, j) => {
      if (!G.placeOf(doc, id) && !G.resolveArea(doc, detail, id)) add(`${at}/via/${j}`, `${id} is neither a place nor an area of ${doc.base}`)
    })
    lab(add, `${at}/label_it`, r.label_it)
  })
  if (Array.isArray(src.arrows) && src.arrows.length > 0) add(`${path}/arrows`, "arrows arrive with the map layers (W2-2): it is not available yet")
  slider(src, add, path, doc, hist)
}

function checkBand(b, add, at, doc, hist) {
  if (hist) return add(at, `agents never write coordinates on a historical base: no bands on ${doc.base}`)
  const from = N.parse(b.from_lat)
  const to = N.parse(b.to_lat)
  if (from && to) {
    if (!(N.compare(from, to) < 0 && N.compare(from, N.int(-90)) >= 0 && N.compare(to, N.int(90)) <= 0)) add(at, "a band goes from a smaller to a larger latitude, between -90 and 90")
    const lo = doc.box[1]
    const hi = doc.box[3]
    if (N.toNumber(to) < lo || N.toNumber(from) > hi) add(at, `the band lies outside the base's window (${lo}° to ${hi}°)`)
  }
  lab(add, `${at}/label_it`, b.label_it)
}

function checkPoint(p, add, at, doc, hist) {
  if (hist) return add(at, `agents never write coordinates on a historical base: no points on ${doc.base}`)
  if ("value" in p) add(`${at}/value`, "proportional circles (value) arrive with the map layers (W2-2): not available yet")
  const lat = G.flt(p.lat)
  const lon = G.flt(p.lon)
  const [w, s, e, n] = doc.box
  if (lat !== null && lon !== null && !(lat >= s && lat <= n && lon >= w && lon <= e)) add(at, `the point (${p.lat}, ${p.lon}) is outside the base's window (lat ${s} to ${n}, lon ${w} to ${e})`)
  lab(add, `${at}/label_it`, p.label_it)
}

function checkLine(l, add, at, doc, hist) {
  if (l.id && l.kind) add(at, "a line is a base line (id) or a meridian or a parallel (kind), not both")
  else if (l.id) {
    if (!G.lineOf(doc, l.id)) add(`${at}/id`, `${l.id} is not a line of ${doc.base}`)
  } else if (l.kind === "meridian" || l.kind === "parallel") {
    if (hist) return add(at, `agents never write coordinates on a historical base: no ${l.kind}s on ${doc.base}`)
    const key = l.kind === "meridian" ? "lon" : "lat"
    const v = G.flt(l[key])
    const [lo, hi] = l.kind === "meridian" ? [doc.box[0], doc.box[2]] : [doc.box[1], doc.box[3]]
    if (!(v !== null && v >= lo && v <= hi)) add(`${at}/${key}`, `a ${l.kind} needs ${key}, inside the base's window (${lo} to ${hi})`)
  } else add(at, "a line is a base line (id) or a meridian or a parallel (kind)")
  lab(add, `${at}/label_it`, l.label_it)
}

function slider(src, add, path, doc, hist) {
  const sl = src.slider
  const rs = src.regions_since ?? []
  if (sl && !hist) add(`${path}/slider`, "the year slider is for the historical bases")
  if (rs.length > 0 && !hist) add(`${path}/regions_since`, "regions_since is for the historical bases")
  if (rs.length > 0 && !sl) add(`${path}/regions_since`, "regions_since needs the year slider (from and to)")
  if (hist) {
    rs.forEach((r, i) => {
      if (!G.resolveArea(doc, null, r.id)) add(`${path}/regions_since/${i}/id`, `${r.id} is not a region of ${doc.base}`)
    })
  }
  if (!sl || !hist) return
  const from = Number(sl.from)
  const to = Number(sl.to)
  if (from > to) add(`${path}/slider`, "the slider goes from an earlier to a later year (or is one year: from equal to to)")
  if (from < 0 && to > 0) add(`${path}/slider`, "the slider stays inside one era (there is no year 0)")
  if (to - from > 500) add(`${path}/slider`, "the slider spans at most 500 years")
  rs.forEach((r, i) => {
    if (Number(r.since) > to) add(`${path}/regions_since/${i}/since`, `the year ${r.since} is after the end of the slider (${sl.to}): the region would never appear`)
  })
}

// ---- the view of one state (what is drawn, resolved) ------------------------------------------------------------------------

// The year a figure shows in state +eff+: the control's value inside the slider's range, or the slider's start; null without slider.
export function yearOf(eff, controls) {
  const sl = eff.slider
  if (!sl) return null
  const from = Number(sl.from)
  const to = Number(sl.to)
  const y = controls?.year !== undefined ? Number(controls.year) : from
  return Math.min(Math.max(y, from), to)
}

const nm = (doc, collection, id) => G.nameOf(doc, collection, id) ?? id

export function view(data, eff, year) {
  const doc = G.baseOf(data.base)
  const hlIn = eff.highlight ?? []
  const sinceIn = year === null ? [] : (eff.regions_since ?? []).filter((r) => Number(r.since) <= year)
  const bandsIn = eff.bands ?? []
  const withPattern = (items) => items.map((h, i) => ({ id: h.id, name: nm(doc, "areas", h.id), role: h.role ?? "muted", pattern: G.patternOf(items, i) }))
  return {
    doc,
    title: doc.title_it,
    approximate: doc.approximate === true,
    polar: G.polar(doc),
    graticule: eff.graticule ?? [],
    highlight: withPattern(hlIn),
    since: withPattern(sinceIn),
    places: (eff.places ?? []).map((p) => ({ id: p.id, name: nm(doc, "places", p.id) })),
    points: (eff.points ?? []).map((p) => ({ lat: p.lat, lon: p.lon, label: p.label_it })),
    bands: bandsIn.map((b, i) => ({ from: b.from_lat, to: b.to_lat, label: b.label_it, role: b.role ?? "muted", pattern: G.patternOf(bandsIn, i) })),
    lines: (eff.lines ?? []).map((l) => lineView(doc, l)),
    routes: (eff.routes ?? []).map((r) => ({
      label: r.label_it,
      role: r.role ?? "muted",
      via: r.via.map((id) => ({ id, name: G.placeOf(doc, id) ? nm(doc, "places", id) : nm(doc, "areas", id) }))
    })),
    year,
    op: eff.op_it
  }
}

function lineView(doc, l) {
  if (l.id) return { kind: "id", key: l.id, name: l.label_it ?? nm(doc, "lines", l.id) }
  if (l.kind === "meridian") return { kind: "meridian", key: `meridian:${l.lon}`, name: l.label_it, lon: l.lon }
  return { kind: "parallel", key: `parallel:${l.lat}`, name: l.label_it, lat: l.lat }
}

// ---- describe and printed (the mirror of the Ruby words) ----------------------------------------------------------------------

const latW = (text) => G.latWord(N.parse(text))
const lonW = (text) => G.lonWord(N.parse(text))

export function describe(data, ctx = {}) {
  const eff = G.effective(data, ctx.state ?? 0)
  if (ctx.mode === "select") return describeSelect(data, eff, ctx)
  const v = view(data, eff, yearOf(eff, ctx.controls))
  const out = [`Carta: ${v.title}.`]
  if (v.approximate) out.push("Confini approssimativi.")
  out.push(v.polar ? "Il polo è al centro della carta." : "Il nord è in alto, l'ovest a sinistra e l'est a destra.")
  if (v.graticule.length) out.push(`Si vedono: ${listIt(v.graticule.map((g) => GRATICULE[g]))}.`)
  if (v.highlight.length) out.push(`In evidenza: ${listIt(v.highlight.map((h) => h.name))}.`)
  if (v.year !== null) out.push(v.since.length === 0 ? `Nel ${G.yearWord(v.year)}.` : `Nel ${G.yearWord(v.year)} in evidenza: ${listIt(v.since.map((h) => h.name))}.`)
  for (const b of v.bands) out.push(`${G.capital(b.label ?? "fascia")}, da ${latW(b.from)} a ${latW(b.to)}.`)
  if (v.places.length) out.push(`Luoghi: ${listIt(v.places.map((p) => p.name))}.`)
  for (const p of v.points) out.push(`${p.label ?? "Un punto"}: ${latW(p.lat)}, ${lonW(p.lon)}.`)
  for (const l of v.lines) {
    if (l.kind === "id") out.push(`Linea: ${l.name}.`)
    else if (l.kind === "meridian") out.push(`Meridiano ${lonW(l.lon)}${l.name ? `: ${l.name}` : ""}.`)
    else out.push(`Parallelo ${latW(l.lat)}${l.name ? `: ${l.name}` : ""}.`)
  }
  for (const r of v.routes) out.push(`Percorso${r.label ? ` (${r.label})` : ""}: ${listIt(r.via.map((x) => x.name))}.`)
  if (v.op) out.push(`${v.op}.`)
  return out.join(" ")
}

function setOf(data, eff, ctx) {
  if (ctx?.set && G.SETS.includes(ctx.set)) return ctx.set
  return G.SETS.find((s) => targetList(data, eff, s).length > 0) ?? "areas"
}

const SET_WORDS = { areas: "zone", places: "luoghi", bands: "fasce", lines: "linee", points: "punti" }

function describeSelect(data, eff, ctx) {
  const set = setOf(data, eff, ctx)
  return `Una carta: ${G.baseOf(data.base).title_it}. Ci sono ${targetList(data, eff, set).length} ${SET_WORDS[set]} da toccare.`
}

const yearsOf = (sl) => (sl && sl.from !== sl.to ? G.yearList(sl) : [sl ? Number(sl.from) : null])

// The strings the state prints (L4): the description at every year of the slider and each name, label, step line and the caption.
export function printed(data, state = 0) {
  const eff = G.effective(data, state)
  const out = []
  for (const y of yearsOf(eff.slider)) {
    const v = view(data, eff, y)
    out.push(describe(data, { state, controls: y === null ? undefined : { year: y } }))
    out.push(...v.highlight.map((h) => h.name), ...v.since.map((h) => h.name), ...v.places.map((p) => p.name))
    out.push(...v.points.map((p) => p.label).filter(Boolean), ...v.bands.map((b) => b.label).filter(Boolean), ...v.lines.map((l) => l.name).filter(Boolean))
    for (const r of v.routes) out.push(...[r.label, ...r.via.map((x) => x.name)].filter(Boolean))
  }
  if (eff.op_it) out.push(eff.op_it)
  if (data.caption_it) out.push(data.caption_it)
  if (G.baseOf(data.base)?.approximate) out.push("Confini approssimativi")
  return [...new Set(out.filter(Boolean))]
}

// The outputs the controls can show within their ranges: a year slider shows each year with the regions it lists (null over the cap).
export function reachable(data) {
  const out = []
  const n = G.hasStates(data) ? data.states.length : 1
  for (let i = 0; i < n; i++) {
    const eff = G.effective(data, i)
    const sl = eff.slider
    if (!sl || sl.from === sl.to) continue
    for (const y of G.yearList(sl)) out.push(G.yearWord(y), ...view(data, eff, y).since.map((h) => h.name))
  }
  const all = [...new Set(out)]
  return all.length > 500 ? null : all
}

// The year slider is the only control of a map besides Avanti (draw.js). Its - and + buttons jump to the next year in which a region
// appears (stops), so that a student does not step through a hundred and thirty years one by one.
export function controls(data, ctx = {}) {
  const eff = G.effective(data, ctx.state ?? 0)
  const sl = eff.slider
  if (!sl || sl.from === sl.to) return []
  const from = Number(sl.from)
  const to = Number(sl.to)
  const stops = [...new Set([from, ...(eff.regions_since ?? []).map((r) => Number(r.since)).filter((y) => y > from && y <= to), to])].sort((a, b) => a - b)
  return [{ id: "year", kind: "slider", range: [from, to], step: 1, stops, label_it: "Anno", format: "year", initial: from }]
}

// A slider prints its first, middle and last year (P1).
export function printViews(data) {
  const n = G.hasStates(data) ? data.states.length : 1
  for (let i = 0; i < n; i++) {
    const sl = G.effective(data, i).slider
    if (!sl || sl.from === sl.to) continue
    const years = G.yearList(sl)
    return [years[0], years[Math.floor(years.length / 2)], years[years.length - 1]].map((y) => ({ state: i, controls: { year: y }, caption_it: G.yearWord(y) }))
  }
  return []
}

// ---- targets ----------------------------------------------------------------------------------------------------------------------

function targetList(data, eff, set) {
  const doc = G.baseOf(data.base)
  const detail = data.detail ?? G.defaultDetail(doc)
  const [w, s, e, n] = doc.box
  const midLon = (w + e) / 2
  const midLat = (s + n) / 2
  switch (set) {
    case "areas": {
      const cands = eff.candidates ?? []
      return G.units(doc, detail)
        .filter((u) => u.target && (cands.length === 0 ? defaultTarget(u) : cands.includes(u.id)))
        .map((u) => ({ id: u.id, x: u.anchor[0], y: u.anchor[1], bbox: u.bbox, unit: u }))
    }
    case "places":
      return (eff.places ?? []).flatMap((p) => {
        const pl = G.placeOf(doc, p.id)
        return pl ? [{ id: p.id, x: pl.x, y: pl.y, bbox: [pl.x, pl.y, pl.x, pl.y] }] : []
      })
    case "bands":
      return (eff.bands ?? []).map((b) => {
        const [x, y] = G.projectOf(doc, (G.flt(b.from_lat) + G.flt(b.to_lat)) / 2, midLon)
        return { id: `lat:${b.from_lat}:${b.to_lat}`, x, y, bbox: boxOfPoints(bandRings(doc, b).flat()), band: b }
      })
    case "lines":
      return (eff.lines ?? []).flatMap((l) => {
        if (l.id) {
          const bx = G.boxOf(G.lineOf(doc, l.id)?.d)
          return bx ? [{ id: l.id, x: (bx[0] + bx[2]) / 2, y: (bx[1] + bx[3]) / 2, bbox: bx, line: l }] : []
        }
        if (l.kind === "meridian") {
          const [x, y] = G.projectOf(doc, midLat, G.flt(l.lon))
          return [{ id: `meridian:${l.lon}`, x, y, bbox: boxOfPoints(linePoints(doc, l)), line: l }]
        }
        const [x, y] = G.projectOf(doc, G.flt(l.lat), midLon)
        return [{ id: `parallel:${l.lat}`, x, y, bbox: boxOfPoints(linePoints(doc, l)), line: l }]
      })
    case "points":
      return (eff.points ?? []).map((p) => {
        const [x, y] = G.projectOf(doc, G.flt(p.lat), G.flt(p.lon))
        return { id: `pt:${p.lat}:${p.lon}`, x, y, bbox: [x, y, x, y] }
      })
    default:
      return []
  }
}

const defaultTarget = (u) => u.bbox[2] - u.bbox[0] >= G.TOO_SMALL && u.bbox[3] - u.bbox[1] >= G.TOO_SMALL

// [{ key: "t1", id, bbox, neutral_it }] of a set in reading order (the Ruby twin gives the ids and the phrases). `id` is for the tests
// and the server: the page keeps the key.
export function targets(data, set) {
  if (!G.SETS.includes(set)) return []
  const doc = G.baseOf(data.base)
  return targetList(data, G.effective(data, 0), set)
    .sort(G.byReading)
    .map((t, i) => ({ key: `t${i + 1}`, id: t.id, bbox: t.bbox, neutral_it: G.compass(doc, t.x, t.y), x: t.x, y: t.y, item: t }))
}

// ---- geometry of bands and lines ------------------------------------------------------------------------------------------------

const clampPt = (doc, [x, y]) => [Math.min(Math.max(x, 0), doc.viewBox[2]), Math.min(Math.max(y, 0), doc.viewBox[3])]
const fix = (v) => Math.round(v * 10) / 10

function boxOfPoints(points) {
  const xs = points.map((p) => p[0])
  const ys = points.map((p) => p[1])
  return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]
}

// The rings of a band: one polygon between two parallels on a map with straight parallels, two circles (an even-odd ring) on a polar one.
function bandRings(doc, b) {
  const from = G.flt(b.from_lat)
  const to = G.flt(b.to_lat)
  const [w, , e] = doc.box
  const lons = []
  for (let lon = w; lon < e; lon += STEP) lons.push(lon)
  lons.push(e)
  const along = (lat) => lons.map((lon) => clampPt(doc, G.projectOf(doc, lat, lon)))
  if (G.polar(doc)) return [along(from), along(to)]
  // the sides follow the window's meridians (curved on Equal Earth), so that the band keeps the outline of the map
  const side = (lon, a, b) => {
    const out = []
    const dir = b > a ? 1 : -1
    for (let lat = a + dir * STEP; dir * (b - lat) > 0; lat += dir * STEP) out.push(clampPt(doc, G.projectOf(doc, lat, lon)))
    return out
  }
  return [[...along(from), ...side(e, from, to), ...along(to).reverse(), ...side(w, to, from)]]
}

const pathOf = (rings) => rings.map((r) => `M${r.map(([x, y]) => `${fix(x)} ${fix(y)}`).join("L")}Z`).join("")

// The polyline of a meridian or a parallel inside the base's window and viewBox.
function linePoints(doc, l) {
  const [w, s, e, n] = doc.box
  const pts = []
  if (l.kind === "meridian") {
    const lon = G.flt(l.lon)
    for (let lat = s; lat < n; lat += STEP) pts.push(G.projectOf(doc, lat, lon))
    pts.push(G.projectOf(doc, n, lon))
  } else {
    const lat = G.flt(l.lat)
    for (let lon = w; lon < e; lon += STEP) pts.push(G.projectOf(doc, lat, lon))
    pts.push(G.projectOf(doc, lat, e))
  }
  return pts.map((p) => clampPt(doc, p))
}

const polyPath = (pts) => `M${pts.map(([x, y]) => `${fix(x)} ${fix(y)}`).join("L")}`

// ---- paths of units ----------------------------------------------------------------------------------------------------------------

const indexes = new WeakMap()
function unitPath(doc, unit) {
  let ix = indexes.get(doc)
  if (!ix) {
    ix = { areas: new Map(doc.areas.map((a) => [a.id, a])), paths: new Map() }
    indexes.set(doc, ix)
  }
  const key = `${unit.id}|${unit.members.length}`
  if (!ix.paths.has(key)) ix.paths.set(key, unit.members.map((m) => ix.areas.get(m)?.d ?? "").join(""))
  return ix.paths.get(key)
}

// ---- layout ----------------------------------------------------------------------------------------------------------------------------

const px = (frame, x) => frame.x + x * frame.k
const py = (frame, y) => frame.y + y * frame.k

// The map fills the width of the figure (a phone has none to spare) unless it is too tall: then it is narrower, centred. "Ovest", "Nord"
// and "Est" are a row under the frame, so that they take no width.
function frameOf(doc, ctx) {
  const H = doc.viewBox[3]
  let k = ctx.width / 1000
  const hmax = Math.min(560, Math.max(300, 1.15 * ctx.width))
  if (H * k > hmax) k = hmax / H
  const w = 1000 * k
  return { x: Math.round((ctx.width - w) / 2), y: 4, k, w, h: H * k }
}

export function layout(data, opts) {
  return run(data, opts, { schema, semantic, build })
}

function build(data, ctx) {
  const doc = G.baseOf(data.base)
  if (!doc) return fail("/base", `the base ${data.base} is not loaded`, "E-DIAGRAM-LAYOUT")
  const select = ctx.mode === "select"
  if (!select && !G.tablesLoaded()) return fail("/base", "the name tables are not loaded", "E-DIAGRAM-LAYOUT")
  const eff = G.effective(data, ctx.state)
  const detail = data.detail ?? G.defaultDetail(doc)
  const frame = frameOf(doc, ctx)
  const year = select ? null : yearOf(eff, ctx.controls)
  const v = select ? null : view(data, eff, year)
  const set = select ? setOf(data, eff, ctx) : null
  const picked = select ? targets(data, set) : []
  const children = []
  const outside = []
  const legend = []
  const items = [] // what carries a label: { kind, text, x, y, role, pattern, swatch }

  // the sea, the land, the water, the graticule, the rivers
  children.push({ kind: "rect", x: 0, y: 0, w: 1000, h: doc.viewBox[3], cls: "dg-sea" })
  if (G.historical(doc)) {
    children.push({ kind: "path", d: doc.land, cls: "dg-land dg-merged" })
    children.push({ kind: "path", d: doc.areas.map((a) => a.d).join(""), cls: "dg-land dg-regions" })
  } else {
    const candIds = set === "areas" ? new Set(picked.map((t) => t.id)) : new Set()
    const bordered = []
    const merged = []
    const all = G.units(doc, detail)
    for (const u of all) if (!candIds.has(u.id)) (u.members.length > 1 ? merged : bordered).push(unitPath(doc, u))
    const covered = new Set(all.flatMap((u) => u.members))
    for (const a of doc.areas) if (!covered.has(a.id)) bordered.push(a.d)
    if (bordered.length) children.push({ kind: "path", d: bordered.join(""), cls: `dg-land${detail === "continents" ? " dg-merged" : ""}` })
    if (merged.length) children.push({ kind: "path", d: merged.join(""), cls: "dg-land dg-merged" })
  }
  for (const w of doc.water ?? []) children.push({ kind: "path", d: w.d, cls: "dg-water" })
  for (const g of select ? data.graticule ?? [] : v.graticule) {
    const gr = doc.graticule[g]
    for (const d of Array.isArray(gr) ? gr : [gr]) children.push({ kind: "path", d, cls: "dg-grat" })
  }
  const onIds = new Set(select ? [] : (eff.lines ?? []).filter((l) => l.id).map((l) => l.id))
  for (const l of doc.lines ?? []) if (!onIds.has(l.id)) children.push({ kind: "path", d: l.d, cls: "dg-river" })

  if (!select) {
    for (const b of v.bands) {
      children.push({ kind: "path", d: pathOf(bandRings(doc, { from_lat: b.from, to_lat: b.to })), cls: `dg-band mk-${b.role}`, pattern: b.pattern, role: b.role, fillRule: "evenodd" })
      const [ax, ay] = G.projectOf(doc, (G.flt(b.from) + G.flt(b.to)) / 2, doc.box[0] + (doc.box[2] - doc.box[0]) * 0.16)
      if (b.label) items.push({ kind: "band", text: b.label, x: ax, y: ay, role: b.role, pattern: b.pattern })
      else legend.push({ text_it: `Fascia da ${latW(b.from)} a ${latW(b.to)}`, swatch: { kind: "area", role: b.role, pattern: b.pattern } })
    }
    for (const h of [...v.highlight, ...v.since]) {
      const unit = G.resolveArea(doc, detail, h.id)
      children.push({ kind: "path", d: unitPath(doc, unit), cls: `dg-hl mk-${h.role}`, pattern: h.pattern, role: h.role })
      items.push({ kind: "area", text: h.name, x: unit.anchor[0], y: unit.anchor[1], role: h.role, pattern: h.pattern })
    }
    for (const l of (eff.lines ?? []).filter((x) => x.id)) {
      const base = G.lineOf(doc, l.id)
      children.push({ kind: "path", d: base.d, cls: "dg-river dg-line-on" })
      const bx = G.boxOf(base.d)
      items.push({ kind: "line", text: l.label_it ?? nm(doc, "lines", l.id), x: (bx[0] + bx[2]) / 2, y: (bx[1] + bx[3]) / 2, swatch: { kind: "line" } })
    }
    for (const l of (eff.lines ?? []).filter((x) => !x.id)) {
      const pts = linePoints(doc, l)
      children.push({ kind: "path", d: polyPath(pts), cls: "dg-meridian dg-line-on" })
      if (l.label_it) {
        const at = pts[Math.floor(pts.length * 0.15)]
        items.push({ kind: "line", text: l.label_it, x: at[0], y: at[1], swatch: { kind: "line" } })
      }
    }
    for (const r of v.routes) {
      const nodes = r.via.map((n) => nodeXY(doc, detail, n.id))
      children.push({ kind: "path", d: polyPath(nodes), cls: `dg-route st-${r.role}`, role: r.role })
      if (r.label) {
        const i = Math.floor((nodes.length - 1) / 2)
        const nxt = nodes[i + 1] ?? nodes[i]
        items.push({ kind: "route", text: r.label, x: (nodes[i][0] + nxt[0]) / 2, y: (nodes[i][1] + nxt[1]) / 2, role: r.role, swatch: { kind: "route", role: r.role } })
      }
    }
    // the points of the figure, in pixels
    for (const p of v.places) {
      const pl = G.placeOf(doc, p.id)
      outside.push({ kind: "circle", cx: px(frame, pl.x), cy: py(frame, pl.y), r: 5, cls: "dg-place" })
      items.push({ kind: "place", text: p.name, x: pl.x, y: pl.y, swatch: { kind: "place" } })
    }
    for (const p of v.points) {
      const [x, y] = G.projectOf(doc, G.flt(p.lat), G.flt(p.lon))
      outside.push({ kind: "marker", shape: "diamond", x: px(frame, x) - 7, y: py(frame, y) - 7, w: 14, h: 14, cls: "dg-point mk-muted" })
      if (p.label) items.push({ kind: "point", text: p.label, x, y, swatch: { kind: "point" } })
    }
    for (const r of v.routes) for (const n of r.via) {
      const [x, y] = nodeXY(doc, detail, n.id)
      outside.push({ kind: "circle", cx: px(frame, x), cy: py(frame, y), r: 4, cls: `dg-node mk-${r.role}` })
    }
  }

  // the select targets: one neutral style, reading order, keys t1..tN, a compass phrase and nothing else
  const targetOut = []
  if (select) {
    picked.forEach((t, i) => {
      const aria = `zona ${i + 1} di ${picked.length}, ${t.neutral_it}`
      const base = { target: t.key, targetLabel: aria }
      if (set === "areas") children.push({ kind: "path", d: unitPath(doc, t.item.unit), cls: "dg-cand", ...base })
      else if (set === "bands") children.push({ kind: "path", d: pathOf(bandRings(doc, t.item.band)), cls: "dg-cand dg-cand-band", fillRule: "evenodd", ...base })
      else if (set === "lines") {
        const l = t.item.line
        const d = l.id ? G.lineOf(doc, l.id).d : polyPath(linePoints(doc, l))
        children.push({ kind: "path", d, cls: "dg-river dg-line-neutral" })
        children.push({ kind: "path", d, cls: "dg-cand-line", ...base })
      } else outside.push({ kind: "circle", cx: px(frame, t.x), cy: py(frame, t.y), r: 12, cls: "dg-cand dg-cand-dot", ...base })
      outside.push({ kind: "text", x: px(frame, t.x), y: py(frame, t.y) + 5, px: ctx.fontPx, text: String(i + 1), cls: "dg-tnum" })
      targetOut.push({ key: t.key, bbox: t.bbox, neutral_it: t.neutral_it })
    })
  }

  ctx.shapes.push({ kind: "group", at: [frame.x, frame.y], scale: frame.k, cls: "dg-mapgroup", children }, ...outside)

  // compass: "Ovest", a north arrow with "Nord" and "Est" in a row under the frame; never on a polar base
  let below = frame.y + frame.h + 6
  if (!G.polar(doc)) {
    const rowY = frame.y + frame.h + 4
    label(ctx, "Ovest", frame.x, rowY, { anchor: "start", cls: "dg-compass" })
    label(ctx, "Est", frame.x + frame.w, rowY, { anchor: "end", cls: "dg-compass" })
    const cx = ctx.width / 2
    ctx.shapes.push({ kind: "polygon", points: [[cx - 20, rowY + 3], [cx - 12, rowY + ctx.lineH - 4], [cx - 20, rowY + ctx.lineH - 9], [cx - 28, rowY + ctx.lineH - 4]], cls: "dg-north" })
    label(ctx, "Nord", cx - 6, rowY, { anchor: "start", cls: "dg-compass" })
    below = rowY + ctx.lineH + 6
  }
  ctx.shapes.push({ kind: "rect", x: frame.x, y: frame.y, w: frame.w, h: frame.h, cls: "dg-frame" })

  // labels: text when at most 8 and all fit, else numbered callouts with the legend naming them
  const box = { x0: frame.x, x1: frame.x + frame.w, y0: frame.y, y1: frame.y + frame.h }
  const placed = items.map((it) => ({ ...it, px: px(frame, it.x), py: py(frame, it.y) }))
  let callouts = placed.length > LABELS_DRAWN
  if (!callouts) {
    const mark = ctx.labels.length
    for (const it of placed) {
      if (!centred(ctx, it, box)) {
        callouts = true
        ctx.labels.length = mark
        break
      }
    }
  }
  let extra = 0
  if (callouts) {
    const r = Math.ceil(ctx.fontPx * 0.75)
    const taken = []
    const crowded = []
    placed.forEach((it, i) => {
      const spot = badgeSpot(it.px, it.py, r, box, taken, ctx.lineH)
      if (spot) taken.push(spot)
      else crowded.push({ it, i })
      const at = spot ?? [it.px, it.py]
      if (spot && Math.hypot(at[0] - it.px, at[1] - it.py) > 1) ctx.shapes.push({ kind: "line", x1: it.px, y1: it.py, x2: at[0], y2: at[1], cls: "dg-leader" })
      if (spot) {
        ctx.shapes.push({ kind: "circle", cx: spot[0], cy: spot[1], r, cls: "dg-badge" })
        label(ctx, String(i + 1), spot[0], spot[1], { anchor: "middle", valign: "middle", cls: "dg-callout" })
      }
      legend.push({ n: i + 1, text_it: it.text, swatch: it.kind === "place" || it.kind === "point" ? undefined : it.swatch ?? { kind: "area", role: it.role, pattern: it.pattern } })
    })
    // what does not fit in the frame goes in a row under it, each with a leader to its place
    let cx = box.x0 + r
    let cy = below + r
    for (const { it, i } of crowded) {
      if (cx + r > ctx.width - 4) {
        cx = box.x0 + r
        cy += 2 * r + 4
      }
      ctx.shapes.push({ kind: "line", x1: it.px, y1: it.py, x2: cx, y2: cy - r, cls: "dg-leader" })
      ctx.shapes.push({ kind: "circle", cx, cy, r, cls: "dg-badge" })
      label(ctx, String(i + 1), cx, cy, { anchor: "middle", valign: "middle", cls: "dg-callout" })
      cx += 2 * r + 6
      extra = cy + r + 4 - below
    }
  } else {
    for (const kind of ["area", "route", "band"]) {
      for (const it of placed.filter((x) => x.kind === kind)) legend.push({ text_it: it.text, swatch: it.swatch ?? { kind: "area", role: it.role, pattern: it.pattern } })
    }
  }
  if (doc.approximate) legend.push({ text_it: "Confini approssimativi", swatch: { kind: "note" } })
  return finish(ctx, below + extra, {
    legend: select ? [] : legend,
    targets: targetOut,
    live: !select && year !== null ? describe(data, { state: ctx.state, controls: { year } }) : "",
    states: Array.isArray(data.states) ? data.states.length : 1,
    state: ctx.state
  })
}

// A label centred on its anchor (an area), or near it; null when none fits.
function centred(ctx, it, box) {
  const m = ctx.measure(it.text, ctx.fontPx, 180)
  const w = Math.ceil(Math.min(m.w, 180))
  const h = Math.ceil(m.h)
  const probe = { x: Math.round(it.px - w / 2), y: Math.round(it.py - h / 2), w, h }
  const inside = probe.x >= box.x0 && probe.x + w <= box.x1 && probe.y >= box.y0 && probe.y + h <= box.y1
  const clash = ctx.labels.some((l) => l.x < probe.x + w && probe.x < l.x + l.w && l.y < probe.y + h && probe.y < l.y + l.h)
  if (it.kind === "area" && inside && !clash) return label(ctx, it.text, probe.x, probe.y, { anchor: "start", cls: `dg-name role-${it.role ?? "muted"}`, maxW: 180 })
  // near its mark, not on it: the avoided "segment" is the mark itself, which also lets the search widen when the nearest places are taken
  return labelNear(ctx, it.text, it.px, it.py, it.kind === "area" ? 4 : 9, box, { cls: `dg-name${it.role ? ` role-${it.role}` : ""}`, maxW: 180, avoid: [{ x1: it.px, y1: it.py, x2: it.px, y2: it.py }] })
}

// The place of a callout: on its anchor, or the nearest free spot around it (a circle of radius r that touches none taken, inside the frame).
function badgeSpot(x, y, r, box, taken, lineH) {
  // apart as circles, and so that the two numbers (a box as high as a line, about 30 px wide) do not touch
  const apart = (cx, cy, [tx, ty]) => Math.hypot(tx - cx, ty - cy) >= 2 * r + 2 && (Math.abs(tx - cx) >= 30 || Math.abs(ty - cy) >= lineH + 1)
  const free = (cx, cy) => cx - r >= box.x0 && cx + r <= box.x1 && cy - r >= box.y0 && cy + r <= box.y1 && taken.every((t) => apart(cx, cy, t))
  const sx = Math.min(Math.max(x, box.x0 + r), box.x1 - r)
  const sy = Math.min(Math.max(y, box.y0 + r), box.y1 - r)
  if (free(sx, sy)) return [sx, sy]
  for (let ring = 1; ring <= 14; ring++) {
    for (let a = 0; a < 16; a++) {
      const cx = sx + Math.cos((a * Math.PI) / 8) * ring * (r + 2)
      const cy = sy + Math.sin((a * Math.PI) / 8) * ring * (r + 2)
      if (free(cx, cy)) return [cx, cy]
    }
  }
  return null
}

// The [x, y] of a route node: a place, or the label anchor of an area.
function nodeXY(doc, detail, id) {
  const pl = G.placeOf(doc, id)
  if (pl) return [pl.x, pl.y]
  const u = G.resolveArea(doc, detail, id)
  return [u.anchor[0], u.anchor[1]]
}
