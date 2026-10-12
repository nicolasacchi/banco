// The graph router (WAVE2 2.1; contract frozen in W2-0, built by T4b): one layout engine for node-and-arrow figures, shared by flow,
// chain and network. Fixed positions per layout (never force-directed: a figure is the same for every student and in print), stable node
// positions across states, edge changes as a 300 ms FLIP (a swap under reduced motion, A5), and below 600 px the nodes are stacked and the
// edges become a numbered list of moves under the figure.
//
// Pure: numbers in, numbers out. The caller measures its nodes (w, h) and draws; nothing here touches the DOM.

// The layouts that have fixed positions: tree, line (a journey), ring (a cycle), pair, row, triangle, hub, fan, grid.
export const LAYOUTS = ["tree", "line", "ring", "pair", "row", "triangle", "hub", "fan", "grid"]

const MARGIN = 6

// place(layout, nodes, box, options) -> Map id -> { x, y, w, h }
//   nodes: [{ id, w, h, lane? }] sizes measured by the caller; box: { width, height?, narrow }; options: { centre?, into? }
//   Extra, all optional: gap (between neighbours across), gapY (between rows), align ("start" stacks a narrow column at `indent`),
//   indent, depth ({ id: level }, tree), branch ({ from, to }: the stations the lane-1 nodes of a `line` run between), order (ring).
export function place(layout, nodes, box, options = {}) {
  if (!LAYOUTS.includes(layout)) throw new Error(`unknown graph layout ${layout}`)
  if (!Array.isArray(nodes) || nodes.length === 0) throw new Error("place needs nodes")
  const width = box.width
  const gap = options.gap ?? 56
  const gapY = options.gapY ?? (box.narrow ? 22 : 36)
  const out = new Map()
  const put = (n, x, y) => out.set(n.id, { x: Math.round(x), y: Math.round(y), w: n.w, h: n.h })
  const maxW = Math.max(...nodes.map((n) => n.w))

  if (box.narrow && layout !== "line") return stack(nodes, width, gapY, options)

  switch (layout) {
    case "tree": {
      // levels from options.depth (default: one per node), each level centred
      const levels = new Map()
      for (const n of nodes) {
        const d = options.depth?.[n.id] ?? levels.size
        if (!levels.has(d)) levels.set(d, [])
        levels.get(d).push(n)
      }
      let y = MARGIN
      for (const d of [...levels.keys()].sort((a, b) => a - b)) {
        const row = levels.get(d)
        spread(row, width, y, put)
        y += Math.max(...row.map((n) => n.h)) + gapY
      }
      break
    }
    case "pair": {
      const [a, b] = nodes
      const h = Math.max(a.h, b.h)
      put(a, MARGIN, MARGIN + (h - a.h) / 2)
      if (b) put(b, width - MARGIN - b.w, MARGIN + (h - b.h) / 2)
      break
    }
    case "row":
    case "grid": {
      const perRow = layout === "row" ? Math.max(1, Math.min(nodes.length, Math.floor((width - 2 * MARGIN + gap) / (maxW + gap)))) : Math.max(1, Math.min(Math.ceil(Math.sqrt(nodes.length)), Math.floor((width - 2 * MARGIN + gap) / (maxW + gap))))
      let y = MARGIN
      for (let i = 0; i < nodes.length; i += perRow) {
        const row = nodes.slice(i, i + perRow)
        spread(row, width, y, put, layout === "grid" ? maxW : null)
        y += Math.max(...row.map((n) => n.h)) + gapY
      }
      break
    }
    case "triangle": {
      const [top, ...rest] = nodes
      put(top, (width - top.w) / 2, MARGIN)
      spread(rest, width, MARGIN + top.h + gapY * 1.6, put)
      break
    }
    case "fan": {
      const target = nodes.find((n) => n.id === options.into) ?? nodes[nodes.length - 1]
      const sources = nodes.filter((n) => n !== target)
      const total = sources.reduce((a, n) => a + n.h, 0) + gapY * (sources.length - 1)
      let y = MARGIN
      for (const n of sources) {
        put(n, MARGIN, y)
        y += n.h + gapY
      }
      put(target, width - MARGIN - target.w, MARGIN + (total - target.h) / 2)
      break
    }
    case "hub":
    case "ring": {
      const centre = layout === "hub" ? nodes.find((n) => n.id === options.centre) ?? nodes[0] : null
      const around = nodes.filter((n) => n !== centre)
      around.sort((a, b) => (options.order?.indexOf(a.id) ?? 0) - (options.order?.indexOf(b.id) ?? 0))
      ellipse(around, centre, width, gapY, put, out)
      break
    }
    case "line": {
      if (box.narrow) lineVertical(nodes, width, gapY, put, options)
      else lineHorizontal(nodes, width, gapY, put, options)
      break
    }
  }
  return out
}

function stack(nodes, width, gapY, options) {
  const out = new Map()
  let y = MARGIN
  for (const n of nodes) {
    const x = options.align === "start" ? (options.indent ?? 0) : (width - n.w) / 2
    out.set(n.id, { x: Math.round(x), y: Math.round(y), w: n.w, h: n.h })
    y += n.h + gapY
  }
  return out
}

// A row of nodes spread over the width (the first at the left margin, the last at the right), centred on the tallest.
function spread(row, width, y, put, cell = null) {
  const h = Math.max(...row.map((n) => n.h))
  if (row.length === 1) return put(row[0], (width - row[0].w) / 2, y + (h - row[0].h) / 2)
  const total = row.reduce((a, n) => a + (cell ?? n.w), 0)
  const free = Math.max(0, width - 2 * MARGIN - total)
  const step = free / (row.length - 1)
  let x = MARGIN
  for (const n of row) {
    put(n, x + ((cell ?? n.w) - n.w) / 2, y + (h - n.h) / 2)
    x += (cell ?? n.w) + step
  }
}

const separated = (a, b, m) => a.x + a.w + m <= b.x || b.x + b.w + m <= a.x || a.y + a.h + m <= b.y || b.y + b.h + m <= a.y

// Nodes round an ellipse, the first at the top and the rest clockwise; the vertical radius grows until nothing touches.
function ellipse(around, centre, width, gapY, put, out) {
  const maxW = Math.max(...around.map((n) => n.w), centre?.w ?? 0)
  const maxH = Math.max(...around.map((n) => n.h), centre?.h ?? 0)
  const rx = Math.max(0, (width - maxW) / 2 - MARGIN)
  const n = around.length
  const angle = (i) => -Math.PI / 2 + (2 * Math.PI * i) / n
  for (let ry = maxH + gapY; ry < 900; ry += 6) {
    const cx = width / 2
    const cy = ry + maxH / 2 + MARGIN
    const boxes = around.map((node, i) => ({ id: node.id, w: node.w, h: node.h, x: cx + rx * Math.cos(angle(i)) - node.w / 2, y: cy + ry * Math.sin(angle(i)) - node.h / 2 }))
    if (centre) boxes.push({ id: centre.id, w: centre.w, h: centre.h, x: cx - centre.w / 2, y: cy - centre.h / 2 })
    const ok = boxes.every((a, i) => boxes.slice(i + 1).every((b) => separated(a, b, 14)))
    if (ok || ry >= 899 - 6) {
      for (const b of boxes) put(b, b.x, b.y)
      return
    }
  }
}

// Stations on a horizontal line: one slot each, the label centred on its station. Lane 1 hangs under the stretch between branch.from and branch.to.
function lineHorizontal(nodes, width, gapY, put, options) {
  const main = nodes.filter((n) => !n.lane)
  const lane = nodes.filter((n) => n.lane)
  const slot = (width - 2 * MARGIN) / main.length
  const hMain = Math.max(...main.map((n) => n.h))
  main.forEach((n, i) => put(n, MARGIN + slot * i + (slot - n.w) / 2, MARGIN))
  if (lane.length) {
    const from = main.findIndex((n) => n.id === options.branch?.from)
    const to = main.findIndex((n) => n.id === options.branch?.to)
    const x0 = MARGIN + slot * (Math.max(from, 0) + 0.5)
    const x1 = MARGIN + slot * ((to < 0 ? main.length - 1 : to) + 0.5)
    const y = MARGIN + hMain + gapY * 2.2
    lane.forEach((n, i) => {
      const cx = lane.length === 1 ? (x0 + x1) / 2 : x0 + ((x1 - x0) * (i + 1)) / (lane.length + 1)
      put(n, Math.max(MARGIN, Math.min(width - MARGIN - n.w, cx - n.w / 2)), y)
    })
  }
}

// A vertical journey: the main stations down the left, the lane-1 stations indented between branch.from and branch.to.
function lineVertical(nodes, width, gapY, put, options) {
  const indent = options.indent ?? 34
  const bypass = options.bypassIndent ?? 46
  const main = nodes.filter((n) => !n.lane)
  const lane = nodes.filter((n) => n.lane)
  let y = MARGIN
  main.forEach((n) => {
    put(n, indent, y)
    y += n.h + gapY
    if (lane.length && n.id === options.branch?.from) {
      for (const l of lane) {
        put(l, indent + bypass, y)
        y += l.h + gapY
      }
    }
  })
}

// route(boxes, edges, options) -> [{ id, from, to, points: [[x, y], ...], arrow: { x, y, angle }, label: { x, y } | null }]
//   boxes: the Map of place(); edges: [{ id, from, to, back?, label? }]; options: { orthogonal: true, gap }
//   Edges between the same two nodes (either direction) are drawn side by side `gap` apart; `back` edges are arcs over the top
//   (under the bottom with side: "bottom"); label is a placeholder: the result's label point is where a label would sit.
export function route(boxes, edges, options = {}) {
  const gap = options.gap ?? 22
  const groups = new Map()
  for (const e of edges) {
    const key = [e.from, e.to].sort().join("|")
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push(e)
  }
  return edges.map((e) => {
    const a = boxes.get(e.from)
    const b = boxes.get(e.to)
    if (!a || !b) throw new Error(`route: edge ${e.id} joins a node that is not placed`)
    if (e.back) return arc(e, a, b)
    const group = groups.get([e.from, e.to].sort().join("|"))
    // opposite edges of one pair take the two sides, repeated ones are spread; the side follows the edge's own direction
    const k = group.indexOf(e)
    const sign = e.from <= e.to ? 1 : -1
    const shift = (k - (group.length - 1) / 2) * gap * sign
    return options.orthogonal ? elbow(e, a, b) : straight(e, a, b, shift)
  })
}

const centre = (r) => [r.x + r.w / 2, r.y + r.h / 2]

// Where the segment p -> q leaves the (padded) rectangle r, p being inside it; p itself when it starts outside.
function leave(r, p, q, pad = 3) {
  const [x0, y0, x1, y1] = [r.x - pad, r.y - pad, r.x + r.w + pad, r.y + r.h + pad]
  const dx = q[0] - p[0]
  const dy = q[1] - p[1]
  if (p[0] < x0 || p[0] > x1 || p[1] < y0 || p[1] > y1) return p
  const tx = dx > 0 ? (x1 - p[0]) / dx : dx < 0 ? (x0 - p[0]) / dx : Infinity
  const ty = dy > 0 ? (y1 - p[1]) / dy : dy < 0 ? (y0 - p[1]) / dy : Infinity
  const t = Math.min(tx, ty, 1)
  return [p[0] + dx * t, p[1] + dy * t]
}

function finishEdge(e, points, labelAt) {
  const [x1, y1] = points[points.length - 2]
  const [x2, y2] = points[points.length - 1]
  const angle = (Math.atan2(y2 - y1, x2 - x1) * 180) / Math.PI
  return { id: e.id, from: e.from, to: e.to, points: points.map(([x, y]) => [Math.round(x * 10) / 10, Math.round(y * 10) / 10]), arrow: { x: x2, y: y2, angle: Math.round(angle * 10) / 10 }, label: e.label === undefined || e.label === null ? null : { x: Math.round(labelAt[0]), y: Math.round(labelAt[1]) } }
}

function straight(e, a, b, shift) {
  const [ax, ay] = centre(a)
  const [bx, by] = centre(b)
  const len = Math.hypot(bx - ax, by - ay) || 1
  const nx = -(by - ay) / len
  const ny = (bx - ax) / len
  const pa = [ax + nx * shift, ay + ny * shift]
  const pb = [bx + nx * shift, by + ny * shift]
  const start = leave(a, pa, pb)
  const end = leave(b, pb, pa)
  return finishEdge(e, [start, end], [(start[0] + end[0]) / 2, (start[1] + end[1]) / 2])
}

function elbow(e, a, b) {
  const [ax, ay] = centre(a)
  const [bx, by] = centre(b)
  const overlapX = a.x < b.x + b.w && b.x < a.x + a.w
  const overlapY = a.y < b.y + b.h && b.y < a.y + a.h
  if (overlapX) {
    const x = (Math.max(a.x, b.x) + Math.min(a.x + a.w, b.x + b.w)) / 2
    const down = by > ay
    const p = [[x, down ? a.y + a.h + 2 : a.y - 2], [x, down ? b.y - 2 : b.y + b.h + 2]]
    return finishEdge(e, p, [x, (p[0][1] + p[1][1]) / 2])
  }
  if (overlapY) {
    const y = (Math.max(a.y, b.y) + Math.min(a.y + a.h, b.y + b.h)) / 2
    const right = bx > ax
    const p = [[right ? a.x + a.w + 2 : a.x - 2, y], [right ? b.x - 2 : b.x + b.w + 2, y]]
    return finishEdge(e, p, [(p[0][0] + p[1][0]) / 2, y])
  }
  const right = bx > ax
  const down = by > ay
  const start = [right ? a.x + a.w + 2 : a.x - 2, ay]
  const corner = [bx, ay]
  const end = [bx, down ? b.y - 2 : b.y + b.h + 2]
  return finishEdge(e, [start, corner, end], [(start[0] + corner[0]) / 2, ay])
}

// A return arc: out of the top of the first node, over the others, into the top of the second (a quadratic curve sampled in 14 steps).
function arc(e, a, b) {
  const below = e.side === "bottom"
  const [ax] = centre(a)
  const [bx] = centre(b)
  const ya = below ? a.y + a.h + 2 : a.y - 2
  const yb = below ? b.y + b.h + 2 : b.y - 2
  const span = Math.abs(bx - ax)
  const lift = Math.min(70, 22 + span * 0.18)
  const cy = (below ? Math.max(ya, yb) + lift * 2 : Math.min(ya, yb) - lift * 2)
  const cx = (ax + bx) / 2
  const points = []
  for (let i = 0; i <= 14; i++) {
    const t = i / 14
    points.push([(1 - t) ** 2 * ax + 2 * (1 - t) * t * cx + t * t * bx, (1 - t) ** 2 * ya + 2 * (1 - t) * t * cy + t * t * yb])
  }
  const apex = points[7]
  return finishEdge(e, points, [apex[0], apex[1] + (below ? 10 : -10)])
}

// flip(previous, next, ms) -> { keep: [id], enter: [id], leave: [id], ms } : what moves between two states; ms 300, 0 under reduced motion
//   previous and next are the ids of the drawn edges (or nodes) of the two states; ms is what the caller allows (0 under A5).
export function flip(previous, next, ms = 300) {
  const before = new Set(previous ?? [])
  const after = new Set(next ?? [])
  return {
    keep: [...after].filter((id) => before.has(id)),
    enter: [...after].filter((id) => !before.has(id)),
    leave: [...before].filter((id) => !after.has(id)),
    ms: Math.max(0, Math.min(300, ms))
  }
}

const short = (label) => String(label ?? "").split(",")[0].trim()

// moveList(nodes, edges) -> [{ n, text_it }] : the phone's numbered list of moves ("1. Da Anna a Paolo: consegna la bicicletta")
//   nodes: [{ id, label_it }]; edges: [{ from, to, label_it? }] in the order they are told.
export function moveList(nodes, edges) {
  const name = new Map(nodes.map((n) => [n.id, short(n.label_it)]))
  return edges.map((e, i) => {
    const to = name.get(e.to) ?? e.to
    const base = `Da ${name.get(e.from) ?? e.from} ${/^a/i.test(to) ? "ad" : "a"} ${to}`
    return { n: i + 1, text_it: e.label_it ? `${base}: ${e.label_it}` : base }
  })
}

// The frozen signatures, one string per function (checked by lesson/test/contract.test.mjs against the exports).
export const SIGNATURES = {
  place: "place(layout, nodes, box, options)",
  route: "route(boxes, edges, options)",
  flip: "flip(previous, next, ms)",
  moveList: "moveList(nodes, edges)",
}
