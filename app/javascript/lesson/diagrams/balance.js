// balance (A7): a two-pan balance for natural terms. Boxes (the unknown) and weights (the units) sit on
// the pans. The beam tilts toward the heavier pan. `tilt` is never declared by an agent: it is computed,
// in Ruby (served as -1, 0 or 1 per state, 1 = the left pan is heavier) or here from x_value / the number
// the student tries. With `try` the student puts a number in the boxes and sees both members.
import * as N from "lesson/num"
import { effectiveState, finish, listIt, plain, shape, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const STATE_KEYS = ["left", "right"]
const plate = (p) => ({ x: p?.x ?? 0, units: p?.units ?? 0 })

function value(plateData, v) {
  const p = plate(plateData)
  return N.add(N.mul(N.int(p.x), v), N.int(p.units))
}

// Semantic checks of the raw data (Lessons::Diagrams::Balance mirror). Served data has no x_value
// (tilt replaces it) and skips what needs it.
export function semantic(data) {
  const n = stateCount(data)
  const served = hasTilt(data)
  const v = data.x_value === undefined ? null : N.parse(data.x_value)
  if (data.x_value !== undefined && (!v || N.compare(v, N.int(0)) <= 0)) return { path: "/x_value", message: "a balance cannot draw a zero or a negative solution" }
  const effective = Array.from({ length: n }, (_, i) => effectiveState(data, i))
  if (!served) {
    const first = effective[0]
    const sameBoxes = plate(first.left).x === plate(first.right).x
    if (v && sameBoxes) return { path: "/x_value", message: "x_value is omitted when both plates hold the same number of boxes" }
    if (!v && !sameBoxes) return { path: "/x_value", message: "x_value is required when the plates hold different numbers of boxes" }
    if (v) {
      for (let i = 0; i < n; i++) {
        const e = effective[i]
        if (N.compare(value(e.left, v), value(e.right, v)) !== 0) {
          return data.states ? { path: `/states/${i}`, message: "a state of a balance must be level at x_value" } : { path: "/x_value", message: "x_value is not the solution of the equation drawn" }
        }
      }
    }
  }
  for (let i = 0; i < n; i++) {
    const e = effective[i]
    if (e.groups !== undefined) {
      const l = plate(e.left)
      const r = plate(e.right)
      if ([l.x, l.units, r.x, r.units].some((k) => k % e.groups !== 0)) return { path: `/states/${i}/groups`, message: "both plates must divide into equal groups" }
    }
  }
  if (data.try) {
    if (data.try.to < data.try.from) return { path: "/try", message: "from is above to" }
    if (data.try.to - data.try.from + 1 > 12) return { path: "/try", message: "a try has at most 12 values" }
    if (v && !(N.compare(v, N.int(data.try.from)) >= 0 && N.compare(v, N.int(data.try.to)) <= 0)) return { path: "/try", message: "the range must contain the solution" }
    if (!v && !served) return { path: "/try", message: "a try needs x_value" }
  }
  return null
}

function hasTilt(data) {
  return data.tilt !== undefined || (data.states ?? []).some((s) => s.tilt !== undefined)
}

// -1, 0 or 1: 1 when the left pan is heavier.
export function tiltOf(data, eff, tryValue) {
  if (tryValue !== undefined) {
    const v = N.int(tryValue)
    return N.compare(value(eff.left, v), value(eff.right, v))
  }
  if (eff.tilt !== undefined) return eff.tilt
  const v = data.x_value === undefined ? null : N.parse(data.x_value)
  if (v) return N.compare(value(eff.left, v), value(eff.right, v))
  // the same number of boxes on both pans: the units decide
  return Math.sign(plate(eff.left).units - plate(eff.right).units)
}

export function states(data) {
  return stateCount(data)
}

// ---- the drawing (E7: the prototype's balance, in 2D) ----
// Sizes follow the figure's width: boxes (the unknown) as rounded squares with an "x", the units as brass bells with a "1",
// pans in the member colours, a beam on a stand. Everything is a plain shape; the beam and the pans are groups whose
// transform draw.js moves smoothly from the last state to the new one.
const DEG = 6 // the beam's tilt when the pans differ

export function sizes(W, scale = 1) {
  const narrow = W < 560
  const u = Math.max(26, Math.min(40, Math.round(W / (narrow ? 13 : 24)))) * scale
  return {
    u, B: Math.round(u * 1.4), Wb: Math.max(24, Math.round(u * 1.05)), Hb: Math.round(u * 1.2), bg: 4, wg: 3, rg: 3, zone: Math.round(u * 0.3),
    panW: Math.round(W * (narrow ? 0.43 : 0.34))
  }
}

// One pan's items in the usual way: boxes in a block (1 to 3 columns), the bells beside them in rows.
function packPlain(x, n, S) {
  let best = null
  for (let bc = x ? 1 : 0; bc <= Math.min(3, x); bc++) {
    const bw = bc ? bc * (S.B + S.bg) - S.bg : 0
    const gapZ = x && n ? S.zone : 0
    const per = n ? Math.floor((S.panW - bw - gapZ + S.wg) / (S.Wb + S.wg)) : 0
    if (n && per < 1) continue
    const rb = x ? Math.ceil(x / bc) : 0
    const rw = n ? Math.ceil(n / per) : 0
    const h = Math.max(rb * (S.B + S.rg), rw * (S.Hb + S.rg))
    if (!best || h < best.h || (h === best.h && bc > best.bc)) best = { bc, per, bw, gapZ, h }
    if (!x) break
  }
  if (!best) {
    const bw = x ? S.B : 0
    best = { bc: x ? 1 : 0, per: 1, bw, gapZ: x && n ? S.zone : 0, h: Math.max(x * (S.B + S.rg), n * (S.Hb + S.rg)) }
  }
  const items = []
  const wRow = n ? Math.min(n, best.per) * (S.Wb + S.wg) - S.wg : 0
  const x0 = -(best.bw + best.gapZ + wRow) / 2
  for (let i = 0; i < x; i++) items.push({ kind: "box", x: x0 + (i % best.bc) * (S.B + S.bg), y: -S.B - Math.floor(i / best.bc) * (S.B + S.rg) - 2, w: S.B, h: S.B })
  const wx0 = x0 + best.bw + best.gapZ
  for (let j = 0; j < n; j++) items.push({ kind: "bell", x: wx0 + (j % best.per) * (S.Wb + S.wg), y: -S.Hb - Math.floor(j / best.per) * (S.Hb + S.rg) - 2, w: S.Wb, h: S.Hb })
  return { items, h: best.h + 2, boxes: [] }
}

// A pan divided into g equal groups: each group a dashed rounded box with its items.
function packGroups(x, n, g, S) {
  const b = x / g
  const w = n / g
  const m = b + w
  const perRowItems = m <= 3 ? m : Math.ceil(m / 2)
  const cellW = b > 0 ? S.B : S.Wb
  const cellH = b > 0 ? S.B : S.Hb
  const rows = Math.ceil(m / perRowItems)
  const cw = perRowItems * (cellW + S.wg) - S.wg + 8
  const ch = rows * (cellH + S.rg) - S.rg + 8
  const perRow = Math.max(1, Math.floor((S.panW + 6) / (cw + 6)))
  const lines = Math.ceil(g / perRow)
  const shown = Math.min(g, perRow)
  const totalW = shown * (cw + 6) - 6
  const items = []
  const boxes = []
  for (let gi = 0; gi < g; gi++) {
    const col = gi % perRow
    const row = Math.floor(gi / perRow)
    const gx = -totalW / 2 + col * (cw + 6)
    const gy = -(row + 1) * (ch + 6) + 4
    boxes.push({ x: gx, y: gy, w: cw, h: ch })
    for (let k = 0; k < m; k++) {
      const kind = k < b ? "box" : "bell"
      const iw = kind === "box" ? S.B : S.Wb
      const ih = kind === "box" ? S.B : S.Hb
      items.push({ kind, x: gx + 4 + (k % perRowItems) * (cellW + S.wg) + (cellW - iw) / 2, y: gy + ch - 4 - (Math.floor(k / perRowItems) + 1) * (cellH + S.rg) + S.rg + (cellH - ih), w: iw, h: ih })
    }
  }
  return { items, h: lines * (ch + 6) + 2, boxes }
}

function packFor(p, groups, S) {
  const q = plate(p)
  if (!groups) return packPlain(q.x, q.units, S)
  return packGroups(q.x, q.units, groups, sizes(S.W, 0.78))
}

function itemShapes(ctx, pack, f, S) {
  const out = []
  for (const bx of pack.boxes) out.push({ kind: "rect", x: bx.x, y: bx.y, w: bx.w, h: bx.h, r: 10, cls: "dg-group" })
  for (const it of pack.items) {
    if (it.kind === "box") {
      out.push({ kind: "rect", x: it.x, y: it.y, w: it.w, h: it.h, r: Math.round(it.w * 0.2), cls: "bl-box" })
      out.push({ kind: "rect", x: it.x + it.w * 0.12, y: it.y + it.w * 0.1, w: it.w * 0.76, h: Math.max(3, it.w * 0.15), r: it.w * 0.07, cls: "bl-shine" })
      out.push({ kind: "text", x: it.x + it.w / 2, y: it.y + it.h * 0.5 + Math.max(f, it.w * 0.52) * 0.36, text: "x", px: Math.max(f, Math.round(it.w * 0.52)), cls: "bl-x" })
    } else {
      const { x, y, w, h } = it
      out.push({ kind: "path", d: `M${x + w * 0.08},${y + h} L${x + w * 0.92},${y + h} L${x + w * 0.76},${y + h * 0.36} L${x + w * 0.24},${y + h * 0.36} Z`, cls: "bl-bell" })
      out.push({ kind: "rect", x: x + w * 0.32, y: y, w: w * 0.36, h: h * 0.4, r: w * 0.16, cls: "bl-knob" })
      out.push({ kind: "text", x: x + w / 2, y: y + h - Math.max(3, h * 0.12), text: "1", px: Math.max(f, 18), cls: "bl-one" })
    }
  }
  return out
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const W = ctx.width
  const f = ctx.fontPx
  const S = { ...sizes(W), W }
  const n = stateCount(data)
  // the tallest stack over every state, so that the figure does not jump between states
  let maxH = S.Hb
  for (let i = 0; i < n; i++) {
    const e = effectiveState(data, i)
    for (const p of [e.left, e.right]) maxH = Math.max(maxH, packFor(p, e.groups, S).h)
  }
  const tilt = tiltOf(data, eff, ctx.tryValue)
  const deg = -tilt * DEG
  const rad = (deg * Math.PI) / 180
  const half = Math.round(W / 2 - S.panW / 2 - 6)
  const rise = Math.round(half * Math.sin((DEG * Math.PI) / 180))
  const panT = Math.max(10, Math.round(S.u * 0.32))
  const postH = Math.round(S.u * 0.6)
  const y0 = 10 + rise + maxH
  const beamY = y0 + panT + postH
  const cx = W / 2
  const needle = Math.round(S.u * 1.9)
  const baseY = beamY + needle + Math.round(S.u * 0.5)
  const bt = Math.max(10, Math.round(S.u * 0.38))

  shape(ctx, "ellipse", { cx, cy: baseY + 4, rx: Math.round(S.u * 2.6), ry: Math.round(S.u * 0.28), cls: "bl-shadow" })
  shape(ctx, "path", { d: `M${cx - S.u * 2.2},${baseY + 2} Q${cx - S.u * 2.3},${baseY - S.u * 0.55} ${cx - S.u * 1.2},${baseY - S.u * 0.6} L${cx + S.u * 1.2},${baseY - S.u * 0.6} Q${cx + S.u * 2.3},${baseY - S.u * 0.55} ${cx + S.u * 2.2},${baseY + 2} Z`, cls: "bl-stand" })
  shape(ctx, "rect", { x: cx - S.u * 0.28, y: beamY, w: S.u * 0.56, h: baseY - beamY - S.u * 0.4, r: 4, cls: "bl-stand" })
  shape(ctx, "group", { key: "beam", at: [0, 0], move: { rot: deg, ox: cx, oy: beamY }, cls: "dg-tilt", children: [
    { kind: "rect", x: cx - half - 10, y: beamY - bt / 2, w: 2 * half + 20, h: bt, r: bt / 2, cls: "bl-beam" },
    { kind: "rect", x: cx - 3, y: beamY, w: 6, h: needle, r: 3, cls: "bl-needle" }
  ] })
  const dx = half * (1 - Math.cos(rad))
  const dy = half * Math.sin(rad)
  const pan = (side, p, sign) => {
    const pack = packFor(p, eff.groups, S)
    const children = [
      { kind: "rect", x: -4, y: panT - 1, w: 8, h: postH + 2, r: 3, cls: "bl-post" },
      { kind: "rect", x: -S.panW / 2, y: 0, w: S.panW, h: panT, r: panT / 2, cls: `bl-pan bl-pan-${side}` },
      ...itemShapes(ctx, pack, f, S)
    ]
    shape(ctx, "group", { key: `pan-${side}`, at: [cx + sign * half, y0], move: { tx: -sign * dx, ty: sign * dy }, cls: "dg-moving", children })
  }
  pan("left", eff.left, -1)
  pan("right", eff.right, 1)
  shape(ctx, "circle", { cx, cy: beamY, r: Math.round(S.u * 0.34), cls: "bl-pivot" })
  return finish(ctx, baseY + Math.round(S.u * 0.55), { states: n, state: ctx.state, tilt, solutionTilt: tilt })
}

export function describe(data) {
  const sides = (e) => {
    const part = (p) => {
      const q = plate(p)
      const bits = []
      if (q.x > 0) bits.push(q.x === 1 ? "una scatola x" : `${q.x} scatole x`)
      if (q.units > 0) bits.push(q.units === 1 ? "un peso da 1" : `${q.units} pesi da 1`)
      return bits.length ? listIt(bits) : "niente"
    }
    return `sul piatto di sinistra ${part(e.left)}, su quello di destra ${part(e.right)}`
  }
  const word = (t) => (t === 0 ? "in equilibrio" : t > 0 ? "inclinata a sinistra, il piatto di sinistra pesa di più" : "inclinata a destra, il piatto di destra pesa di più")
  const n = stateCount(data)
  const out = []
  for (let i = 0; i < n; i++) {
    const e = effectiveState(data, i)
    const head = n > 1 ? `Passo ${i + 1}${e.op_it ? ` (${plain(e.op_it)})` : ""}: ` : ""
    out.push(`${head}${sides(e)}. La bilancia è ${word(tiltOf(data, e))}${e.groups ? `. I piatti sono divisi in ${e.groups} gruppi uguali` : ""}.`)
  }
  if (data.try) out.push(`Puoi mettere un numero da ${data.try.from} a ${data.try.to} nelle scatole e vedere come si muove la bilancia.`)
  return out.join(" ")
}

// The equation of a state as TeX ("2x + 3 = 7"), for the line above the drawing.
export function equationTex(data, i = 0) {
  const e = effectiveState(data, i)
  const side = (p) => {
    const q = plate(p)
    const bits = []
    if (q.x > 0) bits.push(`${q.x === 1 ? "" : q.x}x`)
    if (q.units > 0 || bits.length === 0) bits.push(String(q.units))
    return bits.join(" + ")
  }
  return `${side(e.left)} = ${side(e.right)}`
}

// What the student reads while trying a number: both members and where the beam goes.
export function tryValues(data, n, ctxState = 0) {
  const e = effectiveState(data, ctxState)
  const v = N.int(n)
  const l = value(e.left, v)
  const r = value(e.right, v)
  return { left: N.format(l), right: N.format(r), tilt: N.compare(l, r) }
}

export function tryReadout(data, n, ctxState = 0) {
  const t = tryValues(data, n, ctxState)
  const verdict = t.tilt === 0 ? "I due piatti pesano uguale: la bilancia è in equilibrio" : t.tilt > 0 ? "Il piatto di sinistra pesa di più" : "Il piatto di destra pesa di più"
  return `Con x = ${n}: a sinistra ${t.left}, a destra ${t.right}. ${verdict}.`
}

// The public contract: layout(data, { width, fontPx, measure, subject, state, tryValue }) -> Scene | { error }.
export const layout = (data, opts) => run(data, opts, { semantic, build })
