// number_line (A7): an axis with ticks, marks (dot, open, closed, cross), jumps (arcs with a label) and
// intervals (a thick bar, open or closed ends, an arrow for infinity). Exact numbers (num.js); floats
// only for pixel positions. Tick labels thin out (every k-th, keeping 0) when they would touch.
import * as N from "lesson/num"
import { crosses, effectiveState, fail, finish, label, listIt, plain, shape, stateCount, words } from "lesson/diagrams/common"
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

const ABOVE_GAP = 14 // from the axis to the bottom of the first row of labels above it (clears the ring of a closed mark)
const LEADER_GAP = 12 // from the axis to where a leader going up starts
const SIDE = 4 // a label's box keeps this far in from its leader's x at least
const CLEAR = 3 // a leader keeps this far from a label's box and from another label's box

// Where the labels of marks and intervals go, along x and in rows. Row 0 under the tick numbers (no leader) takes the labels, left to
// right, that fit side by side as they are, centred on their marks. A label that would touch another goes above the axis, in the rows
// there (row 0 right over its mark), or, with `up` false (jump arcs fill the space above), in rows under it, the labels of every row
// looked at again.
// A label of a row after the first has a vertical leader to its mark's x, which crosses no label of the rows between and beside which
// no label of a row further out has its leader: a label slides sideways (its box still over its mark's x) or goes to another row for
// that, and the fewest rows that allow it are used. Returns { below, above, belowRows, aboveRows } (each placed label
// { spec, x, w, h, row }), or null when no way is free.
function planLabels(ctx, specs, up) {
  const W = ctx.width
  const gap = 8
  const boxes = specs
    .map((spec) => {
      const m = ctx.measure(spec.text, ctx.fontPx, spec.maxW, spec.cls)
      const w = Math.min(Math.ceil(m.w), W - 8)
      const x = Math.max(4, Math.min(Math.round(spec.cx - w / 2), W - w - 4))
      return { spec, x, w, h: Math.ceil(m.h), row: 0 }
    })
    .sort((a, b) => a.spec.cx - b.spec.cx)
  const first = []
  const over = []
  for (const b of boxes) (first.every((o) => b.x >= o.x + o.w + gap || b.x + b.w + gap <= o.x) ? first : over).push(b)
  const used = (list) => list.reduce((n, p) => Math.max(n, p.row + 1), 0)
  if (over.length === 0) return { below: first, above: [], belowRows: used(first), aboveRows: 0 }
  // above the axis only the labels that did not fit under it move; under it (jump arcs above) every label is looked at again, since a
  // wide label of the first row can stand where a leader of a further row must pass
  const list = up ? over : boxes
  for (let total = 1; total <= (up ? over.length : boxes.length); total++) {
    const placed = arrange(Array.from({ length: total }, () => []), list, 0, { W, gap, budget: { left: 20000 } })
    if (placed) return up ? { below: first, above: placed, belowRows: used(first), aboveRows: used(placed) } : { below: placed, above: [], belowRows: used(placed), aboveRows: 0 }
  }
  return null
}

// Puts over[k..] into `rows` (the rows are filled in place and emptied again when a try fails): for each label the rows from the first,
// in each the places that keep its box over its mark's x (centred, then against the mark's right, then its left). Returns the placed labels.
function arrange(rows, over, k, env) {
  if (k === over.length) return []
  const b = over[k]
  const cx = b.spec.cx
  const { W, gap, budget } = env
  const xs = [b.x, Math.round(cx) - SIDE, Math.round(cx) + SIDE - b.w]
    .map((x) => Math.max(4, Math.min(x, W - b.w - 4)))
    .filter((x, i, all) => all.indexOf(x) === i && x + SIDE <= cx && cx <= x + b.w - SIDE)
  for (let row = 0; row < rows.length; row++) {
    // the leader of this label runs through the nearer rows at cx
    if (row > 0 && rows.slice(0, row).some((r) => r.some((o) => cx >= o.x - CLEAR && cx <= o.x + o.w + CLEAR))) continue
    for (const x of xs) {
      if (--budget.left < 0) return null
      const free = rows[row].every((o) => x >= o.x + o.w + gap || x + b.w + gap <= o.x)
      const beside = rows.slice(row + 1).every((r) => r.every((o) => o.spec.cx < x - CLEAR || o.spec.cx > x + b.w + CLEAR))
      if (!free || !beside) continue
      const p = { ...b, x, row }
      rows[row].push(p)
      const rest = arrange(rows, over, k + 1, env)
      if (rest) return [p, ...rest]
      rows[row].pop()
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

  // the labels of marks and intervals are placed along x first: how many rows they need above the axis fixes where the axis goes
  const specs = []
  for (const m of eff.marks ?? []) {
    if (m.label_it) specs.push({ text: m.label_it, cx: at(N.parse(m.at)), cls: `dg-note role-${m.role ?? "muted"}`, role: m.role })
  }
  for (const iv of eff.intervals ?? []) {
    if (iv.label_it) {
      const a = N.parse(iv.from, { allowInf: true })
      const b = N.parse(iv.to, { allowInf: true })
      specs.push({ text: iv.label_it, cx: (Math.max(at(a), x0) + Math.min(at(b), x1)) / 2, cls: `dg-note role-${iv.role ?? "muted"}`, role: iv.role })
    }
  }
  const jumps = eff.jumps ?? []
  const plan = planLabels(ctx, specs, jumps.length === 0)
  if (!plan) return fail("", "the labels of the marks are too many or too wide to place clear of each other and of the tick numbers: shorten them or label fewer marks", "E-DIAGRAM-LAYOUT")
  const rowH = ctx.lineH + 4
  const aboveH = plan.aboveRows * rowH
  const belowUsed = plan.belowRows * rowH

  // vertical plan: labels above the axis or jump arcs, axis, tick labels, then the rows of mark and interval labels
  const arcRow = Math.round(f * 0.9) + 14
  const jumpLabelH = jumps.some((j) => j.label_it) ? ctx.lineH + 4 : 0
  const axisY = 14 + (jumps.length ? jumpLabelH + arcRow + (jumps.length - 1) * Math.round(arcRow * 0.55) : 6 + aboveH) + 10
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
  // labels of marks and intervals: the first row under the tick numbers; a label that would touch another goes above the axis
  // (above its mark, none of the tick numbers there), or, when jump arcs fill the space above, in a lower row whose leader starts
  // under the tick numbers. A leader never crosses a tick number, a label or another leader.
  const leaders = []
  const put = (p, y, leader) => {
    const item = label(ctx, p.spec.text, p.x, y, { anchor: "start", cls: p.spec.cls, role: p.spec.role })
    item.w = Math.max(item.w, p.w)
    item.anchor = "middle"
    if (leader) {
      const s = { x1: p.spec.cx, y1: leader.from, x2: p.spec.cx, y2: leader.to(item), cls: "dg-connector" }
      shape(ctx, "line", s)
      leaders.push({ seg: s, own: item })
    }
  }
  for (const p of plan.below) put(p, tickBottom + 4 + p.row * rowH, p.row > 0 && { from: tickBottom + 3, to: (item) => item.y })
  for (const p of plan.above) put(p, axisY - ABOVE_GAP - p.h - p.row * rowH, p.row > 0 && { from: axisY - LEADER_GAP, to: (item) => item.y + item.h })
  for (let i = 0; i < leaders.length; i++) {
    const { seg, own } = leaders[i]
    const hit = ctx.labels.find((l) => l !== own && crosses(seg, l, 1))
    if (hit) return fail("", `a leader of a label crosses another label (${own.text_it} through ${hit.text_it})`, "E-DIAGRAM-LAYOUT")
    if (leaders.some((o, j) => j !== i && Math.abs(o.seg.x1 - seg.x1) < 3 && Math.max(Math.min(o.seg.y1, o.seg.y2), Math.min(seg.y1, seg.y2)) < Math.min(Math.max(o.seg.y1, o.seg.y2), Math.max(seg.y1, seg.y2))))
      return fail("", `two leaders of labels run over each other (${own.text_it})`, "E-DIAGRAM-LAYOUT")
  }
  return finish(ctx, tickBottom + 4 + belowUsed + 6, { states: stateCount(data), state: ctx.state })
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
