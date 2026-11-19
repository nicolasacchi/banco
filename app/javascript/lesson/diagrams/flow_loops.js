// The way back of a tree flow (D-383): an orthogonal arrow from a node under a decision to that decision, drawn beside the chain. It leaves
// `from` on one side, runs vertically in a channel clear of every node, line and label, and enters the decision at its side vertex with an
// arrowhead; its label sits next to the channel. Used by the centred tree of flow.js; the indented layout draws its own (a gutter on the right).
import { crosses, label, overlaps, shape } from "lesson/diagrams/common"

const HEAD = 9
const HALF = 6
const STEP = 4

// Everything already drawn that an arrow must keep off: node boxes (by id), the labels, the lines and arrowheads.
function obstacles(ctx, rects) {
  const list = []
  for (const [id, r] of rects) list.push({ id, x: r.x, y: r.y, w: r.w, h: r.h })
  for (const l of ctx.labels) list.push({ x: l.x, y: l.y, w: l.w, h: l.h })
  for (const s of ctx.shapes) {
    if (s.kind === "line") list.push({ x: Math.min(s.x1, s.x2), y: Math.min(s.y1, s.y2), w: Math.abs(s.x2 - s.x1), h: Math.abs(s.y2 - s.y1) })
    else if (s.kind === "polygon" && s.points) {
      const xs = s.points.map((p) => p[0])
      const ys = s.points.map((p) => p[1])
      list.push({ x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys) })
    }
  }
  return list
}

const asRect = (s) => ({ x: Math.min(s.x1, s.x2), y: Math.min(s.y1, s.y2), w: Math.abs(s.x2 - s.x1), h: Math.abs(s.y2 - s.y1) })

// The candidate boxes of a label of size (w, h) around a channel at X running from yTop to yBottom: beside it, on the far side first (away
// from the chain) then on the near side, from the middle of the channel outwards.
function spots(X, sgn, yTop, yBottom, w, h) {
  const mid = (yTop + yBottom) / 2 - h / 2
  const ys = []
  for (let y = yTop - h / 2; y <= yBottom - h / 2; y += 6) ys.push(Math.round(y))
  ys.sort((a, b) => Math.abs(a - mid) - Math.abs(b - mid))
  const out = []
  for (const y of ys) {
    out.push({ x: Math.round(sgn > 0 ? X + 7 : X - 7 - w), y }, { x: Math.round(sgn > 0 ? X - 7 - w : X + 7), y })
  }
  return out
}

// The width of the widest unbreakable piece of a text (a word, or a $formula$ with what sticks to it): a text is never wrapped narrower than that
// (the browser would let the word run out of its box).
export function widestPiece(ctx, text) {
  let widest = 0
  for (const piece of String(text).match(/\$[^$]*\$\S*|\S+/g) ?? []) widest = Math.max(widest, Math.ceil(ctx.measure(piece, ctx.fontPx).w))
  return widest + 1
}

// A label of one line if it fits, then wrapped narrower: the sizes to try, the widest first.
function sizes(ctx, text) {
  const natural = ctx.measure(text, ctx.fontPx)
  const floor = widestPiece(ctx, text)
  const widths = [...new Set([Math.ceil(natural.w), ...[0.66, 0.5, 0.4].map((k) => Math.max(floor, Math.ceil(natural.w * k)))])]
  const seen = new Set()
  const out = []
  for (const w0 of widths) {
    const m = w0 === Math.ceil(natural.w) ? natural : ctx.measure(text, ctx.fontPx, w0)
    const key = `${Math.ceil(m.w)}x${m.h}`
    if (seen.has(key)) continue
    seen.add(key)
    out.push({ w: Math.ceil(m.w), h: Math.ceil(m.h), wrapped: m.h > ctx.lineH })
  }
  return out
}

// Draws every loop, in order; true when all were routed. `rects` maps a node id to its box { x, y, w, h, cx, cy }; `bounds` is the box the
// drawing may use, { lo, hi } for the channels.
export function drawLoops(ctx, loops, rects, bounds) {
  const drawn = []
  for (const lp of loops) {
    const from = rects.get(lp.from)
    const to = rects.get(lp.to)
    if (!from || !to) return false
    const all = obstacles(ctx, rects)
    const routing = all.filter((o) => o.id !== lp.from && o.id !== lp.to).concat(drawn)
    const sides = from.cx < to.cx - 1 ? [-1, 1] : [1, -1]
    let found = null
    for (const sgn of sides) {
      const x0 = sgn > 0 ? from.x + from.w : from.x
      const t0 = sgn > 0 ? to.x + to.w : to.x
      const start = sgn > 0 ? Math.max(x0, t0) + 14 : Math.min(x0, t0) - 14
      for (let X = start; X >= bounds.lo && X <= bounds.hi && !found; X += sgn * STEP) {
        const segs = [
          { x1: x0, y1: from.cy, x2: X, y2: from.cy },
          { x1: X, y1: from.cy, x2: X, y2: to.cy },
          { x1: X, y1: to.cy, x2: t0 + sgn * HEAD, y2: to.cy }
        ]
        if (segs.some((s) => routing.some((o) => crosses(s, o, 5)))) continue
        const text = lp.label_it
        let spot = null
        if (text) {
          for (const size of sizes(ctx, text)) {
            for (const c of spots(X, sgn, to.cy, from.cy, size.w, size.h)) {
              const probe = { x: c.x, y: c.y, w: size.w, h: size.h }
              const padded = { x: probe.x - 4, y: probe.y - 4, w: probe.w + 8, h: probe.h + 8 }
              if (probe.x < 2 || probe.x + probe.w > ctx.width - 2) continue
              if (all.some((o) => overlaps(padded, o)) || drawn.some((o) => overlaps(padded, o))) continue
              if (segs.some((s) => crosses(s, probe, 3))) continue
              spot = { ...probe, wrapped: size.wrapped }
              break
            }
            if (spot) break
          }
          if (!spot) continue
        }
        found = { segs, X, x0, t0, sgn, spot, text }
      }
      if (found) break
    }
    if (!found) return false
    const { segs, X, t0, sgn, spot, text } = found
    shape(ctx, "path", { d: `M${segs[0].x1},${segs[0].y1} H${X} V${to.cy} H${t0 + sgn * (HEAD - 1)}`, cls: "dg-edge dg-loop" })
    shape(ctx, "polygon", { points: [[t0 + sgn * HEAD, to.cy - HALF], [t0 + sgn * HEAD, to.cy + HALF], [t0, to.cy]], cls: "dg-arrowhead" })
    if (spot) label(ctx, text, spot.x, spot.y, { anchor: "start", maxW: spot.wrapped ? spot.w : undefined, cls: "dg-note dg-edgelabel dg-looplabel" })
    for (const s of segs) drawn.push(asRect(s))
  }
  return true
}
