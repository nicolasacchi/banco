// balance (A7): a two-pan balance for natural terms. Boxes (the unknown) and weights (the units) sit on
// the pans. The beam tilts toward the heavier pan. `tilt` is never declared by an agent: it is computed,
// in Ruby (served as -1, 0 or 1 per state, 1 = the left pan is heavier) or here from x_value / the number
// the student tries. With `try` the student puts a number in the boxes and sees both members.
import * as N from "lesson/num"
import { effectiveState, finish, label, listIt, plain, shape, stateCount } from "lesson/diagrams/common"
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
    if (!v) return { path: "/try", message: "a try needs x_value" }
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

function rowsFor(count, cols) {
  return Math.ceil(count / cols)
}

// The items of one pan in groups: [{boxes, weights}] (one group when `groups` is absent).
function groupsOf(p, groups) {
  const g = groups ?? 1
  return Array.from({ length: g }, () => ({ boxes: p.x / g, weights: p.units / g }))
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const W = ctx.width
  const f = ctx.fontPx
  const m = 8
  const gap = 4
  const panW = Math.floor(W / 2 - 2 * m)
  const s = Math.max(Math.round(f * 1.5), 28)
  const cell = s + gap
  const cols = Math.max(2, Math.floor((panW + gap) / cell))

  // the tallest stack over every state, so that the figure does not jump between states
  const n = stateCount(data)
  const place = (p, groups) => {
    // returns { cells: [{kind, col, row, group}], w, rows, boxes: [{x, y, w, h}] }
    const items = []
    const gs = groupsOf(p, groups)
    if (groups) {
      // each group is a small cluster; clusters flow left to right
      const inner = Math.max(1, Math.min(cols, Math.floor((panW / Math.min(groups, 3) - 8 + gap) / cell)))
      const perCluster = gs.map((g) => g.boxes + g.weights)
      const cw = Math.min(inner, Math.max(...perCluster)) * cell - gap + 8
      const perRow = Math.max(1, Math.floor((panW + 6) / (cw + 6)))
      let height = 0
      const clusters = gs.map((g, gi) => {
        const total = g.boxes + g.weights
        const c = Math.min(inner, total)
        const r = rowsFor(total, c)
        height = Math.max(height, r * cell - gap + 8)
        return { g, c, r, row: Math.floor(gi / perRow), col: gi % perRow, w: c * cell - gap + 8 }
      })
      const lines = Math.ceil(clusters.length / perRow)
      return { clusters, perRow, rowsH: lines * (height + 6), rows: Math.ceil((lines * (height + 6)) / cell), height, cw, grouped: true }
    }
    for (let i = 0; i < p.x; i++) items.push("box")
    for (let i = 0; i < p.units; i++) items.push("weight")
    return { items, rows: Math.max(rowsFor(items.length, cols), 1), grouped: false }
  }
  let maxH = cell
  for (let i = 0; i < n; i++) {
    const e = effectiveState(data, i)
    for (const p of [plate(e.left), plate(e.right)]) {
      const pl = place(p, e.groups)
      maxH = Math.max(maxH, pl.grouped ? pl.rowsH : pl.rows * cell)
    }
  }
  const tilt = tiltOf(data, eff, ctx.tryValue)
  const delta = tilt === 0 ? 0 : Math.min(26, Math.round(W / 16))
  const beamY = 10 + 26
  const hang = Math.ceil(maxH + 22)
  const cxL = Math.round(W / 4)
  const cxR = Math.round((3 * W) / 4)
  const yL = beamY + tilt * delta
  const yR = beamY - tilt * delta
  const baseY = beamY + delta + hang + 22

  shape(ctx, "line", { x1: cxL, y1: yL, x2: cxR, y2: yR, cls: "dg-beam" })
  shape(ctx, "polygon", { points: [[W / 2 - 18, baseY], [W / 2 + 18, baseY], [W / 2, beamY]], cls: "dg-post" })
  shape(ctx, "line", { x1: W / 2 - 40, y1: baseY, x2: W / 2 + 40, y2: baseY, cls: "dg-base" })
  shape(ctx, "circle", { cx: W / 2, cy: beamY, r: 5, cls: "dg-pivot" })

  const boxText = ctx.tryValue !== undefined ? String(ctx.tryValue) : "x"
  const drawPan = (cx, beamEnd, p, side) => {
    const panY = beamEnd + hang
    shape(ctx, "line", { x1: cx, y1: beamEnd, x2: cx - panW / 2, y2: panY, cls: "dg-string" })
    shape(ctx, "line", { x1: cx, y1: beamEnd, x2: cx + panW / 2, y2: panY, cls: "dg-string" })
    shape(ctx, "line", { x1: cx - panW / 2, y1: panY, x2: cx + panW / 2, y2: panY, cls: `dg-pan tn-${side}` })
    const pl = place(p, eff.groups)
    const drawItem = (kind, x, y) => {
      if (kind === "box") {
        shape(ctx, "marker", { shape: "box", x, y, w: s, h: s, cls: "mk-unknown" })
        label(ctx, boxText, x + s / 2, y + s / 2, { valign: "middle", cls: "role-unknown dg-boxlabel" })
      } else shape(ctx, "marker", { shape: "weight", x, y, w: s, h: s, cls: "mk-known" })
    }
    if (pl.grouped) {
      const totalW = Math.min(pl.perRow, pl.clusters.length) * (pl.cw + 6) - 6
      pl.clusters.forEach((c) => {
        const cx0 = cx - totalW / 2 + c.col * (pl.cw + 6) + (pl.cw - c.w) / 2
        const top = panY - (c.row + 1) * (pl.height + 6) + 6
        shape(ctx, "rect", { x: cx0, y: top, w: c.w, h: pl.height, r: 8, cls: "dg-group" })
        const list = [...Array(c.g.boxes).fill("box"), ...Array(c.g.weights).fill("weight")]
        list.forEach((kind, k) => drawItem(kind, cx0 + 4 + (k % c.c) * cell, top + pl.height - 4 - (Math.floor(k / c.c) + 1) * cell + gap))
      })
    } else {
      pl.items.forEach((kind, k) => {
        const row = Math.floor(k / cols)
        const inRow = Math.min(cols, pl.items.length - row * cols)
        const col = k % cols
        const x = cx - (inRow * cell - gap) / 2 + col * cell
        drawItem(kind, x, panY - (row + 1) * cell + gap - 1)
      })
    }
    return panY
  }
  drawPan(cxL, yL, plate(eff.left), "left")
  drawPan(cxR, yR, plate(eff.right), "right")

  let height = baseY + 10
  if (eff.op_it) {
    const l = label(ctx, eff.op_it, W / 2, height, { maxW: W - 2 * m, cls: "dg-op" })
    height += l.h + 4
  }
  return finish(ctx, height, { states: n, state: ctx.state, tilt, solutionTilt: tilt })
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

// What the student reads while trying a number: both members and where the beam goes.
export function tryReadout(data, n, ctxState = 0) {
  const e = effectiveState(data, ctxState)
  const v = N.int(n)
  const l = value(e.left, v)
  const r = value(e.right, v)
  const t = N.compare(l, r)
  const verdict = t === 0 ? "I due piatti pesano uguale: la bilancia è in equilibrio" : t > 0 ? "Il piatto di sinistra pesa di più" : "Il piatto di destra pesa di più"
  return `Con x = ${n}: a sinistra ${N.format(l)}, a destra ${N.format(r)}. ${verdict}.`
}

// The public contract: layout(data, { width, fontPx, measure, subject, state, tryValue }) -> Scene | { error }.
export const layout = (data, opts) => run(data, opts, { semantic, build })
