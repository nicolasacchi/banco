// periodic_table (WAVE2 2.5, chemistry.md 2.9; T7): the first four periods or the main groups, from chem/elements. Tapping an element opens its card.
// Below 600 px (or when a cell would be under its text) the table is a list by group with the outline of the table beside each group (A3: never a
// scroll in two directions). `highlight` marks up to four sets of elements by a marker shape, an outline style and a tint (never colour alone).
// The Ruby twin is Lessons::Diagrams::PeriodicTable (the semantic checks run in the same order); both run test/fixtures/diagrams/types/periodic_table.json.
import schema from "lesson/diagram_schemas/periodic_table"
import * as Chem from "lesson/lib/chem"
import { effectiveState, finish, label, listIt, shape, stateCount, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { cellBox, grid, outline } from "lesson/diagrams/grid/api"
import { rangeElements, rangeGroups } from "lesson/diagrams/science/common"

export const type = "periodic_table"
export { schema }

const LATIN_WORDS = "il simbolo viene dal latino"
const HINT = "Tocca un elemento per vedere la sua scheda."
const LABEL_WORDS = 6 // lesson2.label_words_max
const MARKERS = ["circle", "square", "triangle", "diamond"]
const PHONE_BELOW = 600

// ---- semantics (the same checks, in the same order, as Lessons::Diagrams::PeriodicTable) --------------------------------------------------

function stateProblem(eff, path) {
  const inRange = rangeElements(eff.range).map((e) => e.symbol)
  const seen = new Set()
  const sets = eff.highlight ?? []
  for (let i = 0; i < sets.length; i++) {
    const set = sets[i]
    if (set.label_it && words(set.label_it) > LABEL_WORDS) return { path: `${path}/highlight/${i}/label_it`, message: `a label has ${words(set.label_it)} words (at most ${LABEL_WORDS})` }
    for (let j = 0; j < set.symbols.length; j++) {
      const sym = set.symbols[j]
      const at = `${path}/highlight/${i}/symbols/${j}`
      if (!Chem.isSymbol(sym)) return { path: at, message: `${sym} is not the symbol of an element (symbols are case-exact)`, code: "E-CHEM-SYMBOL" }
      if (!inRange.includes(sym)) return { path: at, message: `${sym} is not in ${eff.range} (the table draws ${inRange[0]} to ${inRange[inRange.length - 1]})` }
      if (seen.has(sym)) return { path: at, message: `${sym} is in two highlight sets (a cell has one marker)` }
      seen.add(sym)
    }
  }
  return null
}

export function semantic(data) {
  const count = stateCount(data)
  for (let i = 0; i < count; i++) {
    const found = stateProblem(effectiveState(data, i), data.states?.length ? `/states/${i}` : "")
    if (found) return found
  }
  return null
}

// ---- what the table says about an element -----------------------------------------------------------------------------------------------

const cap = (text) => text.charAt(0).toUpperCase() + text.slice(1)

// The card of an element, as the page opens it on a tap: number, group, period and where the symbol comes from.
export function cardText(e) {
  const origin = e.origin_it ? ` Il simbolo ${e.symbol} viene ${e.origin_it}.` : ""
  return `Numero atomico ${e.z}. Gruppo ${e.group}, periodo ${e.period}.${origin}`
}

// ---- layout -----------------------------------------------------------------------------------------------------------------------------

const markerOf = (i) => MARKERS[i % MARKERS.length]

// The highlight set of each symbol: { symbol -> index }.
function setsOf(eff) {
  const map = new Map()
  ;(eff.highlight ?? []).forEach((set, i) => set.symbols.forEach((s) => map.set(s, i)))
  return map
}

// The canonical numbering of the targets (reading order of the table), whatever view is drawn.
const targetNumber = (elements) => new Map(elements.map((e, i) => [e.symbol, i + 1]))

// A cell's text lines: [text, class] from the show.
function cellLines(e, show) {
  if (show === "symbol_z") return [[String(e.z), "dg-pz"], [e.symbol, "dg-psym"]]
  return [[e.symbol, "dg-psym"]]
}

function legend(ctx, eff, elements, y, o) {
  const F = ctx.fontPx
  const show = eff.show ?? "symbol"
  const W = ctx.width - 6
  if (o.select) return y
  const rows = []
  ;(eff.highlight ?? []).forEach((set, i) => {
    const names = show === "symbol_name" ? set.symbols.map((s) => `${s} ${Chem.element(s).name_it}`).join(", ") : ""
    const text = [set.label_it, names].filter(Boolean).join(": ")
    rows.push({ marker: markerOf(i), cls: `dg-hlmark dg-hlmark-${i}`, text: text || `Gruppo ${i + 1}` })
  })
  if (eff.mark_latin) rows.push({ marker: "ring", cls: "dg-latinmark", text: LATIN_WORDS })
  for (const r of rows) {
    const m = ctx.measure(r.text, F, W - 30)
    shape(ctx, "marker", { shape: r.marker, x: 2, y: y + Math.round((ctx.lineH - 16) / 2), w: 16, h: 16, cls: r.cls })
    label(ctx, r.text, 26, y, { anchor: "start", cls: "dg-legendtext", maxW: W - 30 })
    y += Math.max(m.h, ctx.lineH) + 6
  }
  return y
}

function tableView(ctx, eff, elements, groups, o) {
  const F = ctx.fontPx
  const show = eff.show ?? "symbol"
  const periods = Math.max(...elements.map((e) => e.period))
  const cols = groups.length
  const wLeft = Math.max(28, ctx.measure("7", F).w + 14)
  const widest = Math.max(...elements.map((e) => ctx.measure(e.symbol, F).w))
  const minCell = Math.max(34, Math.ceil(widest) + 12)
  const maxCell = eff.range === "periods_1_4" ? 56 : 84
  const avail = ctx.width - wLeft - 6
  const cell = Math.min(maxCell, Math.floor(avail / cols))
  if (ctx.width < PHONE_BELOW || cell < minCell) return null
  const lines = show === "symbol_z" ? 2 : 1
  const cellH = Math.max(42, lines * ctx.lineH + 8)
  const headH = o.select ? 0 : ctx.lineH + 8
  const g = grid({ rows: periods + (o.select ? 0 : 1), cols: cols + (o.select ? 0 : 1), widths: o.select ? cell : [wLeft, ...Array(cols).fill(cell)], heights: o.select ? cellH : [headH, ...Array(periods).fill(cellH)], headerRows: o.select ? 0 : 1, headerCols: o.select ? 0 : 1 })
  const at = (e) => ({ row: (o.select ? 0 : 1) + e.period - 1, col: (o.select ? 0 : 1) + groups.indexOf(e.group) })
  const x0 = Math.max(0, Math.round((ctx.width - g.width) / 2))
  const sets = setsOf(eff)
  const latin = new Set(elements.filter((e) => e.latin).map((e) => e.symbol))
  const numbers = targetNumber(elements)
  const boxes = []
  const hits = []
  if (!o.select) {
    groups.forEach((grp, k) => {
      const b = cellBox(g, 0, 1 + k)
      label(ctx, String(grp), x0 + b.x + b.w / 2, b.y + 2, { anchor: "middle", cls: "dg-phead" })
    })
    for (let p = 1; p <= periods; p++) {
      const b = cellBox(g, p, 0)
      label(ctx, String(p), x0 + b.x + b.w / 2, b.y + (b.h - ctx.lineH) / 2, { anchor: "middle", cls: "dg-phead" })
    }
  }
  for (const e of elements) {
    const b = cellBox(g, at(e).row, at(e).col)
    const setIndex = sets.get(e.symbol)
    const cls = o.select ? "dg-pcell" : `dg-pcell${setIndex !== undefined ? ` dg-hl dg-hl-${setIndex}` : ""}`
    const rect = shape(ctx, "rect", { x: x0 + b.x + 2, y: b.y + 2, w: b.w - 4, h: b.h - 4, r: 6, cls })
    if (o.select) {
      rect.target = `t${numbers.get(e.symbol)}`
      boxes.push({ target: rect.target, n: numbers.get(e.symbol), bbox: { x: rect.x, y: rect.y, w: rect.w, h: rect.h } })
    }
    const rows = o.select ? [[e.symbol, "dg-psym"]] : cellLines(e, show)
    const textH = rows.length * ctx.lineH
    rows.forEach(([text, cls2], k) => label(ctx, text, x0 + b.x + b.w / 2, b.y + (b.h - textH) / 2 + k * ctx.lineH, { anchor: "middle", cls: cls2 }))
    if (!o.select) {
      if (setIndex !== undefined) shape(ctx, "marker", { shape: markerOf(setIndex), x: x0 + b.x + b.w - 15, y: b.y + 4, w: 11, h: 11, cls: `dg-hlmark dg-hlmark-${setIndex}` })
      if (eff.mark_latin && latin.has(e.symbol)) shape(ctx, "marker", { shape: "ring", x: x0 + b.x + b.w - 15, y: b.y + b.h - 15, w: 11, h: 11, cls: "dg-latinmark" })
      hits.push({ key: `cell:${e.symbol}`, id: e.symbol, x: x0 + b.x + 2, y: b.y + 2, w: b.w - 4, h: b.h - 4, name: cap(e.name_it), text: `simbolo ${e.symbol}, numero atomico ${e.z}`, note_it: cardText(e) })
    }
  }
  // the outline of each highlight set
  if (!o.select) {
    ;(eff.highlight ?? []).forEach((set, i) => {
      const cells = set.symbols.map((s) => elements.find((e) => e.symbol === s)).filter(Boolean).map(at)
      if (cells.length) shape(ctx, "group", { at: [x0, 0], children: [{ kind: "path", d: outline(g, cells, { kind: "boot" }).d, cls: `dg-hlout dg-hlout-${i}` }], cls: "dg-hlgroup" })
    })
  }
  let y = g.height + 8
  y = legend(ctx, eff, elements, y, o)
  if (!o.select) {
    label(ctx, HINT, 2, y, { anchor: "start", cls: "dg-hint", maxW: ctx.width - 8 })
    y += ctx.measure(HINT, F, ctx.width - 8).h + 4
  }
  return { height: y, hits, boxes, view: "table" }
}

// The outline of the table beside a group: every cell a tiny block, the group's cells filled. One path for the outline, one for the group.
function miniOutline(ctx, elements, groups, group, x, y, w) {
  const periods = Math.max(...elements.map((e) => e.period))
  const u = w / groups.length
  const v = 5
  const rect = (e) => `M${(x + groups.indexOf(e.group) * u + 0.5).toFixed(1)},${y + (e.period - 1) * v + 0.5} h${(u - 1).toFixed(1)} v${v - 1} h-${(u - 1).toFixed(1)} z`
  shape(ctx, "path", { d: elements.map(rect).join(" "), cls: "dg-mini" })
  shape(ctx, "path", { d: elements.filter((e) => e.group === group).map(rect).join(" "), cls: "dg-mini dg-mini-on" })
  return periods * v
}

function listView(ctx, eff, elements, groups, o) {
  const F = ctx.fontPx
  const show = eff.show ?? "symbol"
  const sets = setsOf(eff)
  const latin = new Set(elements.filter((e) => e.latin).map((e) => e.symbol))
  const numbers = targetNumber(elements)
  const periods = Math.max(...elements.map((e) => e.period))
  const miniW = 72
  const miniH = periods * 5
  const heading = o.select ? 0 : Math.ceil(Math.max(...groups.map((g) => ctx.measure(`Gruppo ${g}`, F).w)))
  const chipH = ctx.lineH + 12
  const room = ctx.width - 6
  const boxes = []
  const hits = []
  let y = 4
  for (const grp of groups) {
    const list = elements.filter((e) => e.group === grp)
    const head = Math.max(chipH, miniH)
    // the chips of a group: on the line of its heading when they all fit there, else under it
    const texts = list.map((e) => (o.select ? e.symbol : [show === "symbol_z" ? e.z : null, e.symbol, show === "symbol_name" ? e.name_it : null].filter((p) => p !== null).join(" ")))
    const widths = texts.map((t) => Math.max(48, Math.ceil(ctx.measure(t, F).w) + 32))
    const x1 = miniW + 14 + (heading ? heading + 10 : 0)
    const inline = widths.reduce((a, w) => a + w + 6, 0) - 6 <= room - x1
    const startX = inline ? x1 : 2
    let cx = startX
    let cy = inline ? y + Math.round((head - chipH) / 2) : y + head + 4
    const chips = []
    list.forEach((e, k) => {
      if (cx + widths[k] > room && cx > startX) {
        cx = startX
        cy += chipH + 6
      }
      chips.push({ e, text: texts[k], x: cx, y: cy, w: widths[k] })
      cx += widths[k] + 6
    })
    miniOutline(ctx, elements, groups, grp, 2, y + Math.round((head - miniH) / 2), miniW)
    if (!o.select) label(ctx, `Gruppo ${grp}`, miniW + 14, y + Math.round((head - ctx.lineH) / 2), { anchor: "start", cls: "dg-phead dg-gword" })
    for (const c of chips) {
      const setIndex = sets.get(c.e.symbol)
      const cls = o.select ? "dg-pcell" : `dg-pcell${setIndex !== undefined ? ` dg-hl dg-hl-${setIndex}` : ""}`
      const rect = shape(ctx, "rect", { x: c.x, y: c.y, w: c.w, h: chipH, r: 8, cls })
      if (o.select) {
        rect.target = `t${numbers.get(c.e.symbol)}`
        boxes.push({ target: rect.target, n: numbers.get(c.e.symbol), bbox: { x: c.x, y: c.y, w: c.w, h: chipH } })
      }
      label(ctx, c.text, c.x + (c.w - 12) / 2, c.y + 6, { anchor: "middle", cls: "dg-psym" })
      if (!o.select) {
        if (setIndex !== undefined) shape(ctx, "marker", { shape: markerOf(setIndex), x: c.x + c.w - 13, y: c.y + 3, w: 10, h: 10, cls: `dg-hlmark dg-hlmark-${setIndex}` })
        if (eff.mark_latin && latin.has(c.e.symbol)) shape(ctx, "marker", { shape: "ring", x: c.x + c.w - 13, y: c.y + chipH - 13, w: 10, h: 10, cls: "dg-latinmark" })
        hits.push({ key: `cell:${c.e.symbol}`, id: c.e.symbol, x: c.x, y: c.y, w: c.w, h: chipH, name: cap(c.e.name_it), text: `simbolo ${c.e.symbol}, numero atomico ${c.e.z}`, note_it: cardText(c.e) })
      }
    }
    y = Math.max(inline ? y + head : y + head + 4, ...chips.map((c) => c.y + chipH)) + 10
  }
  y = legend(ctx, eff, elements, y, o)
  if (!o.select) {
    label(ctx, HINT, 2, y, { anchor: "start", cls: "dg-hint", maxW: ctx.width - 8 })
    y += ctx.measure(HINT, F, ctx.width - 8).h + 4
  }
  return { height: y, hits, boxes, view: "list" }
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const select = ctx.mode === "select"
  const elements = rangeElements(eff.range)
  const groups = rangeGroups(eff.range)
  const o = { select }
  const drawn = tableView(ctx, eff, elements, groups, o) ?? listView(ctx, eff, elements, groups, o)
  const out = finish(ctx, drawn.height, { states: stateCount(data), state: ctx.state })
  if (out.error) return out
  if (select) out.targets = drawn.boxes.sort((a, b) => a.n - b.n).map(({ target, bbox }) => ({ target, bbox }))
  else out.hits = drawn.hits
  out.view = drawn.view
  return out
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// ---- description, targets, printed -----------------------------------------------------------------------------------------------------

function describeState(data, i) {
  const eff = effectiveState(data, i)
  const elements = rangeElements(eff.range)
  const span = eff.range === "periods_1_4" ? "le prime quattro righe" : "i gruppi principali"
  const out = [`La tavola periodica: ${span}, ${elements.length} elementi, da ${elementOf(elements[0])} a ${elementOf(elements[elements.length - 1])}. Le colonne sono i gruppi, le righe i periodi. Ogni elemento si può toccare per vedere la sua scheda.`]
  for (const set of eff.highlight ?? []) {
    const names = set.symbols.map((s) => `${Chem.element(s).name_it} (${s})`)
    out.push(`${set.label_it ? `${cap(set.label_it)}` : "Evidenziati"}: ${listIt(names)}.`)
  }
  if (eff.mark_latin) {
    const names = elements.filter((e) => e.latin).map((e) => `${e.name_it} (${e.symbol})`)
    out.push(`Con il cerchio vuoto, ${LATIN_WORDS}: ${listIt(names)}.`)
  }
  return out.join(" ")
}

const elementOf = (e) => `${e.name_it} (${e.symbol})`

export function describe(data, ctx) {
  const single = ctx?.state
  const count = stateCount(data)
  const one = (i) => `${count > 1 ? `Passo ${i + 1}. ${data.states[i]?.op_it ? `${data.states[i].op_it}. ` : ""}` : ""}${describeState(data, i)}`
  if (single !== undefined || count === 1) return one(Math.min(single ?? 0, count - 1))
  return Array.from({ length: count }, (_, i) => one(i)).join(" ")
}

// the symbols in lower case: a target id starts with a lower-case letter or a digit ("na" is sodium, "co" is cobalt)
export const targetIds = (data, set) => (set === "cells" ? rangeElements(data.range).map((e) => e.symbol.toLowerCase()) : [])

// targets(data, set) -> [{ key, bbox, neutral_it }]: the symbols of the table, lower case, in reading order.
export function targets(data, set, opts = {}) {
  const ids = targetIds(data, set)
  if (ids.length === 0) return []
  const scene = layout(data, { width: 360, fontPx: 20, subject: "chemistry", ...opts, mode: "select", state: 0 })
  if (scene.error) return []
  return scene.targets.map((t, i) => ({ key: ids[i], bbox: t.bbox, neutral_it: `Elemento ${i + 1} di ${ids.length}` }))
}

// Every string the state prints (L4), the tap cards included (L8); Ruby's printed() returns the same set.
export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const rows = rangeElements(eff.range)
  const out = new Set()
  for (const e of rows) for (const v of [e.symbol, e.name_it, String(e.z), e.latin, e.origin_it]) if (v) out.add(v)
  for (const g of rangeGroups(eff.range)) out.add(String(g))
  for (let p = 1; p <= Math.max(...rows.map((e) => e.period)); p++) out.add(String(p))
  for (const set of eff.highlight ?? []) if (set.label_it) out.add(set.label_it)
  if (eff.mark_latin) out.add(LATIN_WORDS)
  out.add("Gruppo")
  out.add("Periodo")
  out.add(HINT)
  const op = data.states?.[state]?.op_it
  if (op) out.add(op)
  return [...out]
}
