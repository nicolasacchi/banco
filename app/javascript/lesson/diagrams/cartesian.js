// cartesian (A7): a coordinate plane with a window, a grid, lines (y = mx + q, x = k, ax + by = c with
// rational coefficients), points and segments. A point that names lines in `on_lines` lies exactly on each
// of them (checked with exact rationals). Tick labels thin out; point and line labels go next to their mark.
import * as N from "lesson/num"
import { effectiveState, finish, label, listIt, placeNear, plain, shape, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const states = stateCount

// "y = 2x + 1", "x + y = 7", "x = 3", "1/2x - 1,5" (y = is implied) -> { a, b, c } meaning a x + b y = c, or null.
export function parseLine(eq) {
  const text = String(eq).replace(/\s+/g, "").replace(/−/g, "-")
  const [lhs, rhs] = text.includes("=") ? text.split("=") : ["y", text]
  const side = (s) => {
    if (s === undefined || s === "") return null
    const terms = s.match(/[+-]?[^+-]+/g)
    if (!terms || terms.join("") !== s) return null
    const acc = { x: N.int(0), y: N.int(0), c: N.int(0) }
    for (const t of terms) {
      const m = t.match(/^([+-]?)(\d+(?:,\d+)?(?:\/\d+)?)?(x|y)?$/)
      if (!m || (m[2] === undefined && m[3] === undefined)) return null
      const coef = m[2] === undefined ? N.int(1) : N.parse(m[2])
      if (!coef) return null
      const signed = m[1] === "-" ? N.neg(coef) : coef
      const key = m[3] ?? "c"
      acc[key] = N.add(acc[key], signed)
    }
    return acc
  }
  const L = side(lhs)
  const R = side(rhs)
  if (!L || !R) return null
  const a = N.sub(L.x, R.x)
  const b = N.sub(L.y, R.y)
  const c = N.sub(R.c, L.c)
  if (N.isZero(a) && N.isZero(b)) return null
  return { a, b, c }
}

const onLine = (line, x, y) => N.eq(N.add(N.mul(line.a, x), N.mul(line.b, y)), line.c)

export function semantic(data) {
  const check = (src, base) => {
    const ids = new Set()
    const lines = new Map()
    for (let i = 0; i < (src.lines ?? []).length; i++) {
      const l = src.lines[i]
      if (ids.has(l.id)) return { path: `${base}/lines/${i}/id`, message: "line ids are unique" }
      ids.add(l.id)
      const parsed = parseLine(l.eq)
      if (!parsed) return { path: `${base}/lines/${i}/eq`, message: "eq is y = mx + q, x = k or ax + by = c" }
      lines.set(l.id, parsed)
    }
    const [xlo, xhi] = [N.parse(data.x[0]), N.parse(data.x[1])]
    const [ylo, yhi] = [N.parse(data.y[0]), N.parse(data.y[1])]
    for (let i = 0; i < (src.points ?? []).length; i++) {
      const p = src.points[i]
      const px = N.parse(p.x)
      const py = N.parse(p.y)
      if (N.compare(px, xlo) < 0 || N.compare(px, xhi) > 0 || N.compare(py, ylo) < 0 || N.compare(py, yhi) > 0) return { path: `${base}/points/${i}`, message: "a point lies outside the window" }
      for (const id of p.on_lines ?? []) {
        const line = lines.get(id)
        if (!line || !onLine(line, px, py)) return { path: `${base}/points/${i}/on_lines`, message: "a point lies on each line it names" }
      }
    }
    for (let i = 0; i < (src.segments ?? []).length; i++) {
      for (const end of [src.segments[i].from, src.segments[i].to]) {
        const ex = N.parse(end[0])
        const ey = N.parse(end[1])
        if (N.compare(ex, xlo) < 0 || N.compare(ex, xhi) > 0 || N.compare(ey, ylo) < 0 || N.compare(ey, yhi) > 0) return { path: `${base}/segments/${i}`, message: "a segment lies outside the window" }
      }
    }
    return null
  }
  if (N.compare(N.parse(data.x[0]), N.parse(data.x[1])) >= 0) return { path: "/x", message: "the window runs from a smaller to a larger number" }
  if (N.compare(N.parse(data.y[0]), N.parse(data.y[1])) >= 0) return { path: "/y", message: "the window runs from a smaller to a larger number" }
  const bad = check(data, "")
  if (bad) return bad
  for (let j = 0; j < (data.states ?? []).length; j++) {
    const merged = effectiveState(data, j)
    const err = check(merged, `/states/${j}`)
    if (err) return err
  }
  return null
}

function niceStep(span, slots) {
  for (const s of [1, 2, 5, 10, 20, 50, 100]) if (span / s <= slots) return s
  return 100
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const W = ctx.width
  const f = ctx.fontPx
  const xlo = N.toNumber(N.parse(data.x[0]))
  const xhi = N.toNumber(N.parse(data.x[1]))
  const ylo = N.toNumber(N.parse(data.y[0]))
  const yhi = N.toNumber(N.parse(data.y[1]))
  // margins for the tick labels
  const yTickText = (v) => N.format(N.parse(String(v)))
  const widest = Math.max(...[ylo, yhi].map((v) => ctx.measure(yTickText(Math.round(v)), f).w))
  const left = Math.ceil(widest) + 12
  const right = 12
  const top = 10
  const bottom = ctx.lineH + 10
  const pw = W - left - right
  const ph = Math.round(Math.max(160, Math.min(pw * ((yhi - ylo) / (xhi - xlo)), 340)))
  const X = (v) => left + ((v - xlo) / (xhi - xlo)) * pw
  const Y = (v) => top + ph - ((v - ylo) / (yhi - ylo)) * ph
  const num = (s) => N.toNumber(N.parse(s))

  shape(ctx, "rect", { x: left, y: top, w: pw, h: ph, r: 0, cls: "dg-plot" })
  const xs = Math.max(1, niceStep(xhi - xlo, Math.max(2, Math.floor(pw / (f * 2.4)))))
  const ys = Math.max(1, niceStep(yhi - ylo, Math.max(2, Math.floor(ph / (f * 1.9)))))
  const startX = Math.ceil(xlo / xs) * xs
  for (let v = startX; v <= xhi + 1e-9; v += xs) {
    if (data.grid && v > xlo && v < xhi) shape(ctx, "line", { x1: X(v), y1: top, x2: X(v), y2: top + ph, cls: "dg-grid" })
    const l = label(ctx, N.format(N.parse(String(Math.round(v)))), X(v), top + ph + 4, { cls: "dg-tick-label" })
    l.x = Math.max(0, Math.min(l.x, W - l.w))
  }
  const startY = Math.ceil(ylo / ys) * ys
  for (let v = startY; v <= yhi + 1e-9; v += ys) {
    if (data.grid && v > ylo && v < yhi) shape(ctx, "line", { x1: left, y1: Y(v), x2: left + pw, y2: Y(v), cls: "dg-grid" })
    const l = label(ctx, N.format(N.parse(String(Math.round(v)))), left - 6, Y(v), { anchor: "end", valign: "middle", cls: "dg-tick-label" })
    l.y = Math.min(l.y, top + ph + 2 - l.h)
  }
  if (xlo <= 0 && xhi >= 0) shape(ctx, "line", { x1: X(0), y1: top, x2: X(0), y2: top + ph, cls: "dg-axis" })
  if (ylo <= 0 && yhi >= 0) shape(ctx, "line", { x1: left, y1: Y(0), x2: left + pw, y2: Y(0), cls: "dg-axis" })

  // lines clipped to the window
  const box = { x0: left + 2, y0: top + 2, x1: left + pw - 2, y1: top + ph - 2 }
  const ends = []
  for (const l of eff.lines ?? []) {
    const { a, b, c } = parseLine(l.eq)
    const fa = N.toNumber(a)
    const fb = N.toNumber(b)
    const fc = N.toNumber(c)
    let p1
    let p2
    if (fb === 0) {
      const x = fc / fa
      p1 = [x, ylo]
      p2 = [x, yhi]
    } else {
      const yAt = (x) => (fc - fa * x) / fb
      const pts = []
      for (const x of [xlo, xhi]) {
        const y = yAt(x)
        if (y >= ylo - 1e-9 && y <= yhi + 1e-9) pts.push([x, y])
      }
      if (fa !== 0) {
        for (const y of [ylo, yhi]) {
          const x = (fc - fb * y) / fa
          if (x > xlo + 1e-9 && x < xhi - 1e-9) pts.push([x, y])
        }
      }
      if (pts.length < 2) continue
      pts.sort((u, v) => u[0] - v[0])
      ;[p1, p2] = [pts[0], pts[pts.length - 1]]
    }
    const role = l.role ?? "muted"
    shape(ctx, "line", { x1: X(p1[0]), y1: Y(p1[1]), x2: X(p2[0]), y2: Y(p2[1]), cls: `dg-line st-${role}` })
    ends.push({ l, at: [X(p2[0]), Y(p2[1])], role })
  }
  for (const s of eff.segments ?? []) {
    shape(ctx, "line", { x1: X(num(s.from[0])), y1: Y(num(s.from[1])), x2: X(num(s.to[0])), y2: Y(num(s.to[1])), cls: `dg-segment st-${s.role ?? "muted"}` })
  }
  for (const p of eff.points ?? []) {
    shape(ctx, "circle", { cx: X(num(p.x)), cy: Y(num(p.y)), r: 7, cls: `mk-${p.role ?? "muted"} dg-point` })
  }
  // labels next to their marks (inside the plot, not over another label)
  for (const p of eff.points ?? []) {
    if (!p.label_it) continue
    const placed = placeNear(ctx, p.label_it, X(num(p.x)), Y(num(p.y)), 10, box, { cls: `dg-note role-${p.role ?? "muted"}`, role: p.role })
    if (!placed) return { error: { path: "/points", message: "no room for the label of a point", code: "E-DIAGRAM-LAYOUT" } }
  }
  for (const e of ends) {
    if (!e.l.label_it) continue
    const placed = placeNear(ctx, e.l.label_it, e.at[0], e.at[1], 6, box, { cls: `dg-note role-${e.role}`, role: e.role })
    if (!placed) return { error: { path: "/lines", message: "no room for the label of a line", code: "E-DIAGRAM-LAYOUT" } }
  }
  return finish(ctx, top + ph + bottom, { states: stateCount(data), state: ctx.state })
}

export function describe(data) {
  const n = stateCount(data)
  const out = []
  for (let i = 0; i < n; i++) {
    const e = effectiveState(data, i)
    const bits = [`Un piano cartesiano: la x va da ${N.format(N.parse(data.x[0]))} a ${N.format(N.parse(data.x[1]))}, la y da ${N.format(N.parse(data.y[0]))} a ${N.format(N.parse(data.y[1]))}.`]
    for (const l of e.lines ?? []) bits.push(`C'è la retta ${plain(l.label_it ?? l.eq)}.`)
    for (const p of e.points ?? []) bits.push(`C'è il punto (${N.format(N.parse(p.x))}, ${N.format(N.parse(p.y))})${p.on_lines ? `, sulle rette ${listIt(p.on_lines)}` : ""}.`)
    for (const s of e.segments ?? []) bits.push(`C'è un segmento da (${N.format(N.parse(s.from[0]))}, ${N.format(N.parse(s.from[1]))}) a (${N.format(N.parse(s.to[0]))}, ${N.format(N.parse(s.to[1]))}).`)
    out.push(`${n > 1 ? `Passo ${i + 1}. ` : ""}${bits.join(" ")}`)
  }
  return out.join(" ")
}

export const layout = (data, opts) => run(data, opts, { semantic, build })
