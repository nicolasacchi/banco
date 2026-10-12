// The years scale of `timeline` (WAVE2 2.2, T4a): signed years on one axis that runs 1 a.C. straight into 1 d.C. with no year 0 (the place of
// a year is Chrono.position, so the drawing and the sums cannot disagree), periods as bars, events as role markers with their labels stacked
// above, lanes, century bands, spans whose duration Chrono computes, and the zoom as states. Pure; layout and text are called by timeline.js.
import { century, duration, position, roman } from "lesson/lib/chrono"
import { effectiveState, label, listIt, plain, roleInfo, shape, stackLabels, words } from "lesson/diagrams/common"
import { fill, TEXT } from "lesson/diagrams/time/texts"

export const CAPS = { label_words: 6, note_words: 25, ticks: 40 }
const STEPS = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]

export const yearLabel = (y) => `${Math.abs(Number(y))} ${Number(y) < 0 ? TEXT.era_bc : TEXT.era_ad}`
export const eventYearLabel = (e) => (e.approx ? `${TEXT.about} ${yearLabel(e.at)}` : yearLabel(e.at))
export const durationText = (n) => `${Math.abs(n)} ${Math.abs(n) === 1 ? TEXT.year_one : TEXT.year_many}`
// A label of the neutral select form ("·") is told as a point.
const nameOf = (text) => (plain(text) === "·" ? TEXT.neutral_point : plain(text))
export const signed = (y) => String(Number(y))

// The years that are multiples of `every` inside from..to, never the year 0.
export function ticks(from, to, every) {
  const a = Number(from)
  const b = Number(to)
  const out = []
  for (let y = Math.ceil(a / every) * every; y <= b; y += every) if (y !== 0 && y >= a) out.push(y)
  return out
}

// The centuries the line passes through, in order: the boundaries lie half a year before 100 k on the axis of Chrono.position.
export function centuries(from, to) {
  const t0 = position(from)
  const t1 = position(to)
  const out = []
  for (let k = Math.floor((t0 + 0.5) / 100); k <= Math.floor((t1 + 0.5) / 100); k++) {
    const lo = Math.max(100 * k - 0.5, t0)
    const hi = Math.min(100 * (k + 1) - 0.5, t1)
    if (hi <= lo) continue
    const p = Math.ceil(lo)
    out.push({ lo, hi, text: century(p >= 0 ? p + 1 : p), n: roman(Math.floor((Math.abs(p >= 0 ? p + 1 : p) - 1) / 100) + 1), bc: p < 0 })
  }
  return out
}

const inside = (y, from, to) => duration(from, y) >= 0 && duration(y, to) >= 0

// ---- the checks (first finding, as Lessons::Diagrams::Timeline gives them) ----------------------------------------
export function staticChecks(data, map, dia) {
  const ids = (data.lanes ?? []).map((l) => l.id)
  if (new Set(ids).size !== ids.length) return dia("/lanes", "two lanes have the same id")
  const all = [data, ...(data.states ?? []).map((_, i) => effectiveState(data, i))]
  if (data.measure && Math.max(...all.map((e) => (e.events ?? []).length)) < 2) return dia("/measure", "measure needs at least two events")
  if (data.every) {
    for (const e of all) {
      if (!e.from || !e.to || duration(e.from, e.to) <= 0) continue
      const n = ticks(e.from, e.to, data.every).length
      if (n > CAPS.ticks) return dia("/every", `a step of ${data.every} years gives ${n} ticks (at most ${CAPS.ticks})`)
    }
  }
  return null
}

export function stateChecks(eff, path, map, dia) {
  const { from, to } = eff
  if (!from || !to) return null
  if (duration(from, to) <= 0) return dia(`${path}/to`, "the range goes from an earlier year to a later one")
  const lanes = (eff.lanes ?? []).map((l) => l.id)
  const events = eff.events ?? []
  if (new Set(events.map((e) => e.id)).size !== events.length) return map(`${path}/events`, "event ids must be unique")
  for (const [i, e] of events.entries()) {
    const at = `${path}/events/${i}`
    if (!inside(e.at, from, to)) return dia(`${at}/at`, "the event is outside the years of the line")
    const n = words(e.label_it)
    if (n > CAPS.label_words) return dia(`${at}/label_it`, `an event label has ${n} words (at most ${CAPS.label_words})`)
    const nw = e.note_it ? words(e.note_it) : 0
    if (nw > CAPS.note_words) return dia(`${at}/note_it`, `a note has ${nw} words (at most ${CAPS.note_words})`)
    if (lanes.length === 0) {
      if (e.lane) return dia(`${at}/lane`, "the event names a lane but the line has none")
    } else if (!e.lane) return dia(`${at}/lane`, "with lanes, every event names its lane")
    else if (!lanes.includes(e.lane)) return map(`${at}/lane`, "the event names a lane that does not exist")
  }
  for (const [i, p] of (eff.periods ?? []).entries()) {
    const at = `${path}/periods/${i}`
    if (duration(p.from, p.to) <= 0) return dia(`${at}/to`, "a period goes from an earlier year to a later one")
    if (duration(p.to, from) > 0 || duration(to, p.from) > 0) return dia(at, "the period is entirely outside the years of the line")
    if (words(p.label_it) > 8) return dia(`${at}/label_it`, `a label has ${words(p.label_it)} words (at most 8)`)
  }
  for (const [i, l] of (eff.lanes ?? []).entries()) if (words(l.label_it) > 8) return dia(`${path}/lanes/${i}/label_it`, `a label has ${words(l.label_it)} words (at most 8)`)
  const seen = []
  for (const [i, s] of (eff.spans ?? []).entries()) {
    const at = `${path}/spans/${i}`
    const a = events.find((e) => e.id === s.from)
    const b = events.find((e) => e.id === s.to)
    if (!a || !b) return map(at, "the span names an event that is not in this state")
    if (duration(a.at, b.at) <= 0) return dia(`${at}/to`, "a span goes from an earlier event to a later one")
    if (seen.includes(`${s.from}>${s.to}`)) return map(at, "the same span is written twice")
    seen.push(`${s.from}>${s.to}`)
  }
  return null
}

// ---- text ------------------------------------------------------------------------------------------------------------
const sortedEvents = (eff) => [...(eff.events ?? [])].sort((a, b) => position(a.at) - position(b.at))

export function describeYears(eff, controls = {}) {
  const parts = [fill(TEXT.years_intro, { from: yearLabel(eff.from), to: yearLabel(eff.to) })]
  if (eff.centuries) parts.push(fill(TEXT.centuries_line, { list: listIt(centuries(eff.from, eff.to).map((c) => c.text)) }))
  if ((eff.lanes ?? []).length > 1) for (const l of eff.lanes) parts.push(fill(TEXT.lane_line, { label: plain(l.label_it) }))
  for (const p of eff.periods ?? []) parts.push(fill(TEXT.period_line, { label: nameOf(p.label_it), from: yearLabel(p.from), to: yearLabel(p.to) }))
  const events = sortedEvents(eff)
  for (const e of events) parts.push(fill(TEXT.event_line, { year: eventYearLabel(e), label: nameOf(e.label_it) }))
  for (const s of eff.spans ?? []) {
    const a = events.find((e) => e.id === s.from)
    const b = events.find((e) => e.id === s.to)
    if (!a || !b) continue
    parts.push(s.show_value ? fill(TEXT.span_line, { a: plain(a.label_it), b: plain(b.label_it), n: durationText(duration(a.at, b.at)) }) : fill(TEXT.span_open, { a: plain(a.label_it), b: plain(b.label_it) }))
  }
  const picked = measured(eff, controls)
  if (picked) parts.push(fill(TEXT.measure_result, { a: plain(picked[0].label_it), b: plain(picked[1].label_it), n: durationText(duration(picked[0].at, picked[1].at)) }))
  return parts.join(" ")
}

// The two events a measure figure has chosen (earlier first), or null.
export function measured(eff, controls = {}) {
  if (!eff.measure) return null
  const chosen = (controls.measure ?? []).map((id) => (eff.events ?? []).find((e) => e.id === id)).filter(Boolean)
  return chosen.length === 2 ? chosen.sort((a, b) => position(a.at) - position(b.at)) : null
}

export function printedYears(eff) {
  const out = []
  const events = eff.events ?? []
  for (const e of events) out.push(e.label_it, e.note_it, eventYearLabel(e), signed(e.at))
  for (const p of eff.periods ?? []) out.push(p.label_it)
  for (const l of eff.lanes ?? []) out.push(l.label_it)
  if (eff.centuries) out.push(...centuries(eff.from, eff.to).map((c) => c.text))
  if (eff.every) for (const y of ticks(eff.from, eff.to, eff.every)) out.push(yearLabel(y), signed(y))
  for (const s of eff.spans ?? []) {
    if (!s.show_value) continue
    const a = events.find((e) => e.id === s.from)
    const b = events.find((e) => e.id === s.to)
    if (!a || !b) continue
    const n = duration(a.at, b.at)
    out.push(String(n), durationText(n))
  }
  if (eff.measure) out.push(TEXT.measure_label, TEXT.measure_pick, TEXT.measure_too_many)
  if (events.some((e) => e.note_it)) out.push(TEXT.note_hint)
  return out
}

export function reachableYears(data, all) {
  if (!data.measure) return []
  const out = new Set()
  for (const eff of all) {
    const events = eff.events ?? []
    for (let i = 0; i < events.length; i++) for (let j = i + 1; j < events.length; j++) {
      const n = Math.abs(duration(events[i].at, events[j].at))
      out.add(String(n)).add(durationText(n))
    }
  }
  return [...out]
}

// ---- the drawing -----------------------------------------------------------------------------------------------------
const shapeOf = (ctx, role) => roleInfo(ctx.palette, ctx.subject, role ?? "muted")?.shape ?? "circle"

// The legend row of the roles a figure uses: the role's marker and its name, wrapped to the width.
export function legendRow(ctx, roles, y) {
  const list = [...new Set(roles.filter(Boolean))]
  if (!list.length) return y
  const f = ctx.fontPx
  const sz = Math.round(f * 0.9)
  let x = 8
  let top = y + 6
  let rowH = 0
  for (const role of list) {
    const info = roleInfo(ctx.palette, ctx.subject, role)
    const text = info?.label_it ?? role
    const room = ctx.width - 16 - sz - 6
    const m = ctx.measure(text, f, room) // the same call as the label's own, so the two agree whatever the font
    const w = Math.min(Math.ceil(m.w), room)
    if (x + sz + 6 + w > ctx.width - 8 && x > 8) {
      x = 8
      top += rowH + 6
      rowH = 0
    }
    shape(ctx, "marker", { shape: shapeOf(ctx, role), x, y: top + (ctx.lineH - sz) / 2, w: sz, h: sz, cls: `mk-${role} dg-tl-legend-marker` })
    label(ctx, text, x + sz + 6, top, { anchor: "start", maxW: room, cls: "dg-tl-legend", key: `legend:${role}` })
    rowH = Math.max(rowH, m.h, ctx.lineH)
    x += sz + 6 + w + 18
  }
  return top + rowH + 6
}

// Where a tick label starts: centred on its tick, pushed inside the figure at the ends.
const tickLeft = (ctx, cx, w) => Math.max(4, Math.min(cx - w / 2, ctx.width - 4 - w))

// The tick plan: which years are drawn and which are labelled (the multiples of a longer step), in how many rows. A label is wider than most
// steps, so the labelled ticks are those of a step that keeps them apart (two rows on a phone); a line too short for two such labels is
// labelled at its two ends.
function tickPlan(ctx, from, to, every, k, x0, labelW) {
  const rows = ctx.width < 600 ? 2 : 1
  const xOf = (y) => x0 + (position(y) - position(from)) * k
  const fits = (list) => {
    const lastX = new Array(rows).fill(-Infinity)
    return list.every((y, j) => {
      const left = tickLeft(ctx, xOf(y), labelW)
      const ok = left >= lastX[j % rows] + 8
      lastX[j % rows] = left + labelW
      return ok
    })
  }
  const plan = (all, labelled) => ({ all, labelled, rows, xOf })
  if (every) {
    const all = ticks(from, to, every)
    for (let m = 1; m <= 40; m++) {
      const lab = ticks(from, to, every * m)
      if (lab.length < 2) break
      if (fits(lab)) return plan(all, lab)
    }
  } else {
    for (const step of STEPS) {
      const lab = ticks(from, to, step)
      if (lab.length >= 2 && fits(lab)) return plan(lab, lab)
    }
  }
  const ends = [Number(from), Number(to)]
  return fits(ends) ? plan(ends, ends) : plan([ends[0]], [ends[0]])
}

export function buildYears(data, ctx, eff) {
  const W = ctx.width
  const f = ctx.fontPx
  const lineH = ctx.lineH
  const select = ctx.mode === "select"
  const set = ctx.set ?? ctx.targetSet
  const r = Math.round(f * 0.55)
  const tickW = Math.ceil(Math.max(...[eff.from, eff.to, "-888", "888"].map((y) => ctx.measure(yearLabel(y), f).w)))
  const mx = Math.max(16, Math.round(f * 0.9))
  const x0 = mx
  const x1 = W - mx
  const t0 = position(eff.from)
  const t1 = position(eff.to)
  const k = (x1 - x0) / (t1 - t0)
  const xOf = (y) => x0 + (position(y) - t0) * k
  const roles = []
  const hits = []
  let y = 6

  // century bands: drawn when most of them can say their name
  if (eff.centuries && !select) {
    const bandH = lineH + 6
    const list = centuries(eff.from, eff.to).map((c, i) => {
      const a = x0 + (c.lo - t0) * k
      const b = x0 + (c.hi - t0) * k
      const short = `${c.n} ${c.bc ? TEXT.era_bc : TEXT.era_ad}`
      return { c, i, a, b, pick: [c.text, short].find((t) => ctx.measure(t, f).w + 8 <= b - a) }
    })
    if (list.filter((q) => q.pick).length * 2 >= list.length) {
      for (const q of list) {
        shape(ctx, "rect", { x: q.a, y, w: q.b - q.a, h: bandH, r: 0, cls: `dg-tl-band dg-tl-band-${q.i % 2}`, key: `band:${q.i}` })
        if (q.pick) label(ctx, q.pick, (q.a + q.b) / 2, y + 3, { anchor: "middle", cls: "dg-tl-bandlabel", key: `band:${q.i}:label` })
      }
      y += bandH + 8
    }
  }

  // periods: bars in rows, the label inside when it fits and under the bar when it does not
  const periods = eff.periods ?? []
  if (periods.length) {
    const barH = lineH + 8
    const rowsEnd = []
    const placed = periods.map((p, i) => {
      const a = Math.max(x0, xOf(p.from))
      const b = Math.min(x1, xOf(p.to))
      const text = plain(p.label_it)
      const need = Math.ceil(ctx.measure(text, f).w) + Math.round(f * 0.8) + 30 // marker, paddings and a little room so that the label never wraps inside its bar
      const inner = b - a >= need
      let row = rowsEnd.findIndex((end) => end <= a - 6)
      if (row < 0) row = rowsEnd.length
      rowsEnd[row] = inner ? b : Math.max(b, Math.min(a + need, x1))
      return { p, i, a, b, text, inner, row }
    })
    const outsideH = Math.max(0, ...placed.filter((q) => !q.inner).map((q) => ctx.measure(q.text, f, W - 12).h + 2))
    const rowH = barH + outsideH + 6
    for (const q of placed) {
      const top = y + q.row * rowH
      const role = q.p.role ?? "muted"
      roles.push(q.p.role)
      shape(ctx, "rect", { x: q.a, y: top, w: Math.max(q.b - q.a, 2), h: barH, r: 8, cls: `dg-tl-period mk-${role}`, key: `pd:${q.i + 1}`, ...(select && set === "periods" ? { target: `t${q.i + 1}` } : {}) })
      if (select) continue
      const sz = Math.round(f * 0.8)
      shape(ctx, "marker", { shape: shapeOf(ctx, role), x: q.a + 8, y: top + (barH - sz) / 2, w: sz, h: sz, cls: `mk-${role} dg-tl-periodmark`, key: `pd:${q.i + 1}:mark` })
      const tx = q.a + 8 + sz + 6
      if (q.inner) label(ctx, q.text, tx, top + 4, { anchor: "start", maxW: q.b - tx - 6, cls: "dg-tl-periodlabel", key: `pd:${q.i + 1}:label` })
      else label(ctx, q.text, Math.max(6, Math.min(q.a, W - 6 - Math.ceil(Math.min(ctx.measure(q.text, f, W - 12).w, W - 12)))), top + barH + 2, { anchor: "start", maxW: W - 12, cls: "dg-tl-periodlabel dg-tl-outside", key: `pd:${q.i + 1}:label` })
    }
    y += (Math.max(...placed.map((q) => q.row)) + 1) * rowH
  }

  // lanes with their events
  const lanes = eff.lanes?.length ? eff.lanes : [{ id: null, label_it: null }]
  const events = eff.events ?? []
  const picks = ctx.controls?.measure ?? []
  const maxLabelW = Math.min(W - 16, Math.round(f * 8.5))
  const baselines = []
  for (const lane of lanes) {
    if (lane.label_it && !select) {
      const item = label(ctx, plain(lane.label_it), 8, y, { anchor: "start", maxW: W - 16, cls: "dg-tl-lane-label", key: `lane:${lane.id}` })
      y += item.h + 2
    }
    const mine = events.filter((e) => (lane.id ? e.lane === lane.id : true))
    const specs = select ? [] : mine.map((e) => ({
      text: `${eventYearLabel(e)}: ${plain(e.label_it)}`, cx: xOf(e.at), cls: `dg-tl-evlabel dg-tl-plate${e.role ? ` role-${e.role}` : ""}`, role: e.role, maxW: maxLabelW, key: `ev:${e.id}:label`, connectFrom: 0
    }))
    const lines = Math.max(1, ...specs.map((sp) => Math.round(ctx.measure(sp.text, f, sp.maxW).h / lineH)))
    for (const sp of specs) sp.lines = lines
    // a dry run for the height of the stack above the line
    const scratch = { ...ctx, labels: [], shapes: [] }
    const used = specs.length ? stackLabels(scratch, specs.map((s) => ({ ...s, connectFrom: 0 })), 1000, -1) : 0
    const base = y + (used ? used + 8 : 0) + r + 6
    baselines.push(base)
    for (const s of specs) s.connectFrom = base - r - 2
    if (specs.length) stackLabels(ctx, specs, base - r - 8, -1)
    shape(ctx, "line", { x1: x0, y1: base, x2: x1, y2: base, cls: lanes.length === 1 ? "dg-tl-axis" : "dg-tl-laneline", key: `lane:${lane.id ?? "main"}:line` })
    for (const e of mine) {
      const cx = xOf(e.at)
      const role = e.role ?? "muted"
      roles.push(e.role)
      const index = events.indexOf(e)
      const isPicked = picks.includes(e.id)
      if (e.approx && !select) shape(ctx, "circle", { cx, cy: base, r: r + 5, cls: "dg-tl-approx", key: `ev:${e.id}:approx` })
      if (isPicked) shape(ctx, "circle", { cx, cy: base, r: r + 6, cls: "dg-tl-picked", key: `ev:${e.id}:picked` })
      shape(ctx, "marker", { shape: shapeOf(ctx, select ? "muted" : role), x: cx - r, y: base - r, w: 2 * r, h: 2 * r, cls: `mk-${select ? "muted" : role} dg-tl-event`, key: `ev:${e.id}` })
      if (select && set === "events") {
        const sz = Math.max(2 * r + 8, 28)
        shape(ctx, "rect", { x: cx - sz / 2, y: base - sz / 2, w: sz, h: sz, r: 6, cls: "dg-tl-hit", key: `ev:${e.id}:target`, target: `t${index + 1}` })
      }
      if (e.note_it && !select) {
        const sz = Math.max(2 * r + 8, 28)
        hits.push({ key: `ev:${e.id}`, id: e.id, x: cx - sz / 2, y: base - sz / 2, w: sz, h: sz, name: plain(e.label_it), text: e.note_it, note_it: e.note_it, hint_it: TEXT.note_hint })
      }
    }
    y = base + r + 10
  }

  // the axis: ticks and their labels (the lane line is the axis when there is one lane)
  const axisY = lanes.length === 1 ? baselines[0] : y + 4
  if (lanes.length > 1) shape(ctx, "line", { x1: x0, y1: axisY, x2: x1, y2: axisY, cls: "dg-tl-axis", key: "axis" })
  const plan = tickPlan(ctx, eff.from, eff.to, eff.every, k, x0, tickW)
  const dense = (plan.all.length > 1 ? (xOf(plan.all[1]) - xOf(plan.all[0])) : 99) >= 5
  const tickTop = axisY
  for (const yr of dense ? plan.all : plan.labelled) {
    const labelled = plan.labelled.includes(yr)
    shape(ctx, "line", { x1: xOf(yr), y1: tickTop, x2: xOf(yr), y2: tickTop + (labelled ? 12 : 7), cls: `dg-tl-tick${labelled ? " dg-tl-tick-major" : ""}`, key: `tick:${yr}` })
  }
  if (Number(eff.from) < 0 && Number(eff.to) > 0) {
    const ex = x0 + (-0.5 - t0) * k
    shape(ctx, "line", { x1: ex, y1: tickTop - 8, x2: ex, y2: tickTop + 18, cls: "dg-tl-era", key: "era" })
  }
  plan.labelled.forEach((yr, j) => {
    const text = yearLabel(yr)
    const w = Math.ceil(ctx.measure(text, f).w)
    label(ctx, text, tickLeft(ctx, xOf(yr), w), tickTop + 14 + (j % plan.rows) * lineH, { anchor: "start", cls: "dg-tl-ticklabel", key: `tick:${yr}:label` })
  })
  y = tickTop + 14 + plan.rows * lineH + 8

  // spans (and the measured pair), brackets under the ticks
  const bracketed = []
  if (!select) {
    for (const s of eff.spans ?? []) {
      const a = events.find((e) => e.id === s.from)
      const b = events.find((e) => e.id === s.to)
      if (a && b) bracketed.push({ a, b, text: s.show_value ? durationText(duration(a.at, b.at)) : null, key: `span:${s.from}>${s.to}`, cls: "dg-tl-span" })
    }
    const pair = measured(eff, ctx.controls)
    if (pair) bracketed.push({ a: pair[0], b: pair[1], text: durationText(duration(pair[0].at, pair[1].at)), key: "measure", cls: "dg-tl-span dg-tl-measure" })
  }
  const rowEnd = []
  for (const s of bracketed) {
    const a = xOf(s.a.at)
    const b = xOf(s.b.at)
    const w = s.text ? Math.ceil(ctx.measure(s.text, f).w) + 12 : 0
    const lo = Math.min(a, (a + b) / 2 - w / 2)
    const hi = Math.max(b, (a + b) / 2 + w / 2)
    let row = rowEnd.findIndex((end) => end <= lo - 6)
    if (row < 0) row = rowEnd.length
    rowEnd[row] = hi
    s.row = row
  }
  const spanRowH = lineH + 16
  for (const s of bracketed) {
    const top = y + s.row * spanRowH
    const a = xOf(s.a.at)
    const b = xOf(s.b.at)
    shape(ctx, "path", { d: `M${a} ${top} V${top + 10} H${b} V${top}`, cls: s.cls, key: s.key })
    if (s.text) {
      const w = Math.ceil(ctx.measure(s.text, f).w)
      label(ctx, s.text, Math.max(4, Math.min((a + b) / 2 - w / 2, W - 4 - w)), top + 12, { anchor: "start", cls: "dg-tl-spanlabel", key: `${s.key}:label` })
    }
  }
  if (bracketed.length) y += (Math.max(...bracketed.map((s) => s.row)) + 1) * spanRowH + 2

  // the measure's own words
  let live = null
  if (eff.measure && !select) {
    const pair = measured(eff, ctx.controls)
    const text = pair ? fill(TEXT.measure_result, { a: plain(pair[0].label_it), b: plain(pair[1].label_it), n: durationText(duration(pair[0].at, pair[1].at)) })
      : picks.length > 2 ? TEXT.measure_too_many : TEXT.measure_pick
    const item = label(ctx, text, 8, y, { anchor: "start", maxW: W - 16, cls: "dg-tl-readout", key: "readout" })
    y += item.h + 6
    live = pair ? text : null
  }
  if (!select) y = legendRow(ctx, [...roles], y)
  return { bottom: y + 2, hits, live }
}
