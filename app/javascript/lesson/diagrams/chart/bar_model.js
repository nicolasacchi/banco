// bar_model (T6, WAVE2 2.4): one proportional-bar module with three views. `parts` is R8's bar model (bars of parts, one total; a hidden part is
// a solution field whose width is the total less the parts that show); `percent` is business's double number line (euro above, percent below,
// one scale, every value computed exactly; successive percentages on new lines); `fraction` is reserved (W2-3).
// The server serves hidden values as null and the computed `values` of the percent view; this module never works a hidden value out (L2).
// Ruby twin: Lessons::Diagrams::BarModel; shared vectors: test/fixtures/lesson2/bar_model.json and test/fixtures/diagrams/types/bar_model.json.
import * as N from "lesson/num"
import schema from "lesson/diagram_schemas/bar_model"
import { effectiveState, finish, label, listIt, plain, shape, stackLabels, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { authorValue, formatValue } from "lesson/diagrams/chart/format"

export const type = "bar_model"
export { schema }
export const states = stateCount

const PERCENT_ONLY = ["base", "anchor", "unit", "marks", "hide", "chain"]
const same = (a, b) => N.compare(a, b) === 0

// ---- the computed values of the percent view (the twin of BarModel.percent_values) ----------------------------------------------------------

export function hundred(eff) {
  if (eff.base !== undefined) return N.parse(eff.base)
  if (!eff.anchor) return null
  return N.div(N.mul(N.parse(eff.anchor.value), N.int(100)), N.parse(eff.anchor.pct))
}

export function money(x, unit) {
  const places = unit === "euro" ? 2 : undefined
  const text = authorValue(x, places)
  return unit !== "euro" && text.includes(",") && text.split(",")[1].length > 2 ? authorValue(x, 2) : text
}

// { values: { "100": "1860,00", "22": null }, chain_values: [{ from, to }] } with null for a hidden value; {} when there is no base
export function percentValues(eff) {
  const base = hundred(eff)
  if (!base) return {}
  const hide = (eff.hide ?? []).map((h) => N.parse(h))
  const unit = eff.unit ?? "euro"
  const marks = (eff.marks ?? []).map((m) => N.parse(m.pct))
  const shown = [N.int(100), ...marks, ...(eff.anchor ? [N.parse(eff.anchor.pct)] : [])]
  const uniq = []
  for (const p of shown) if (!uniq.some((q) => same(p, q))) uniq.push(p)
  uniq.sort(N.compare)
  const values = {}
  for (const p of uniq) values[authorValue(p)] = hide.some((h) => same(h, p)) ? null : money(N.div(N.mul(base, p), N.int(100)), unit)
  const out = { values }
  const chain = eff.chain ?? []
  if (chain.length) {
    let from = base
    let cut = hide.some((h) => same(h, N.int(100)))
    out.chain_values = chain.map((step) => {
      const p = N.parse(step.pct)
      const to = N.div(N.mul(from, p), N.int(100))
      const row = { from: cut ? null : money(from, unit) }
      cut = cut || hide.some((h) => same(h, p))
      row.to = cut ? null : money(to, unit)
      from = to
      return row
    })
  }
  return out
}

// the display text of a value string of `values` ("1860,00" -> "1.860,00 €"); null is "?"
function shownValue(text, unit) {
  if (text === null || text === undefined) return "?"
  const x = N.parse(text)
  if (!x) return "?"
  const places = text.includes(",") ? text.split(",")[1].length : 0
  const body = formatValue(x, places)
  return unit === "euro" ? `${body} €` : body
}

// ---- the served form: values and chain_values come beside the schema's fields; a hidden part has a null value ------------------------------

function split(data) {
  const strip = (o) => {
    const { values, chain_values: chain, ...rest } = o
    if (rest.bars) rest.bars = rest.bars.map((b) => ({ ...b, parts: b.parts.map((p) => (p.hidden && p.value === null ? { ...p, value: "0" } : p)) }))
    return [rest, { values, chain_values: chain }]
  }
  const [clean, top] = strip(data)
  const perState = []
  if (Array.isArray(clean.states)) {
    clean.states = clean.states.map((s) => {
      const [rest, extra] = strip(s)
      perState.push(extra)
      return rest
    })
  }
  return { clean, top, perState }
}

const valuesOf = (eff, extra) => (extra.values || extra.chain_values ? extra : percentValues(eff))

// ---- semantics (the JS mirror of the Ruby checks that a served figure can still break) ---------------------------------------------------

export function semantic(data) {
  for (let i = 0; i < stateCount(data); i++) {
    const eff = effectiveState(data, i)
    const at = data.states ? `/states/${i}` : ""
    if (eff.view === "parts") {
      for (const k of [...PERCENT_ONLY, "fractions", "aligned"]) if (data[k] !== undefined) return { path: `/${k}`, message: `${k} does not belong to the parts view` }
      if (!eff.bars) return { path: "/bars", message: "the parts view draws bars" }
      const total = eff.total ? N.parse(eff.total.value) : null
      for (let b = 0; b < eff.bars.length; b++) {
        const bar = eff.bars[b]
        const hidden = bar.parts.filter((p) => p.hidden).length
        if (hidden > 1) return { path: `${at}/bars/${b}/parts`, message: "a bar hides at most one part" }
        if (hidden && !total) return { path: `${at}/bars/${b}/parts`, message: "a hidden part needs the total" }
        let sum = N.int(0)
        for (let p = 0; p < bar.parts.length; p++) {
          const part = bar.parts[p]
          const v = part.hidden && part.value === "0" ? null : N.parse(part.value)
          if (v !== null && N.compare(v, N.int(0)) <= 0) return { path: `${at}/bars/${b}/parts/${p}/value`, message: "a part is above 0" }
          if (v !== null) sum = N.add(sum, v)
        }
        const visibleOnly = bar.parts.some((p) => p.hidden && p.value === "0")
        if (total && !visibleOnly && !same(sum, total)) return { path: `${at}/bars/${b}/parts`, message: "the parts add up to the total" }
        if (total && visibleOnly && N.compare(sum, total) >= 0) return { path: `${at}/bars/${b}/parts`, message: "the parts that show fill the total: nothing is left for the hidden one" }
      }
    } else if (eff.view === "percent") {
      for (const k of ["bars", "total", "fractions", "aligned"]) if (data[k] !== undefined) return { path: `/${k}`, message: `${k} does not belong to the percent view` }
      if ((data.base === undefined) === (data.anchor === undefined)) {
        // a served figure whose base was withheld still has `values`: that is not an error
        if (!(data.base === undefined && data.anchor === undefined && data.hide?.length)) return { path: "/base", message: "the percent view has exactly one of base and anchor" }
      }
      for (let m = 0; m < (eff.marks ?? []).length; m++) {
        const p = N.parse(eff.marks[m].pct)
        if (!p || N.toNumber(p) < 0 || N.toNumber(p) > 300) return { path: `${at}/marks/${m}/pct`, message: "a mark lies between 0 and 300 percent" }
      }
    }
  }
  return null
}

// ---- the layout ------------------------------------------------------------------------------------------------------------------------------

function partsBuild(eff, ctx, select) {
  const f = ctx.fontPx
  const W = ctx.width
  const pad = 8
  const x0 = pad
  const full = W - 2 * pad
  const total = eff.total ? N.parse(eff.total.value) : null
  const lens = eff.bars.map((bar) => {
    if (total) return N.toNumber(total)
    return bar.parts.reduce((a, p) => a + N.toNumber(N.parse(p.value)), 0)
  })
  const scale = full / Math.max(...lens)
  const barH = Math.max(40, Math.round(f * 2.3))
  let y = 6
  if (total && !select) {
    const x1 = x0 + N.toNumber(total) * scale
    // a label is drawn with its markup, as the bar's own label is (a formula: D-310); the descriptions use plain()
    const text = `${eff.total.label_it ? `${eff.total.label_it}: ` : ""}${formatValue(total)}`
    const h = label(ctx, text, (x0 + x1) / 2, y, { cls: "dgq-total" }).h
    shape(ctx, "path", { d: `M${x0},${y + h + 16} V${y + h + 8} H${x1} V${y + h + 16}`, cls: "dgq-brace" })
    y += h + 24
  }
  const targets = []
  eff.bars.forEach((bar, bi) => {
    if (bar.label_it && !select) y += label(ctx, bar.label_it, x0, y, { anchor: "start", cls: "dgq-bar-label" }).h + 2
    const visible = bar.parts.filter((p) => !(p.hidden && p.value === "0"))
    const shownSum = visible.reduce((a, p) => a.concat(N.parse(p.value)), []).reduce((a, b) => N.add(a, b), N.int(0))
    let x = x0
    const below = []
    bar.parts.forEach((part, pi) => {
      const hidden = part.hidden && part.value === "0"
      const widthValue = hidden ? N.toNumber(N.sub(total, shownSum)) : N.toNumber(N.parse(part.value))
      const w = widthValue * scale
      const role = !select && part.role ? ` mk-${part.role}` : ""
      const tone = select ? "dgq-part dgq-neutral" : hidden ? "dgq-part dgq-hidden" : `dgq-part ${part.role ? `mk-${part.role}` : `dgq-p${pi % 4}`}`
      void role
      const rect = shape(ctx, "rect", { x, y, w, h: barH, r: 0, cls: tone, key: `part${bi}-${pi}` })
      if (select) {
        rect.target = `t${targets.length + 1}`
        targets.push(rect)
      } else {
        const inside = hidden ? "?" : formatValue(N.parse(part.value))
        const fits = ctx.measure(inside, f).w + 8 <= w
        if (fits) label(ctx, inside, x + w / 2, y + (barH - ctx.lineH) / 2, { cls: "dgq-value", role: part.role })
        const name = part.label_it ?? ""
        below.push({ text: fits ? name : name ? `${name}: ${inside}` : inside, cx: x + w / 2, cls: "dgq-name", role: part.role, connectFrom: y + barH, maxW: Math.max(90, Math.min(200, w + 60)) })
      }
      x += w
    })
    y += barH + 2
    if (below.length) y += stackLabels(ctx, below, y + 4, 1) + 8
    y += 12
  })
  return { height: y, targets }
}

function percentBuild(eff, ctx, select, extra) {
  const f = ctx.fontPx
  const W = ctx.width
  const unit = eff.unit ?? "euro"
  const { values, chain_values: chainValues } = valuesOf(eff, extra)
  const marks = sortedMarks(eff).map(({ m }) => ({ ...m, p: N.parse(m.pct) }))
  const anchorP = eff.anchor ? N.parse(eff.anchor.pct) : null
  // the chain's lines: line k has the result before as its 100 % and a tick at its percent (all drawn on one scale)
  const rows = []
  let before = 1
  for (const step of eff.chain ?? []) {
    const p = N.parse(step.pct)
    const len = 100 * before
    rows.push({ p, len, at: (len * N.toNumber(p)) / 100 })
    before *= N.toNumber(p) / 100
  }
  const pcts = [100, ...marks.map((m) => N.toNumber(m.p)), ...(anchorP ? [N.toNumber(anchorP)] : []), ...rows.flatMap((r) => [r.len, r.at])]
  const maxPct = Math.max(100, Math.ceil(Math.max(...pcts) / 10) * 10)
  const pad = Math.max(14, Math.round(f * 0.9))
  const x0 = pad
  const x1 = W - pad
  const xOf = (p) => x0 + (p / maxPct) * (x1 - x0)
  const barH = Math.max(34, Math.round(f * 1.9))
  const pctText = (p) => `${authorValue(p)}%`
  const targets = []
  let y = 8

  // one row: the bar from 0 to its 100 %, ticks at the listed percents, the value above and the percent below
  const row = (len, ticks, tail) => {
    const aboveSpecs = []
    const belowSpecs = []
    const rowTop = y + ctx.lineH * 2 + 14
    shape(ctx, "rect", { x: x0, y: rowTop, w: xOf(len) - x0, h: barH, r: 0, cls: select ? "dgq-part dgq-neutral" : "dgq-part dgq-base" })
    if (tail > len) shape(ctx, "rect", { x: xOf(len), y: rowTop, w: xOf(tail) - xOf(len), h: barH, r: 0, cls: "dgq-part dgq-extra", pattern: "dots" })
    for (const t of ticks) {
      const x = xOf(t.pct)
      shape(ctx, "line", { x1: x, y1: rowTop - 6, x2: x, y2: rowTop + barH + 6, cls: `dgq-tick${t.role && !select ? ` st-${t.role}` : ""}` })
      if (t.role && !select) shape(ctx, "circle", { cx: x, cy: rowTop + barH / 2, r: 6, cls: `mk-${t.role}` })
      if (!select) aboveSpecs.push({ text: t.plain ? t.value : shownValue(t.value, unit), cx: x, cls: "dgq-euro", role: t.role, connectFrom: rowTop - 6 })
      belowSpecs.push({ text: select || !t.name ? t.pctText : `${t.pctText} ${t.name}`, cx: x, cls: "dgq-pct", role: select ? undefined : t.role, connectFrom: rowTop + barH + 6 })
      if (select && t.target) targets.push(shape(ctx, "rect", { x: x - 14, y: rowTop - 8, w: 28, h: barH + 16, r: 0, cls: "dgq-target", target: `t${targets.length + 1}` }))
    }
    if (aboveSpecs.length) {
      aboveSpecs.sort((a, b) => a.cx - b.cx)
      stackLabels(ctx, aboveSpecs, rowTop - 10, -1)
    }
    belowSpecs.sort((a, b) => a.cx - b.cx)
    const used = stackLabels(ctx, belowSpecs, rowTop + barH + 10, 1)
    y = rowTop + barH + 10 + used + 6
  }

  // the first line: 0, 100 and the marks sorted (a mark at 0 or 100 shares the tick)
  const ticks = []
  const put = (p, extraTick) => {
    const at = ticks.find((t) => Math.abs(t.pct - N.toNumber(p)) < 1e-9)
    if (at) Object.assign(at, Object.fromEntries(Object.entries(extraTick).filter(([, v]) => v !== undefined && v !== null)))
    else ticks.push({ pct: N.toNumber(p), pctText: pctText(p), ...extraTick })
  }
  put(N.int(0), { value: "0", plain: true })
  put(N.int(100), { value: values?.[authorValue(N.int(100))] ?? null })
  if (anchorP) put(anchorP, { value: values?.[authorValue(anchorP)] ?? null })
  for (const m of marks) put(m.p, { value: values?.[authorValue(m.p)] ?? null, name: m.label_it, role: m.role, target: true })
  ticks.sort((a, b) => a.pct - b.pct)
  row(100, ticks, Math.max(...pcts) > 100 ? Math.max(...pcts) : 100)

  // the chain: a new line for each step, drawn to scale
  rows.forEach((r, k) => {
    const cv = chainValues?.[k]
    const line = [{ pct: 0, pctText: "0%", value: "0", plain: true }, { pct: r.len, pctText: "100%", value: cv?.from ?? null }]
    if (Math.abs(r.at - r.len) > 1e-9) line.push({ pct: r.at, pctText: pctText(r.p), value: cv?.to ?? null, name: select ? null : "risultato" })
    else Object.assign(line[1], { name: select ? null : "risultato", value: cv?.to ?? null })
    row(r.len, line.sort((u, v) => u.pct - v.pct), Math.max(r.len, r.at))
  })
  return { height: y, targets }
}

function build(data, ctx, extras) {
  const eff = effectiveState(data, ctx.state)
  const extra = (data.states ? extras.perState[Math.min(ctx.state, extras.perState.length - 1)] : extras.top) ?? {}
  const select = ctx.mode === "select"
  const out = eff.view === "percent" ? percentBuild(eff, ctx, select, extra) : partsBuild(eff, ctx, select)
  return finish(ctx, out.height, { states: stateCount(data), state: ctx.state })
}

export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const out = []
  if (eff.view === "percent") {
    const pv = percentValues(eff)
    for (const [p, v] of Object.entries(pv.values ?? {})) out.push(p, v)
    for (const r of pv.chain_values ?? []) out.push(r.from, r.to)
    for (const s of eff.chain ?? []) out.push(s.pct)
  } else {
    for (const b of eff.bars ?? []) for (const p of b.parts) if (!p.hidden) out.push(p.value)
    if (eff.total) out.push(eff.total.value)
  }
  const nums = new Map()
  for (const s of out) {
    const x = typeof s === "string" ? N.parse(s.replace(/\./g, "")) : null
    if (x) nums.set(N.canonical(x), x)
  }
  return [...nums.values()].sort(N.compare).map((x) => authorValue(x))
}

const sortedMarks = (eff) => (eff.marks ?? []).map((m, i) => ({ m, i })).sort((a, b) => N.compare(N.parse(a.m.pct), N.parse(b.m.pct)) || a.i - b.i)

export function targets(data, set) {
  const scene = layout(data, { width: 390, fontPx: 18, subject: "business", state: 0, mode: "select" })
  if (scene.error) return []
  const hits = scene.shapes.filter((s) => s.target)
  const eff = effectiveState(data, 0)
  const want = set === "parts" ? eff.view !== "percent" : set === "marks" && eff.view === "percent"
  if (!want) return []
  return hits.map((s, i) => ({ key: s.target, bbox: { x: s.x, y: s.y, w: s.w, h: s.h }, neutral_it: set === "parts" ? `Parte ${i + 1}` : `Segno ${i + 1}` }))
}

// ---- the description -------------------------------------------------------------------------------------------------------------------------

function describeState(data, eff, extra, index, total) {
  const unit = eff.unit ?? "euro"
  const bits = []
  if (eff.view === "percent") {
    const { values, chain_values: cv } = valuesOf(eff, extra)
    bits.push("Una scala doppia: sopra i valori, sotto le percentuali.")
    const entries = Object.entries(values ?? {})
    for (const [p, v] of entries) {
      const mark = (eff.marks ?? []).find((m) => same(N.parse(m.pct), N.parse(p)))
      const name = mark ? ` (${plain(mark.label_it)})` : ""
      bits.push(v === null ? `Il ${p}%${name} non si vede: è da trovare.` : `Il ${p}%${name} vale ${shownValue(v, unit)}.`)
    }
    ;(eff.chain ?? []).forEach((s, k) => {
      const row = cv?.[k]
      bits.push(row?.to == null ? `Nuova riga: il ${s.pct}% del valore di prima, da trovare.` : `Nuova riga: il ${s.pct}% di ${shownValue(row.from, unit)} vale ${shownValue(row.to, unit)}.`)
    })
  } else {
    for (const bar of eff.bars) {
      const parts = bar.parts.map((p) => `${plain(p.label_it)} ${p.hidden ? "(da trovare)" : formatValue(N.parse(p.value))}`)
      bits.push(`${bar.label_it ? `${plain(bar.label_it)}: ` : ""}una barra divisa in ${bar.parts.length} parti: ${listIt(parts)}.`)
    }
    if (eff.total) bits.push(`In tutto: ${formatValue(N.parse(eff.total.value))}.`)
  }
  void data
  return `${total > 1 ? `Passo ${index + 1}. ` : ""}${bits.join(" ")}`
}

export function describe(data, ctx = {}) {
  const { clean, top, perState } = split(data)
  const n = stateCount(clean)
  const one = (i) => describeState(clean, effectiveState(clean, i), (clean.states ? perState[Math.min(i, perState.length - 1)] : top) ?? {}, i, n)
  if (typeof ctx?.state === "number") return one(ctx.state)
  return Array.from({ length: n }, (_, i) => one(i)).join(" ")
}

export function layout(data, opts) {
  const split_ = data && typeof data === "object" ? split(data) : null
  if (!split_) return run(data, opts, { schema, semantic, build: () => null })
  return run(split_.clean, opts, { schema, semantic, build: (d, ctx) => build(d, ctx, split_) })
}
