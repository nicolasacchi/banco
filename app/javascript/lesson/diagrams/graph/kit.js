// What the three graph types draw in the same way (WAVE2 2.1): node boxes with an icon, arrows with an arrowhead, round plates for numbers.
// Pure: each helper adds shapes and labels to the context of common.js.
import { label, shape } from "lesson/diagrams/common"

// A point rotated by `angle` degrees around the origin, then moved.
const turn = (x, y, angle, ox, oy) => {
  const a = (angle * Math.PI) / 180
  return [ox + x * Math.cos(a) - y * Math.sin(a), oy + x * Math.sin(a) + y * Math.cos(a)]
}

// An arrowhead whose tip is at (x, y) pointing along `angle` degrees.
export function arrowhead(ctx, { x, y, angle }, cls = "dg-arrowhead", size = Math.round(ctx.fontPx * 0.6)) {
  return shape(ctx, "polygon", { points: [turn(0, 0, angle, x, y), turn(-size, -size * 0.55, angle, x, y), turn(-size, size * 0.55, angle, x, y)].map((p) => p.map((v) => Math.round(v * 10) / 10)), cls })
}

export function polyline(ctx, points, cls, key) {
  const d = points.map(([x, y], i) => `${i ? "L" : "M"}${Math.round(x * 10) / 10} ${Math.round(y * 10) / 10}`).join(" ")
  return shape(ctx, "path", { d, cls, ...(key ? { key } : {}) })
}

// The measured size of a node's content: a label (and an icon before it), then optional lines under it.
export function measureLabel(ctx, text, maxW, iconW = 0, cls = "") {
  const m = ctx.measure(text, ctx.fontPx, Math.max(40, maxW - iconW), cls)
  return { w: Math.ceil(m.w) + iconW, h: Math.ceil(m.h) }
}

export const iconSize = (ctx) => Math.round(ctx.fontPx * 1.1)

// Does a rectangle (x, y, w, h) fit the scene? The caller checks before it adds a label there.
export const inside = (ctx, r) => r.x >= 0 && r.x + r.w <= ctx.width

// A label with a plate behind it so that a line passing under stays readable: the plate is the label's own background (CSS dg-plate).
export function plateLabel(ctx, text, cx, cy, { maxW, cls = "", key, role } = {}) {
  const probe = ctx.measure(text, ctx.fontPx, maxW, `dg-plate ${cls}`.trim())
  const w = Math.min(Math.ceil(probe.w), maxW ?? Infinity)
  const item = label(ctx, text, cx - w / 2, cy - probe.h / 2, { anchor: "start", maxW: maxW ? w : undefined, cls: `dg-plate ${cls}`.trim(), key, role })
  item.x = Math.max(0, Math.min(item.x, ctx.width - item.w - 6)) // the plate has a padding: the word stays inside the figure
  return item
}

// The numbered list of moves under a figure (the phone, and a crowded figure): a number in a round plate, then the move, one under
// the other. (The number is a shape: written as "1." in a label it would be read as a list and renumbered.) Returns the y after it.
export function drawMoves(ctx, moves, y, { title, marginX = 6 } = {}) {
  let top = y
  if (title) {
    const t = label(ctx, title, marginX, top, { anchor: "start", cls: "dg-moves-title", maxW: ctx.width - 2 * marginX })
    top += t.h + 6
  }
  const r = Math.round(ctx.fontPx * 0.8)
  const textX = marginX + 2 * r + 10
  for (const move of moves) {
    const probe = ctx.measure(move.text_it, ctx.fontPx, ctx.width - textX - marginX)
    const rowH = Math.max(probe.h, 2 * r)
    shape(ctx, "circle", { cx: marginX + r, cy: top + rowH / 2, r, cls: "dg-numplate", key: `move:${move.n}:plate` })
    label(ctx, String(move.n), marginX + r, top + rowH / 2 - Math.ceil(ctx.fontPx * 0.7), { anchor: "middle", cls: "dg-numlabel", key: `move:${move.n}:n` })
    label(ctx, move.text_it, textX, top + (rowH - probe.h) / 2, { anchor: "start", cls: "dg-move", maxW: ctx.width - textX - marginX, key: `move:${move.n}` })
    top += rowH + 8
  }
  return top
}

// A number in a round plate on an arrow (the numbered mode of a crowded figure).
export function numberPlate(ctx, n, cx, cy) {
  const r = Math.round(ctx.fontPx * 0.9)
  shape(ctx, "circle", { cx, cy, r, cls: "dg-numplate" })
  label(ctx, String(n), cx, cy - Math.ceil(ctx.fontPx * 0.7), { anchor: "middle", cls: "dg-numlabel", key: `num:${n}` })
  return r
}

// A copy of a figure's data without the colour roles: what a select layout is drawn from (the roles belong to the subject's palette,
// and a select figure shows none), used by the `targets` of each type to measure the boxes.
export const withoutRoles = (data) => JSON.parse(JSON.stringify(data, (key, value) => (key === "role" ? undefined : value)))
