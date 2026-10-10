// number_line (A7): an axis with ticks, marks (dot, open, closed, cross), jumps (arcs with a label) and
// intervals (a thick bar, open or closed ends, an arrow for infinity). Exact numbers (num.js); floats
// only for pixel positions. Tick labels thin out (every k-th, keeping 0) when they would touch.
import * as N from "lesson/num"
import { effectiveState, finish, label, listIt, plain, shape, stackLabels, stateCount, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const states = stateCount

function range(data) {
  const lo = N.parse(data.min)
  const hi = N.parse(data.max)
  const step = N.parse(data.step)
  return { lo, hi, step }
}

export function semantic(data) {
  const { lo, hi, step } = range(data)
  if (N.compare(lo, hi) >= 0) return { path: "/min", message: "min must be below max" }
  if (N.compare(step, N.int(0)) <= 0) return { path: "/step", message: "step must be positive" }
  const count = N.div(N.sub(hi, lo), step)
  if (!N.isInteger(count) || count.n > 30n) return { path: "/step", message: "(max - min) / step must be an integer, at most 30" }
  let err = null
  const flag = (e) => {
    err ??= e
  }
  const inside = (x) => N.compare(x, lo) >= 0 && N.compare(x, hi) <= 0
  for (let j = -1; j < (data.states ? data.states.length : 0); j++) {
    const base = j < 0 ? "" : `/states/${j}`
    const src = j < 0 ? data : data.states[j]
    ;(src.marks ?? []).forEach((m, i) => {
      if (!inside(N.parse(m.at))) flag({ path: `${base}/marks/${i}/at`, message: "a mark lies outside the line" })
    })
    ;(src.jumps ?? []).forEach((jm, i) => {
      const from = N.parse(jm.from)
      if (!inside(from) || !inside(N.add(from, N.parse(jm.by)))) flag({ path: `${base}/jumps/${i}`, message: "a jump starts or lands outside the line" })
    })
    ;(src.intervals ?? []).forEach((iv, i) => {
      const a = N.parse(iv.from, { allowInf: true })
      const b = N.parse(iv.to, { allowInf: true })
      const c = N.compare(a, b)
      if (c > 0 || (c === 0 && !(iv.from_closed && iv.to_closed))) flag({ path: `${base}/intervals/${i}`, message: "an interval runs from a number to a larger one" })
      for (const end of [a, b]) if (!N.isInf(end) && !inside(end)) flag({ path: `${base}/intervals/${i}`, message: "an interval ends outside the line" })
    })
  }
  if (err) return err
  for (let j = -1; j < (data.states ? data.states.length : 0); j++) {
    const src = j < 0 ? data : data.states[j]
    for (const [k, list] of [["marks", src.marks], ["jumps", src.jumps], ["intervals", src.intervals]]) {
      for (let i = 0; i < (list ?? []).length; i++) {
        if (words(list[i].label_it) > 6) return { path: `${j < 0 ? "" : `/states/${j}`}/${k}/${i}/label_it`, message: "a label has at most 6 words" }
      }
    }
  }
  return null
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const { lo, hi, step } = range(data)
  const W = ctx.width
  const f = ctx.fontPx
  const margin = Math.max(18, Math.round(f * 1.2))
  const x0 = margin
  const x1 = W - margin
  const span = N.toNumber(N.sub(hi, lo))
  const at = (v) => {
    if (N.isInf(v)) return v.inf > 0 ? x1 + margin - 4 : x0 - margin + 4
    return x0 + (N.toNumber(N.sub(v, lo)) / span) * (x1 - x0)
  }
  const count = Number(N.div(N.sub(hi, lo), step).n)

  // vertical plan: jump arcs above, axis, tick labels, then mark and interval labels
  const jumps = eff.jumps ?? []
  const arcRow = Math.round(f * 0.9) + 14
  const jumpLabelH = jumps.some((j) => j.label_it) ? ctx.lineH + 4 : 0
  const axisY = 14 + (jumps.length ? jumpLabelH + arcRow + (jumps.length - 1) * Math.round(arcRow * 0.55) : 6) + 10
  // axis and ticks
  shape(ctx, "line", { x1: x0, y1: axisY, x2: x1, y2: axisY, cls: "dg-axis" })
  const tickLabels = data.labels ?? "all"
  const texts = []
  for (let i = 0; i <= count; i++) {
    const v = N.add(lo, N.mul(step, N.int(i)))
    const x = x0 + (i / count) * (x1 - x0)
    shape(ctx, "line", { x1: x, y1: axisY - 5, x2: x, y2: axisY + 5, cls: "dg-tick" })
    texts.push({ i, x, text: N.format(v), zero: N.isZero(v) })
  }
  const maxW = Math.max(...texts.map((t) => ctx.measure(t.text, f).w)) + 10
  const pitch = (x1 - x0) / count
  let stride = 1
  if (tickLabels === "ends") stride = count
  else if (tickLabels === "marks") stride = Infinity
  else while (stride * pitch < maxW && stride < count) stride += 1
  const zeroIndex = texts.find((t) => t.zero)?.i ?? 0
  const marksAt = new Set((eff.marks ?? []).map((m) => N.canonical(N.parse(m.at))))
  let tickBottom = axisY + 8
  for (const t of texts) {
    const show = stride === Infinity ? marksAt.has(N.canonical(N.add(lo, N.mul(step, N.int(t.i))))) : tickLabels === "ends" ? t.i === 0 || t.i === count : (t.i - zeroIndex) % stride === 0
    if (!show) continue
    const l = label(ctx, t.text, t.x, axisY + 8, { cls: "dg-tick-label" })
    l.x = Math.max(0, Math.min(l.x, W - l.w))
    tickBottom = Math.max(tickBottom, l.y + l.h)
  }
  // intervals: thick bars on the axis
  for (const iv of eff.intervals ?? []) {
    const a = N.parse(iv.from, { allowInf: true })
    const b = N.parse(iv.to, { allowInf: true })
    const xa = at(a)
    const xb = at(b)
    const role = iv.role ?? "muted"
    shape(ctx, "line", { x1: xa, y1: axisY, x2: xb, y2: axisY, cls: `dg-interval st-${role}` })
    for (const [v, x, closed] of [[a, xa, iv.from_closed], [b, xb, iv.to_closed]]) {
      if (N.isInf(v)) shape(ctx, "polygon", { points: [[x, axisY], [x + (v.inf > 0 ? -10 : 10), axisY - 7], [x + (v.inf > 0 ? -10 : 10), axisY + 7]], cls: `mk-${role}` })
      else shape(ctx, "circle", { cx: x, cy: axisY, r: 7, cls: closed ? `mk-${role}` : `dg-open st-${role}` })
    }
  }
  // marks
  for (const m of eff.marks ?? []) {
    const x = at(N.parse(m.at))
    const role = m.role ?? "muted"
    const kind = m.kind ?? "dot"
    if (kind === "cross") {
      shape(ctx, "line", { x1: x - 6, y1: axisY - 6, x2: x + 6, y2: axisY + 6, cls: `dg-cross st-${role}` })
      shape(ctx, "line", { x1: x - 6, y1: axisY + 6, x2: x + 6, y2: axisY - 6, cls: `dg-cross st-${role}` })
    } else if (kind === "open") shape(ctx, "circle", { cx: x, cy: axisY, r: 7, cls: `dg-open st-${role}` })
    else {
      if (kind === "closed") shape(ctx, "circle", { cx: x, cy: axisY, r: 10, cls: `dg-ring st-${role}` })
      shape(ctx, "circle", { cx: x, cy: axisY, r: 6, cls: `mk-${role}` })
    }
  }
  // jumps: arcs above the axis, each higher than the one before when they overlap
  jumps.forEach((j, idx) => {
    const a = N.parse(j.from)
    const b = N.add(a, N.parse(j.by))
    const xa = at(a)
    const xb = at(b)
    const role = j.role ?? "muted"
    const lift = arcRow + idx * Math.round(arcRow * 0.55)
    const mid = (xa + xb) / 2
    shape(ctx, "path", { d: `M${xa},${axisY - 8} Q${mid},${axisY - 8 - lift * 1.7} ${xb},${axisY - 8}`, cls: `dg-jump st-${role}` })
    const dir = xb >= xa ? 1 : -1
    shape(ctx, "polygon", { points: [[xb, axisY - 6], [xb - 8 * dir, axisY - 16], [xb - 1 * dir, axisY - 17]], cls: `mk-${role}` })
    if (j.label_it) label(ctx, j.label_it, mid, axisY - 8 - lift * 0.85 - ctx.lineH - 2, { cls: `dg-note role-${role}`, role })
  })
  // labels of marks and intervals, in rows under the tick labels
  const specs = []
  for (const m of eff.marks ?? []) {
    if (m.label_it) specs.push({ text: m.label_it, cx: at(N.parse(m.at)), cls: `dg-note role-${m.role ?? "muted"}`, role: m.role, connectFrom: axisY + 8 })
  }
  for (const iv of eff.intervals ?? []) {
    if (iv.label_it) {
      const a = N.parse(iv.from, { allowInf: true })
      const b = N.parse(iv.to, { allowInf: true })
      specs.push({ text: iv.label_it, cx: (Math.max(at(a), x0) + Math.min(at(b), x1)) / 2, cls: `dg-note role-${iv.role ?? "muted"}`, role: iv.role, connectFrom: axisY + 8 })
    }
  }
  specs.sort((a, b) => a.cx - b.cx)
  const used = specs.length ? stackLabels(ctx, specs, tickBottom + 4, 1) : 0
  return finish(ctx, tickBottom + 4 + used + 6, { states: stateCount(data), state: ctx.state })
}

export function describe(data) {
  const n = stateCount(data)
  const out = []
  for (let i = 0; i < n; i++) {
    const e = effectiveState(data, i)
    const bits = [`Una retta dei numeri da ${N.format(N.parse(data.min))} a ${N.format(N.parse(data.max))}, con un segno ogni ${N.format(N.parse(data.step))}.`]
    for (const m of e.marks ?? []) {
      const kind = { dot: "un punto", open: "un cerchio vuoto", closed: "un punto pieno", cross: "una croce" }[m.kind ?? "dot"]
      bits.push(`C'è ${kind} su ${N.format(N.parse(m.at))}${m.label_it ? ` (${plain(m.label_it)})` : ""}.`)
    }
    for (const j of e.jumps ?? []) {
      const from = N.parse(j.from)
      bits.push(`Un salto parte da ${N.format(from)} e arriva a ${N.format(N.add(from, N.parse(j.by)))}${j.label_it ? ` (${plain(j.label_it)})` : ""}.`)
    }
    for (const iv of e.intervals ?? []) {
      const a = N.parse(iv.from, { allowInf: true })
      const b = N.parse(iv.to, { allowInf: true })
      bits.push(`Un intervallo va da ${N.format(a)} (${iv.from_closed ? "compreso" : "escluso"}) a ${N.format(b)} (${iv.to_closed ? "compreso" : "escluso"})${iv.label_it ? `: ${plain(iv.label_it)}` : ""}.`)
    }
    out.push(`${n > 1 ? `Passo ${i + 1}. ` : ""}${bits.join(" ")}`)
  }
  return listIt([out.join(" ")])
}

export const layout = (data, opts) => run(data, opts, { semantic, build })
