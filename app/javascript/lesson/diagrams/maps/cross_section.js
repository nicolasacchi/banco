// cross_section (T5, W2-1, D-272): a section of the ground, `points` [[x, altitude in m]] exact, features, belts of altitude, and with `lapse`
// the temperature at each belt edge and under the altitude stepper, computed (base_temp - per_km * altitude / 1000). The vertical
// exaggeration is computed from the data (the largest "nice" number that keeps the drawing about half as high as wide) and always printed:
// "altezze esagerate 15 volte". Ruby twin: lib/lessons/diagrams/cross_section.rb; both run test/fixtures/diagrams/types/cross_section.json.
// Select targets: `belts` (stored "alt:FROM:TO", highest first); in select mode the belts are neutral: no label, no number, no temperature.
import schema from "lesson/diagram_schemas/cross_section"
import * as N from "lesson/num"
import * as G from "lesson/diagrams/maps/geo"
import { finish, label, shape } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const type = "cross_section"
export { schema }

const ASPECT = 0.5
const NICE = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 80, 100, 120, 150, 200, 250, 300, 400, 500, 600, 800, 1000, 1500, 2000, 2500, 3000, 5000, 10000]
const ALT_MIN = -12000
const ALT_MAX = 9000
const KIND_SHAPE = { peak: "triangle", city: "box", river: "circle", sea: "diamond", plain: "square", plateau: "weight" }

// ---- the numbers (the mirror of Lessons::Diagrams::CrossSection) ----------------------------------------------------------------

const pts = (data) => (data.points ?? []).map(([x, a]) => [N.parse(x), N.parse(a)])
const xTo = (data) => N.parse(data.x?.to)
const xMetres = (data) => {
  const t = xTo(data)
  return t && N.mul(t, N.int(data.x.unit === "km" ? 1000 : 1))
}
const maxOf = (list) => list.reduce((m, v) => (N.compare(v, m) > 0 ? v : m))
const minOf = (list) => list.reduce((m, v) => (N.compare(v, m) < 0 ? v : m))
const top = (data) => maxOf(pts(data).map((p) => p[1]))
const bottom = (data) => minOf([...pts(data).map((p) => p[1]), N.int(0)])

export function exaggeration(data) {
  const xm = xMetres(data)
  const span = N.sub(top(data), bottom(data))
  if (!xm || N.compare(xm, N.int(0)) <= 0 || N.compare(span, N.int(0)) <= 0) return 1
  const raw = (ASPECT * N.toNumber(xm)) / N.toNumber(span)
  return NICE.filter((v) => v <= raw).reduce((m, v) => Math.max(m, v), 1)
}

export const exaggerationText = (data) => {
  const e = exaggeration(data)
  return e === 1 ? "altezze in scala" : `altezze esagerate ${e} volte`
}

export function temp(data, alt) {
  const l = data.lapse
  if (!l) return null
  return N.sub(N.parse(l.base_temp), N.div(N.mul(N.parse(l.per_km), alt), N.int(1000)))
}
const tempStr = (data, alt) => {
  const t = temp(data, alt)
  return t === null ? null : `${G.fmt1(t, { trim: true })} °C`
}

// The altitudes of the stepper: every 500 m up to 4000 m of height, every 1000 m above, from 0, and the top.
export function stepperValues(data) {
  const t = top(data)
  const tn = Math.trunc(N.toNumber(t))
  const step = N.compare(t, N.int(4000)) <= 0 ? 500 : 1000
  const out = []
  for (let v = 0; v <= Math.floor(N.toNumber(t)); v += step) out.push(v)
  if (!out.includes(tn)) out.push(tn)
  return out.filter((v) => v >= 0)
}

function altOf(data, controls) {
  const vals = stepperValues(data)
  const want = controls?.alt !== undefined ? Number(controls.alt) : 0
  if (vals.includes(want)) return want
  return vals.reduce((best, v) => (Math.abs(v - want) < Math.abs(best - want) ? v : best), vals[0] ?? 0)
}

// ---- semantic checks --------------------------------------------------------------------------------------------------------------------

export function semanticAll(data) {
  const out = []
  const add = (path, message) => out.push({ path, message })
  const xt = xTo(data)
  if (!(xt && N.compare(xt, N.int(0)) > 0)) add("/x/to", "x goes from 0 to a positive length")
  const ps = pts(data)
  if (ps.some(([x, a]) => x === null || a === null)) {
    add("/points", "every point is [x, altitude] with exact numbers")
    return out
  }
  const xs = ps.map((p) => p[0])
  const increasing = xs.every((x, i) => i === 0 || N.compare(xs[i - 1], x) < 0)
  if (!(N.isZero(xs[0]) && xt && N.eq(xs[xs.length - 1], xt) && increasing)) add("/points", `the points go from the left edge (x = 0) to the right edge (x = ${data.x?.to}), x always increasing`)
  ps.forEach(([, a], i) => {
    if (!(N.compare(a, N.int(ALT_MIN)) >= 0 && N.compare(a, N.int(ALT_MAX)) <= 0)) add(`/points/${i}`, `an altitude is between ${ALT_MIN} and ${ALT_MAX} m`)
  })
  const flat = N.compare(top(data), bottom(data)) <= 0
  if (flat) add("/points", "the highest point must be above the lowest (a flat section has nothing to show)")
  const xm = xMetres(data)
  if (xm && N.compare(xm, N.int(0)) > 0 && !flat && N.compare(N.div(N.sub(top(data), bottom(data)), xm), N.int(1)) > 0) add("/points", "the section is too steep to draw to scale (more than 45 degrees on average): lengthen x or lower the peaks")
  ;(data.features ?? []).forEach((f, i) => {
    const v = N.parse(f.at)
    if (!(v && xt && N.compare(v, N.int(0)) >= 0 && N.compare(v, xt) <= 0)) add(`/features/${i}/at`, `a feature lies between 0 and ${data.x?.to}`)
    lab(add, `/features/${i}/label_it`, f.label_it)
  })
  const l = data.lapse
  if (l) {
    const p = N.parse(l.per_km)
    if (!(p && N.compare(p, N.int(0)) > 0)) add("/lapse/per_km", "per_km is above 0 (degrees lost every 1000 m)")
    if (!N.parse(l.base_temp)) add("/lapse/base_temp", "base_temp is a number")
  }
  if (data.stepper && !l) add("/stepper", "the altitude stepper needs lapse (the temperature it reads)")
  beltsCheck(data, add, "", data.belts ?? [])
  ;(data.states ?? []).forEach((s, i) => {
    if (s && typeof s === "object" && "belts" in s) beltsCheck(data, add, `/states/${i}`, s.belts ?? [])
  })
  return out
}
export const semantic = (data) => semanticAll(data)[0] ?? null

const lab = (add, path, text) => {
  if (text !== undefined && String(text).trim().split(/\s+/).length > 6) add(path, "a label has more than 6 words")
}

function beltsCheck(data, add, path, list) {
  const lo = bottom(data)
  const hi = top(data)
  const parsed = list.map((b, i) => {
    const at = `${path}/belts/${i}`
    const a = N.parse(b.from_alt)
    const z = N.parse(b.to_alt)
    if (!(a && z && N.compare(a, z) < 0 && N.compare(a, lo) >= 0 && N.compare(z, hi) <= 0)) add(at, `a belt goes from a lower to a higher altitude, inside the section (${Math.trunc(N.toNumber(lo))} to ${Math.trunc(N.toNumber(hi))} m)`)
    lab(add, `${at}/label_it`, b.label_it)
    return [a, z]
  })
  const valid = parsed.filter(([a, z]) => a && z).sort((p, q) => N.compare(p[0], q[0]) || N.compare(p[1], q[1]))
  for (let i = 1; i < valid.length; i++) if (N.compare(valid[i][0], valid[i - 1][1]) < 0) add(`${path}/belts`, "two belts overlap")
}

// ---- describe, printed, reachable, controls --------------------------------------------------------------------------------------------

export function describe(data, ctx = {}) {
  const eff = G.effective(data, ctx.state ?? 0)
  const u = data.x.unit
  const belts = eff.belts ?? []
  if (ctx.mode === "select") return `Una sezione del terreno lunga ${G.fmt(xTo(data))} ${u}, con ${belts.length} fasce da toccare. ${exaggerationText(data)}.`
  const out = [`Sezione del terreno, lunga ${G.fmt(xTo(data))} ${u}. La quota va da ${G.fmt(bottom(data))} a ${G.fmt(top(data))} m. ${G.capital(exaggerationText(data))}.`]
  for (const f of data.features ?? []) out.push(`${G.capital(f.label_it)}, a ${G.fmt(N.parse(f.at))} ${u}.`)
  for (const b of belts) {
    const a = N.parse(b.from_alt)
    const z = N.parse(b.to_alt)
    out.push(`Fascia ${b.label_it}: da ${G.fmt(a)} a ${G.fmt(z)} m${data.lapse ? ` (da ${tempStr(data, a)} a ${tempStr(data, z)})` : ""}.`)
  }
  if (data.lapse) {
    out.push(`Con la quota la temperatura scende di ${G.fmt(N.parse(data.lapse.per_km))} °C ogni 1000 m.`)
    if (data.stepper) {
      const alt = N.int(altOf(data, ctx.controls))
      out.push(`A ${G.fmt(alt)} m: ${tempStr(data, alt)}.`)
    }
  }
  if (eff.op_it) out.push(`${eff.op_it}.`)
  return out.join(" ")
}

export function printed(data, state = 0) {
  const eff = G.effective(data, state)
  const out = [describe(data, { state }), exaggerationText(data), ...(data.features ?? []).map((f) => f.label_it)]
  for (const b of eff.belts ?? []) {
    out.push(b.label_it)
    if (data.lapse) out.push(tempStr(data, N.parse(b.from_alt)), tempStr(data, N.parse(b.to_alt)))
  }
  if (eff.op_it) out.push(eff.op_it)
  if (data.caption_it) out.push(data.caption_it)
  return [...new Set(out.filter(Boolean))]
}

export function reachable(data) {
  if (!data.stepper || !data.lapse) return []
  const all = [...new Set(stepperValues(data).flatMap((a) => [`${a} m`, tempStr(data, N.int(a))]))]
  return all.length > 500 ? null : all
}

export function controls(data) {
  if (!data.stepper || !data.lapse) return []
  const values = stepperValues(data)
  return [{ id: "alt", kind: "stepper", values, label_it: "Quota", format: "alt", initial: 0 }]
}

// The belts, highest first: [{ key: "t1", id: "alt:FROM:TO", neutral_it }].
export function targets(data, set) {
  if (set !== "belts") return []
  const eff = G.effective(data, 0)
  const list = (eff.belts ?? []).map((b) => ({ id: `alt:${b.from_alt}:${b.to_alt}`, from: N.parse(b.from_alt), to: N.parse(b.to_alt) }))
  list.sort((a, b) => N.compare(b.from, a.from) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
  return list.map((t, i) => ({ key: `t${i + 1}`, id: t.id, bbox: [0, N.toNumber(t.from), N.toNumber(xTo(data)), N.toNumber(t.to)], neutral_it: `fascia ${i + 1} di ${list.length}, contando dall'alto` }))
}

// ---- geometry ---------------------------------------------------------------------------------------------------------------------------

// Sutherland-Hodgman against the half-planes alt >= lo and alt <= hi on a polygon of [x, alt].
function clipBand(poly, lo, hi) {
  const clip = (input, inside, cross) => {
    const out = []
    for (let i = 0; i < input.length; i++) {
      const a = input[i]
      const b = input[(i + 1) % input.length]
      const ia = inside(a)
      const ib = inside(b)
      if (ia) out.push(a)
      if (ia !== ib) out.push(cross(a, b))
    }
    return out
  }
  const at = (a, b, alt) => [a[0] + ((b[0] - a[0]) * (alt - a[1])) / (b[1] - a[1]), alt]
  let r = clip(poly, (p) => p[1] >= lo, (a, b) => at(a, b, lo))
  if (r.length) r = clip(r, (p) => p[1] <= hi, (a, b) => at(a, b, hi))
  return r
}

// The rightmost x at which the profile has altitude alt (null when it never does).
function rightCross(points, alt) {
  let best = null
  for (let i = 0; i + 1 < points.length; i++) {
    const [x1, a1] = points[i]
    const [x2, a2] = points[i + 1]
    if ((a1 - alt) * (a2 - alt) <= 0 && a1 !== a2) {
      const x = x1 + ((x2 - x1) * (alt - a1)) / (a2 - a1)
      best = best === null ? x : Math.max(best, x)
    } else if (a1 === alt && a2 === alt) best = Math.max(best ?? x2, x2)
  }
  return best
}

const altAt = (points, x) => {
  for (let i = 0; i + 1 < points.length; i++) {
    const [x1, a1] = points[i]
    const [x2, a2] = points[i + 1]
    if (x >= x1 && x <= x2) return x2 === x1 ? Math.max(a1, a2) : a1 + ((a2 - a1) * (x - x1)) / (x2 - x1)
  }
  return points[points.length - 1][1]
}

const niceTick = (span, room, lineH) => {
  for (const step of [100, 200, 250, 500, 1000, 2000, 2500, 5000]) if ((span / step) * (lineH + 4) <= room) return step
  return 5000
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

function build(data, ctx) {
  const eff = G.effective(data, ctx.state)
  const select = ctx.mode === "select"
  const f = ctx.fontPx
  const W = ctx.width
  const xt = N.toNumber(xTo(data))
  const unit = data.x.unit
  const xm = N.toNumber(xMetres(data))
  const T = N.toNumber(top(data))
  const B = N.toNumber(bottom(data))
  const e = exaggeration(data)
  const points = pts(data).map(([x, a]) => [N.toNumber(x), N.toNumber(a)])
  const belts = (eff.belts ?? []).map((b, i) => ({ b, from: N.toNumber(N.parse(b.from_alt)), to: N.toNumber(N.parse(b.to_alt)), i }))
  const r = Math.ceil(f * 0.75)

  // the margins: the altitudes on the left, the numbered belts on the right, the features above, the x axis and the exaggeration below
  const axisW = ctx.measure(String(Math.max(Math.abs(Math.round(T)), Math.abs(Math.round(B)))), f).w + 14
  const LM = axisW + 18
  const RM = select || belts.length === 0 ? 12 : 2 * r + 12
  const PW = Math.max(120, W - LM - RM)
  const PH = Math.round(((e * (T - B)) / xm) * PW)

  // the features: a label above its point; rows when they would touch
  const feats = select ? [] : (data.features ?? []).map((ft) => ({ ft, x: N.toNumber(N.parse(ft.at)) })).sort((a, c) => a.x - c.x)
  const rowsEnd = []
  const placedFeats = feats.map((it) => {
    const w = Math.ceil(ctx.measure(it.ft.label_it, f).w)
    const cx = LM + (it.x / xt) * PW
    const lo = w <= PW ? LM : 2 // a feature label stays over the plot, clear of the altitudes and of the numbered belts
    const hi = w <= PW ? W - RM - w : W - w - 2
    const left = Math.max(lo, Math.min(cx - w / 2, hi))
    let row = 0
    while (rowsEnd[row] !== undefined && left < rowsEnd[row] + 6) row += 1
    rowsEnd[row] = left + w
    return { ...it, w, left, cx, row }
  })
  const rows = rowsEnd.length
  const featH = rows ? rows * (ctx.lineH + 4) + 14 : 10
  const topY = Math.round(ctx.lineH + Math.max(featH, ctx.lineH / 2 + 8)) // the title of the axis, then the feature rows, then the profile's top
  const Y = (alt) => topY + ((T - alt) / (T - B)) * PH
  const X = (x) => LM + (x / xt) * PW
  const bottomY = topY + PH

  // axis title and ticks
  label(ctx, "Quota (m)", 2, 0, { anchor: "start", cls: "dg-axis-title" })
  const tick = niceTick(T - B, PH, ctx.lineH)
  shape(ctx, "line", { x1: LM, y1: topY, x2: LM, y2: bottomY, cls: "dg-axis" })
  shape(ctx, "line", { x1: LM, y1: bottomY, x2: LM + PW, y2: bottomY, cls: "dg-axis" })
  for (let a = Math.ceil(B / tick) * tick; a <= T; a += tick) {
    shape(ctx, "line", { x1: LM - 5, y1: Y(a), x2: LM, y2: Y(a), cls: "dg-tick" })
    shape(ctx, "line", { x1: LM, y1: Y(a), x2: LM + PW, y2: Y(a), cls: "dg-grid" })
    label(ctx, String(a), LM - 8, Y(a), { anchor: "end", valign: "middle", cls: "dg-tick-label" })
  }
  const xtext = (x, last) => `${G.fmt(N.parse(String(Math.round(x * 10) / 10).replace(".", ",")))}${last ? ` ${unit}` : ""}`
  const first = label(ctx, xtext(0, false), X(0), bottomY + 6, { anchor: "start", cls: "dg-tick-label" })
  const lastL = label(ctx, xtext(xt, true), X(xt), bottomY + 6, { anchor: "end", cls: "dg-tick-label" })
  const midW = Math.ceil(ctx.measure(xtext(xt / 2, false), f).w)
  const midX = Math.round(X(xt / 2) - midW / 2)
  if (midX > first.x + first.w + 8 && midX + midW + 8 < lastL.x) label(ctx, xtext(xt / 2, false), X(xt / 2), bottomY + 6, { anchor: "middle", cls: "dg-tick-label" })

  // the ground and the belts
  const ground = [...points, [xt, B], [0, B]]
  const toPx = (poly) => poly.map(([x, a]) => [X(x), Y(a)])
  const dOf = (poly) => `M${toPx(poly).map(([x, y]) => `${x.toFixed(1)} ${y.toFixed(1)}`).join("L")}Z`
  shape(ctx, "path", { d: dOf(ground), cls: "dg-ground" })
  const bandRoles = belts.map((b) => ({ role: b.b.role }))
  const targetsOut = []
  const tlist = select ? targets(data, "belts") : []
  // in select mode the targets are drawn, and so focused, highest first
  ;(select ? [...belts].sort((a, c) => c.from - a.from) : belts).forEach((bt) => {
    const poly = clipBand(ground, bt.from, bt.to)
    if (poly.length < 3) return
    if (select) {
      const t = tlist.find((x) => x.id === `alt:${bt.b.from_alt}:${bt.b.to_alt}`)
      shape(ctx, "path", { d: dOf(poly), cls: "dg-cand dg-cand-band", target: t.key, targetLabel: t.neutral_it })
      targetsOut.push({ key: t.key, bbox: t.bbox, neutral_it: t.neutral_it })
      shape(ctx, "text", { x: X(poly.reduce((s, p) => s + p[0], 0) / poly.length), y: Y((bt.from + bt.to) / 2) + 5, px: f, text: String(t.key.slice(1)), cls: "dg-tnum" })
    } else {
      const role = bt.b.role ?? "muted"
      shape(ctx, "path", { d: dOf(poly), cls: `dg-belt mk-${role}`, pattern: G.patternOf(bandRoles, bt.i), role })
    }
  })
  if (!select) {
    for (const bt of belts) for (const a of [bt.from, bt.to]) if (a > B && a < T) shape(ctx, "line", { x1: LM, y1: Y(a), x2: LM + PW, y2: Y(a), cls: "dg-belt-edge" })
  }
  shape(ctx, "path", { d: `M${toPx(points).map(([x, y]) => `${x.toFixed(1)} ${y.toFixed(1)}`).join("L")}`, cls: "dg-profile" })
  if (B < 0) shape(ctx, "line", { x1: LM, y1: Y(0), x2: LM + PW, y2: Y(0), cls: "dg-sealevel" })

  // the features
  for (const it of placedFeats) {
    const ay = Y(altAt(points, it.x))
    const ly = Math.round(ctx.lineH + 4 + (rows - 1 - it.row) * (ctx.lineH + 4))
    label(ctx, it.ft.label_it, it.left, ly, { anchor: "start", cls: "dg-name" })
    shape(ctx, "line", { x1: it.cx, y1: ly + ctx.lineH, x2: it.cx, y2: ay - 7, cls: "dg-connector" })
    shape(ctx, "marker", { shape: KIND_SHAPE[it.ft.kind] ?? "circle", x: it.cx - 7, y: ay - 14, w: 14, h: 14, cls: "dg-feature mk-muted" })
  }

  // the numbered belts at the right, each at the height of its middle, kept apart; a leader to the belt
  const legend = []
  if (!select && belts.length) {
    const spots = belts.map((bt) => ({ bt, y: Y((bt.from + bt.to) / 2) })).sort((a, c) => a.y - c.y)
    let lastY = -Infinity
    for (const s of spots) {
      s.by = Math.max(s.y, lastY + 2 * r + 2)
      lastY = s.by
    }
    const over = spots.length ? spots[spots.length - 1].by - (bottomY + r) : 0
    if (over > 0) for (const s of spots) s.by -= over
    const bx = LM + PW + r + 6
    spots.forEach((s) => {
      const n = s.bt.i + 1
      const mid = (s.bt.from + s.bt.to) / 2
      const xr = rightCross(points, mid)
      if (xr !== null) {
        shape(ctx, "line", { x1: X(xr), y1: Y(mid), x2: bx - r, y2: s.by, cls: "dg-leader" })
        shape(ctx, "circle", { cx: X(xr), cy: Y(mid), r: 3, cls: "dg-leader-dot" })
      }
      shape(ctx, "circle", { cx: bx, cy: s.by, r, cls: "dg-badge" })
      label(ctx, String(n), bx, s.by, { anchor: "middle", valign: "middle", cls: "dg-callout" })
    })
    for (const bt of belts) {
      const temps = data.lapse ? `, da ${tempStr(data, N.int(bt.from))} a ${tempStr(data, N.int(bt.to))}` : ""
      legend.push({ n: bt.i + 1, text_it: `${bt.b.label_it}: da ${G.fmt(N.parse(bt.b.from_alt))} a ${G.fmt(N.parse(bt.b.to_alt))} m${temps}`, swatch: { kind: "area", role: bt.b.role ?? "muted", pattern: G.patternOf(bandRoles, bt.i) } })
    }
  }

  // the exaggeration, always said; the altitude stepper's reading under it
  const exag = G.capital(exaggerationText(data))
  let rowY = bottomY + 6 + ctx.lineH + 6
  const exagLabel = label(ctx, exag, 2, rowY, { anchor: "start", cls: "dg-exag", maxW: W - 4 })
  rowY += exagLabel.h + 4
  let live = ""
  if (!select && data.stepper && data.lapse) {
    const alt = altOf(data, ctx.controls)
    shape(ctx, "line", { x1: LM, y1: Y(alt), x2: LM + PW, y2: Y(alt), cls: "dg-stepline" })
    shape(ctx, "circle", { cx: LM + PW - 4, cy: Y(alt), r: 5, cls: "dg-stepdot" })
    const text = `A ${alt} m: ${tempStr(data, N.int(alt))}`
    const readout = label(ctx, text, 2, rowY, { anchor: "start", cls: "dg-readout-label", maxW: W - 4 })
    rowY += readout.h + 4
    live = `${text}.`
  }
  return finish(ctx, rowY, { legend, targets: targetsOut, live, states: Array.isArray(data.states) ? data.states.length : 1, state: ctx.state })
}
