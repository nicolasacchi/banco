// The drawing of a molecule, an ionic unit or a metal (T7): shared by `molecule` and by `formula` with show: molecules.
// A molecular row is balls (or sticks) with the symbol written inside every atom; an ionic or metal row is a small patch with one unit framed and
// labelled "unità", never a molecule (WAVE2 2.8). Pure: functions that push shapes and labels on a layout context at absolute coordinates.
import { label, shape } from "lesson/diagrams/common"
import { PATCH_ROWS, PATCH_UNITS, ionGroups } from "lesson/diagrams/science/common"

const toNumber = (text) => Number(String(text).replace(",", "."))

// The radius of an atom: relative sizes (H small) in balls, one size for every atom in sticks. In select mode every atom has the same size (L3).
export function atomRadius(symbol, F, style = "balls", neutral = false) {
  if (neutral) return Math.round(F * 0.8)
  if (style === "sticks") return Math.round(F * 0.72)
  if (symbol === "H") return Math.round(F * 0.72)
  if (["C", "N", "O"].includes(symbol)) return Math.round(F * 0.92)
  return Math.round(F * 1.05)
}

// "OH", "NO3", "HCO3": the atoms of one ion as a formula, in the order the row lists them, as KaTeX where a subscript is needed.
export function ionText(row, indices) {
  const counts = []
  for (const i of indices) {
    const s = row.atoms[i].symbol
    const last = counts[counts.length - 1]
    if (last && last[0] === s) last[1] += 1
    else counts.push([s, 1])
  }
  const plain = counts.map(([s, n]) => `${s}${n > 1 ? n : ""}`).join("")
  const tex = counts.map(([s, n]) => `${s}${n > 1 ? `_${n}` : ""}`).join("")
  return { plain, label: counts.some(([, n]) => n > 1) ? `$\\mathrm{${tex}}$` : plain, atoms: indices.length }
}

// ---- molecules --------------------------------------------------------------------------------------------------------------------------

// The pose of one molecule: atoms at pixel positions from 0,0 (the top left of the box), bonds, the box size. S px per angstrom grows with the text.
export function pose(row, F, { style = "balls", neutral = false, margin = 0 } = {}) {
  const [mx, my] = Array.isArray(margin) ? margin : [margin, margin]
  const S = F * 3
  const raw = row.atoms.map((a) => ({ symbol: a.symbol, x: toNumber(a.xy[0]) * S, y: -toNumber(a.xy[1]) * S, r: atomRadius(a.symbol, F, style, neutral) }))
  const x0 = Math.min(...raw.map((a) => a.x - a.r))
  const y0 = Math.min(...raw.map((a) => a.y - a.r))
  const atoms = raw.map((a) => ({ ...a, x: Math.round(a.x - x0 + mx), y: Math.round(a.y - y0 + my) }))
  const w = Math.ceil(Math.max(...raw.map((a) => a.x + a.r)) - x0) + 2 * mx
  const h = Math.ceil(Math.max(...raw.map((a) => a.y + a.r)) - y0) + 2 * my
  return { kind: "molecular", atoms, bonds: row.bonds ?? [], w, h, margin: my }
}

const polar = (cx, cy, r, deg) => [cx + r * Math.cos((deg * Math.PI) / 180), cy - r * Math.sin((deg * Math.PI) / 180)]

// The vertex of the drawn angle: the first atom with exactly two bonds, and its two neighbours; null when there is none.
export function angleSpot(row) {
  const bonds = row.bonds ?? []
  const centre = row.atoms.findIndex((_, i) => bonds.filter(([a, b]) => a === i || b === i).length === 2)
  if (centre < 0) return null
  const ends = bonds.filter(([a, b]) => a === centre || b === centre).map(([a, b]) => (a === centre ? b : a))
  return { centre, ends }
}

// "104,5°"; the zero decimal of a straight angle is dropped ("180°").
export const angleText = (text) => `${String(text).replace(/,0$/, "")}°`

// Draws one molecule (a pose) with its top left at (x, y). opts: { symbols, partial, angle, row, cls, targets: { atoms: bool, firstTarget: n } }.
// Returns the atoms' boxes in reading order (for the select targets) and the next target number.
export function drawMolecule(ctx, p, x, y, row, opts = {}) {
  const F = ctx.fontPx
  const neutral = opts.neutral === true
  const boxes = []
  let n = opts.firstTarget ?? 1
  for (const [i, j, order] of p.bonds) {
    const a = p.atoms[i]
    const b = p.atoms[j]
    const dx = b.x - a.x
    const dy = b.y - a.y
    const len = Math.hypot(dx, dy) || 1
    const nx = -dy / len
    const ny = dx / len
    const offsets = order === 1 ? [0] : order === 2 ? [-4.5, 4.5] : [-8, 0, 8]
    for (const o of offsets) shape(ctx, "line", { x1: x + a.x + nx * o, y1: y + a.y + ny * o, x2: x + b.x + nx * o, y2: y + b.y + ny * o, cls: `dg-bond${opts.sticks ? " dg-stick" : ""}` })
  }
  p.atoms.forEach((a) => {
    const s = shape(ctx, "circle", { cx: x + a.x, cy: y + a.y, r: a.r, cls: neutral ? "dg-atom dg-neutral" : `dg-atom dg-atom-${a.symbol}` })
    if (opts.atomTargets) {
      s.target = `t${n}`
      boxes.push({ target: `t${n}`, bbox: { x: x + a.x - a.r, y: y + a.y - a.r, w: 2 * a.r, h: 2 * a.r } })
      n += 1
    }
  })
  if (opts.symbols !== false && !neutral) {
    p.atoms.forEach((a) => label(ctx, a.symbol, x + a.x, y + a.y, { anchor: "middle", valign: "middle", cls: "dg-atomtext" }))
  }
  if (opts.partial && row.partial_charges && !neutral) {
    const cx = p.atoms.reduce((s, a) => s + a.x, 0) / p.atoms.length
    const cy = p.atoms.reduce((s, a) => s + a.y, 0) / p.atoms.length
    p.atoms.forEach((a, i) => {
      const c = toNumber(row.partial_charges[i])
      if (c === 0) return
      // the sign goes over the atom when the atom is above the middle of the molecule, under it when below; the middle atom: under it when the angle
      // arc is over it, else over it; an atom off to one side leans a little outward.
      const dy0 = a.y - cy
      const dy = Math.abs(dy0) < 6 ? (opts.angle && row.angle ? 1 : -1) : Math.sign(dy0)
      const off = a.x - cx
      const dx = Math.abs(off) < 6 ? 0 : Math.sign(off) * Math.round(F * 0.5) // an atom to the side: its sign leans outward, away from the angle label
      const text = c > 0 ? "$\\delta^{+}$" : "$\\delta^{-}$"
      const m = ctx.measure(text, F)
      const reach = a.r + 4
      const lx = x + a.x + dx - m.w / 2
      const ly = y + a.y + dy * (reach + m.h / 2) - m.h / 2
      label(ctx, text, lx, ly, { anchor: "start", cls: "dg-partial" })
    })
  }
  if (opts.angle && row.angle && !neutral) {
    const spot = angleSpot(row)
    if (spot) {
      const c = p.atoms[spot.centre]
      const ang = (k) => {
        const e = p.atoms[spot.ends[k]]
        return (Math.atan2(-(e.y - c.y), e.x - c.x) * 180) / Math.PI
      }
      let a1 = ang(0)
      let a2 = ang(1)
      let span = (a2 - a1 + 360) % 360
      if (span > 180) {
        ;[a1, a2] = [a2, a1]
        span = 360 - span
      }
      if (Math.abs(span - 180) < 0.5) {
        a1 = 0 // a straight angle: the half circle goes over the top
        span = 180
      }
      const ra = c.r + 12
      const [sx, sy] = polar(x + c.x, y + c.y, ra, a1)
      const [ex, ey] = polar(x + c.x, y + c.y, ra, a1 + span)
      const sweep = 0 // counter-clockwise on the screen (the angle grows upward)
      shape(ctx, "path", { d: `M${sx.toFixed(1)},${sy.toFixed(1)} A${ra},${ra} 0 ${span > 180 ? 1 : 0} ${sweep} ${ex.toFixed(1)},${ey.toFixed(1)}`, cls: "dg-anglearc" })
      const text = angleText(row.angle)
      const m = ctx.measure(text, F)
      const mid = a1 + span / 2
      const [tx, ty] = polar(x + c.x, y + c.y, ra + 8 + Math.abs(Math.cos((mid * Math.PI) / 180)) * m.w / 2 + Math.abs(Math.sin((mid * Math.PI) / 180)) * m.h / 2, mid)
      label(ctx, text, tx - m.w / 2, ty - m.h / 2, { anchor: "start", cls: "dg-angletext" })
    }
  }
  return { boxes, next: n }
}

// ---- patches (ionic and metal) --------------------------------------------------------------------------------------------------------------

// The pose of a patch: ions at pixel positions, the box, and the frames of the units.
export function patchPose(row, ctx, nUnits = 1) {
  const F = ctx.fontPx
  const r = Math.round(F * 0.95)
  const gap = 8
  if (row.kind === "metal") {
    const sym = row.atoms[0].symbol
    const ds = 2 * r + gap
    const discs = []
    const rows = [4, 3]
    rows.forEach((count, ri) => {
      for (let k = 0; k < count; k++) discs.push({ symbol: sym, r, x: r + k * ds + (ri === 1 ? ds / 2 : 0), y: r + ri * (ds - 4) })
    })
    const w = Math.ceil(r * 2 + 3 * ds)
    const h = Math.ceil(2 * r + (ds - 4))
    return { kind: "metal", discs, w, h, frames: [{ x: 0, y: 0, w: 2 * r, h: 2 * r }], units: 1 }
  }
  const list = ionGroups(row).map((idx, k) => {
    const t = ionText(row, idx)
    const textW = ctx.measure(t.label, F).w
    const w = idx.length === 1 ? 2 * r : Math.max(2 * r, textW + 18)
    return { ...t, cation: k === 0, w, r }
  })
  // PATCH_ROWS x PATCH_UNITS units, each the ions of the formula in order, a row of units shifted by one ion from the one above (a lattice, not a column).
  // Two units side by side when they fit, else one under the other: the discs and their order are the same.
  const units = []
  for (let u = 0; u < PATCH_ROWS * PATCH_UNITS; u++) {
    const shift = Math.floor(u / PATCH_UNITS)
    units.push(list.map((_, k) => list[(k + shift) % list.length]))
  }
  const unitW = (ions) => ions.reduce((s, ion) => s + ion.w, 0) + (ions.length - 1) * gap
  const wide = unitW(units[0]) * PATCH_UNITS + gap * 2 + 16 <= ctx.width
  const cols = wide ? PATCH_UNITS : 1
  const rowH = 2 * r + gap
  const placed = units.map((ions, u) => {
    const col = u % cols
    const rowIndex = Math.floor(u / cols)
    let x = col * (unitW(ions) + gap * 2)
    return { ions: ions.map((ion) => { const at = { ...ion, x, y: rowIndex * rowH }; x += ion.w + gap; return at }), u, x0: col * (unitW(ions) + gap * 2), w: unitW(ions), y: rowIndex * rowH }
  })
  const rowsOut = [placed.flatMap((p) => p.ions)]
  const framed = placed.slice(0, Math.min(nUnits, PATCH_UNITS))
  const width = Math.max(...placed.map((p) => p.x0 + p.w))
  const rows = Math.ceil(units.length / cols)
  const frames = wide
    ? [{ x: framed[0].x0 - 5, y: -5, w: framed[framed.length - 1].x0 + framed[framed.length - 1].w - framed[0].x0 + 10, h: 2 * r + 10 }]
    : framed.map((p) => ({ x: p.x0 - 5, y: p.y - 5, w: p.w + 10, h: 2 * r + 10 }))
  return { kind: "ionic", rows: rowsOut, w: Math.ceil(width), h: Math.ceil(rows * 2 * r + (rows - 1) * gap), frames, units: framed.length }
}

// Draws a patch with its top left at (x, y). Returns the boxes of the discs in reading order (rows from the top, ions from the left).
export function drawPatch(ctx, p, x, y, opts = {}) {
  const neutral = opts.neutral === true
  const boxes = []
  let n = opts.firstTarget ?? 1
  const mark = (item, w, h, bx, by) => {
    const s = item
    if (opts.atomTargets) {
      s.target = `t${n}`
      boxes.push({ target: `t${n}`, bbox: { x: bx, y: by, w: Math.max(w, 24), h: Math.max(h, 24) } })
      n += 1
    }
  }
  if (p.kind === "metal") {
    for (const d of p.discs) {
      const s = shape(ctx, "circle", { cx: x + d.x, cy: y + d.y, r: d.r, cls: neutral ? "dg-atom dg-neutral" : `dg-atom dg-atom-${d.symbol}` })
      mark(s, 2 * d.r, 2 * d.r, x + d.x - d.r, y + d.y - d.r)
      if (!neutral && opts.symbols !== false) label(ctx, d.symbol, x + d.x, y + d.y, { anchor: "middle", valign: "middle", cls: "dg-atomtext" })
    }
  } else {
    for (const items of p.rows) {
      for (const ion of items) {
        const cls = neutral ? "dg-atom dg-neutral" : `dg-atom dg-ion ${ion.cation ? "dg-cation" : "dg-anion"}`
        const s = ion.atoms === 1 ? shape(ctx, "circle", { cx: x + ion.x + ion.w / 2, cy: y + ion.y + ion.r, r: ion.r, cls }) : shape(ctx, "rect", { x: x + ion.x, y: y + ion.y, w: ion.w, h: 2 * ion.r, r: ion.r, cls })
        mark(s, ion.w, 2 * ion.r, x + ion.x, y + ion.y)
        if (!neutral) {
          if (opts.symbols !== false) label(ctx, ion.label, x + ion.x + ion.w / 2, y + ion.y + ion.r, { anchor: "middle", valign: "middle", cls: "dg-atomtext" })
          // the sign of the ion, a small mark in the corner: a plus for the cation and a minus for the anion (a shape, not a colour)
          const sx = x + ion.x + ion.w - 4
          const sy = y + ion.y + 4
          shape(ctx, "circle", { cx: sx, cy: sy, r: 8, cls: "dg-sign-disc" })
          shape(ctx, "line", { x1: sx - 4, y1: sy, x2: sx + 4, y2: sy, cls: "dg-sign-stroke" })
          if (ion.cation) shape(ctx, "line", { x1: sx, y1: sy - 4, x2: sx, y2: sy + 4, cls: "dg-sign-stroke" })
        }
      }
    }
  }
  if (!neutral) {
    for (const f of p.frames) shape(ctx, "rect", { x: x + f.x, y: y + f.y, w: f.w, h: f.h, r: 8, cls: "dg-unitframe" })
  }
  return { boxes, next: n, frames: p.frames.map((f) => ({ x: x + f.x, y: y + f.y, w: f.w, h: f.h })) }
}
