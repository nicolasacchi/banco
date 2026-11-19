// flow (A8): a decision flow as an indented tree, top to bottom: steps in a chain, a decision's branches
// indented under it with their label ("sì", "no") on the connector, ends as pills. A node already drawn
// that a branch rejoins is shown as a small "vai a" box. Readable at any width. A decision is a rhombus (D-383); a loop (`loops`) is an
// arrow from a node under a decision back to it, drawn beside the chain (flow_loops.js) or, in the indented layout, in a gutter on the right.
import { finish, hasOverlap, label, listIt, plain, roleInfo, shape } from "lesson/diagrams/common"
import { drawLoops, widestPiece } from "lesson/diagrams/flow_loops"
import palette from "lesson/palette"
import { run } from "lesson/diagrams/run"
import { buildLine, describeLine, printedLine, semanticLine, targetsLine } from "lesson/diagrams/graph/flow_line"

export const states = () => 1

export function semantic(data) {
  if (data.layout === "line") return data.loops ? { path: "/loops", message: "loops are for the tree layout: a line has returns", code: "E-LESSON-DIAGRAM" } : semanticLine(data)
  const index = new Map(data.nodes.map((n, i) => [n.id, i]))
  if (index.size !== data.nodes.length) return { path: "/nodes", message: "node ids are unique", code: "E-LESSON-MAP" }
  const out = new Map(data.nodes.map((n) => [n.id, []]))
  for (let i = 0; i < data.edges.length; i++) {
    const [from, to, text] = data.edges[i]
    if (!index.has(from) || !index.has(to)) return { path: `/edges/${i}`, message: "an edge joins two nodes", code: "E-LESSON-MAP" }
    // a cycle: `from` is reachable from `to` through the edges before this one
    const seen = new Set()
    const stack = [to]
    while (stack.length) {
      const id = stack.pop()
      if (id === from) return { path: `/edges/${i}`, message: "a flow has no cycles among its edges (a way back to a decision is written in loops)", code: "E-LESSON-MAP" }
      if (seen.has(id)) continue
      seen.add(id)
      stack.push(...out.get(id).map(([t]) => t))
    }
    out.get(from).push([to, text])
  }
  const leaving = new Map()
  const loops = data.loops ?? []
  for (let i = 0; i < loops.length; i++) {
    const { from, to } = loops[i]
    if (!index.has(from) || !index.has(to)) return { path: `/loops/${i}`, message: "a loop joins two nodes", code: "E-LESSON-MAP" }
    leaving.set(from, (leaving.get(from) ?? 0) + 1)
    if (data.nodes[index.get(to)].kind !== "decision") return { path: `/loops/${i}/to`, message: "a loop goes back to a decision", code: "E-LESSON-MAP" }
    if (from === to || !below(out, to, from)) return { path: `/loops/${i}/from`, message: "a loop starts from a node drawn under its decision", code: "E-LESSON-MAP" }
    if (data.nodes[index.get(from)].kind === "end") return { path: `/loops/${i}/from`, message: "a loop does not start from an end", code: "E-LESSON-MAP" }
    if (loops.slice(0, i).some((o) => o.from === from && o.to === to)) return { path: `/loops/${i}`, message: "the same loop is written twice", code: "E-LESSON-MAP" }
  }
  for (let i = 0; i < data.nodes.length; i++) {
    const n = data.nodes[i]
    const k = out.get(n.id).length
    if (n.kind === "decision" && (k < 2 || k > 3)) return { path: `/nodes/${i}`, message: "a decision has 2 or 3 branches", code: "E-LESSON-MAP" }
    if (n.kind === "step" && k + (leaving.get(n.id) ?? 0) > 1) return { path: `/nodes/${i}`, message: "a step leads to one node", code: "E-LESSON-MAP" }
    if (n.kind === "end" && k > 0) return { path: `/nodes/${i}`, message: "an end leads nowhere", code: "E-LESSON-MAP" }
  }
  const reach = new Set()
  const walk = (id) => {
    if (reach.has(id)) return
    reach.add(id)
    out.get(id).forEach(([t]) => walk(t))
  }
  walk(data.nodes[0].id)
  for (let i = 0; i < data.nodes.length; i++) if (!reach.has(data.nodes[i].id)) return { path: `/nodes/${i}`, message: "every node is reached from the first", code: "E-LESSON-MAP" }
  return null
}

// Is `target` reached from `from` along the edges of `out` (id to [[to, text]])?
function below(out, from, target) {
  const seen = new Set()
  const stack = [from]
  while (stack.length) {
    const id = stack.pop()
    for (const [to] of out.get(id)) {
      if (to === target) return true
      if (!seen.has(to)) {
        seen.add(to)
        stack.push(to)
      }
    }
  }
  return false
}

// The box of a decision (D-383): a rhombus that holds its text. A text of w x h fits a rhombus of width W and height H when w / W + h / H <= 1; with
// W = r * H that is H = w / r + h, and the rhombus is as flat as the text allows: r = w / h, kept between 1.5 and 2.2. Wrap, then widen: the text
// stays on one line when the rhombus around it fits `cap` (the widest there is room for); otherwise it is wrapped to three quarters of its width,
// then less, taking the first wrap that gives the lowest rhombus that fits. When none fits `cap` the answer is null (a text is never made smaller).
export function rhombus(ctx, text, cap) {
  const f = ctx.fontPx
  const extra = /\\frac|\\dfrac/.test(text) ? Math.round(f * 0.5) : 0
  const natural = ctx.measure(text, f)
  const floor = widestPiece(ctx, text)
  const wraps = [1, 0.75, 0.6, 0.5, 0.4, 0.3].map((k) => (k === 1 ? natural : ctx.measure(text, f, Math.max(floor, Math.ceil(natural.w * k)))))
  let best = null
  const consider = (mt, r) => {
    const h = Math.ceil((Math.ceil(mt.w) + ctx.pad) / r + mt.h + extra)
    const box = { w: Math.ceil(h * r), h, mt, extra, rhombus: true }
    if (!best) best = box
    else if (box.w <= cap && (best.w > cap || box.h < best.h)) best = box
    else if (box.w > cap && best.w > cap && box.w < best.w) best = box
  }
  for (const mt of wraps) consider(mt, Math.min(2.2, Math.max(1.5, (Math.ceil(mt.w) + ctx.pad) / (mt.h + extra))))
  // a text too long for any of these on a narrow screen: a taller, narrower rhombus
  if (best.w > cap) for (const r of [1.2, 1, 0.85, 0.7, 0.6]) for (const mt of wraps) consider(mt, r)
  return best.w <= cap ? best : null
}

// The rhombus as a polygon, with its text centred in it.
function paintRhombus(ctx, n, box, left, top, cls) {
  const cx = left + box.w / 2
  const cy = top + box.h / 2
  shape(ctx, "polygon", { points: [[cx, top], [left + box.w, cy], [cx, top + box.h], [left, cy]], cls })
  const tcls = `dg-nodetext${n.role ? ` role-${n.role}` : ""}`
  label(ctx, n.text_it, cx, cy - (box.mt.h + box.extra) / 2, { anchor: "middle", maxW: box.mt.h > ctx.lineH ? box.mt.w : undefined, cls: tcls, role: n.role })
}

// A tree that fits the width is drawn centred, top to bottom, with arrows: the first step as a dark box, a decision's
// branches side by side under a bus line. Anything else (a node joined twice, a narrow screen) takes the indented layout.
// The loops go beside the chain; the tree is moved off the middle if its loop needs the room (a phone), and when no place is
// clear for an arrow and its label the indented layout draws it.
function buildTree(data, ctx) {
  const W = ctx.width
  const f = ctx.fontPx
  const m = 8
  const loops = data.loops ?? []
  const out = new Map(data.nodes.map((n) => [n.id, []]))
  const indeg = new Map(data.nodes.map((n) => [n.id, 0]))
  for (const [from, to, text] of data.edges) {
    out.get(from).push({ to, text })
    indeg.set(to, indeg.get(to) + 1)
  }
  if ([...indeg.values()].some((k) => k > 1)) return null
  const byId = new Map(data.nodes.map((n) => [n.id, n]))
  const maxBox = Math.min(W - 2 * m, Math.round(f * 11))
  const iconSize = Math.round(f * 1.1)
  let fits = true
  const boxOf = (n) => {
    if (n.kind === "decision") {
      const r = rhombus(ctx, n.text_it, Math.min(W - 2 * m, Math.round(f * 16)))
      if (r) return r
      fits = false // no rhombus holds this question at this size: the indented layout draws it in a box
      return { w: 0, h: 0, mt: { w: 0, h: 0 } }
    }
    const info = n.role ? roleInfo(palette, ctx.subject, n.role) : null
    const icon = info?.icon
    const iconW = icon ? iconSize + 6 : 0
    const mt = ctx.measure(n.text_it, f, maxBox - iconW - 2 * ctx.pad - 8)
    const w = Math.min(maxBox, Math.ceil(mt.w) + iconW + 2 * ctx.pad + 8)
    const h = mt.h + 2 * ctx.pad + (/\\frac|\\dfrac/.test(n.text_it) ? Math.round(f * 0.5) : 0)
    return { w, h, icon, iconW, mt }
  }
  const gapX = 14
  const sub = (id) => {
    const n = byId.get(id)
    const kids = out.get(id).map((k) => ({ ...k, s: sub(k.to) }))
    const own = boxOf(byId.get(id))
    const kw = kids.length ? kids.reduce((a, k) => a + k.s.width, 0) + gapX * (kids.length - 1) : 0
    // the label of the last branch starts at its arrow and may run past its subtree: room for it on the right (and the left, to stay centred)
    const last = kids.at(-1)
    const over = last?.text && n.kind === "decision" ? Math.max(0, 9 + Math.ceil(ctx.measure(last.text, f).w) - last.s.width / 2) : 0
    return { id, kids, own, kw, width: Math.max(own.w, kw + 2 * over) }
  }
  const root = sub(data.nodes[0].id)
  if (!fits || root.width > W - 2 * m) return null
  const arrow = (x, y) => shape(ctx, "polygon", { points: [[x - 6, y - 9], [x + 6, y - 9], [x, y]], cls: "dg-arrowhead" })
  const rects = new Map()
  let bottomMost = 0
  const place = (t, x0, y, isRoot, isDecisionKid) => {
    const n = byId.get(t.id)
    const cx = x0 + t.width / 2
    const left = Math.round(cx - t.own.w / 2)
    const kind = isRoot && n.kind === "step" ? "start" : n.kind
    rects.set(t.id, { x: left, y, w: t.own.w, h: t.own.h, cx: left + t.own.w / 2, cy: y + t.own.h / 2 })
    if (t.own.rhombus) paintRhombus(ctx, n, t.own, left, y, `dg-node dg-${kind} st-${n.role ?? "muted"}`)
    else {
      shape(ctx, "rect", { x: left, y, w: t.own.w, h: t.own.h, r: n.kind === "end" ? Math.min(t.own.h / 2, 24) : 12, cls: `dg-node dg-${kind} st-${n.role ?? "muted"}` })
      const tcls = `dg-nodetext${kind === "start" ? " dg-starttext" : ""}${n.role ? ` role-${n.role}` : ""}`
      if (t.own.icon) {
        shape(ctx, "icon", { name: t.own.icon, x: left + ctx.pad + 2, y: y + (t.own.h - iconSize) / 2, size: iconSize, cls: `role-${n.role}` })
        label(ctx, n.text_it, left + ctx.pad + 4 + t.own.iconW, y + ctx.pad, { anchor: "start", maxW: t.own.mt.h > ctx.lineH ? t.own.mt.w : undefined, cls: tcls, role: n.role })
      } else label(ctx, n.text_it, cx, y + ctx.pad, { anchor: "middle", maxW: t.own.mt.h > ctx.lineH ? t.own.mt.w : undefined, cls: tcls, role: n.role })
    }
    const bottom = y + t.own.h
    bottomMost = Math.max(bottomMost, bottom)
    if (t.kids.length === 0) return
    const decision = n.kind === "decision"
    const gap = decision ? Math.round(f * 2.7) : Math.round(f * 1.5)
    const ky = bottom + gap
    let gx = x0 + (t.width - t.kw) / 2
    const centres = []
    for (const k of t.kids) {
      place(k.s, gx, ky, false, decision)
      centres.push(gx + k.s.width / 2)
      gx += k.s.width + gapX
    }
    if (!decision) {
      shape(ctx, "line", { x1: cx, y1: bottom, x2: centres[0], y2: ky - 8, cls: "dg-edge" })
      arrow(centres[0], ky)
      return
    }
    const bus = bottom + Math.round(f * 0.7)
    shape(ctx, "line", { x1: cx, y1: bottom, x2: cx, y2: bus, cls: "dg-edge" })
    shape(ctx, "line", { x1: Math.min(...centres, cx), y1: bus, x2: Math.max(...centres, cx), y2: bus, cls: "dg-edge" })
    t.kids.forEach((k, i) => {
      shape(ctx, "line", { x1: centres[i], y1: bus, x2: centres[i], y2: ky - 8, cls: "dg-edge" })
      arrow(centres[i], ky)
      if (k.text) label(ctx, k.text, centres[i] + 9, bus + 4, { anchor: "start", cls: "dg-note dg-edgelabel" })
    })
  }
  const free = W - 2 * m - root.width
  const attempt = (x0) => {
    ctx.shapes.length = 0
    ctx.labels.length = 0
    rects.clear()
    bottomMost = 0
    place(root, x0, 6, true, false)
    if (loops.length && !drawLoops(ctx, loops, rects, { lo: m + 4, hi: W - m - 4 })) return false
    return !hasOverlap(ctx)
  }
  const centred = m + free / 2
  let ok = attempt(centred)
  if (!ok && loops.length && free > 0) {
    // the loop needs room on its side: move the tree away from it, a little more each time
    const [first] = loops
    const dirs = rects.get(first.from).cx < rects.get(first.to).cx - 1 ? [1, -1] : [-1, 1]
    for (const frac of [0.25, 0.5, 0.75, 1]) {
      for (const dir of dirs) {
        if (!ok) ok = attempt(centred + (dir * frac * free) / 2)
      }
    }
  }
  if (!ok) {
    ctx.shapes.length = 0
    ctx.labels.length = 0
    return null
  }
  return finish(ctx, bottomMost + 6, { states: 1, state: 0 })
}

function build(data, ctx) {
  if (data.layout === "line") return buildLine(data, ctx)
  return buildTree(data, ctx) ?? buildIndented(data, ctx)
}

function buildIndented(data, ctx) {
  const W = ctx.width
  const f = ctx.fontPx
  const m = 8
  const indent = 26
  const loops = data.loops ?? []
  // the loops run in a gutter on the right, one channel each; the boxes keep to its left
  const R = W - (loops.length ? 12 * loops.length + 12 : 0)
  const out = new Map(data.nodes.map((n) => [n.id, []]))
  for (const [from, to, text] of data.edges) out.get(from).push({ to, text })
  const byId = new Map(data.nodes.map((n) => [n.id, n]))
  const drawn = new Set()
  const rects = new Map()
  let y = 6
  const iconSize = Math.round(f * 1.1)

  const box = (n, x, maxW, ref) => {
    const rh = n.kind === "decision" && !ref ? rhombus(ctx, n.text_it, maxW) : null
    if (rh) return { ...rh, pre: n.text_it }
    const r = n.role ? roleInfo(palette, ctx.subject, n.role) : null
    const icon = r?.icon
    const pre = ref ? `Vai a: ${n.text_it}` : n.text_it
    const iconW = icon ? iconSize + 6 : 0
    const mt = ctx.measure(pre, f, maxW - iconW - 2 * ctx.pad - 6)
    const w = Math.min(maxW, Math.ceil(mt.w) + iconW + 2 * ctx.pad + 6)
    // a fraction stands taller than its line: room under it, so that the next label does not touch it
    const h = mt.h + 2 * ctx.pad + (/\\frac|\\dfrac/.test(pre) ? Math.round(f * 0.5) : 0)
    return { w, h, icon, iconW, pre, mt }
  }
  const paint = (n, b, x, top, ref) => {
    const role = n.role ?? "muted"
    const kind = ref ? "ref" : n.kind
    if (b.rhombus) return paintRhombus(ctx, n, b, x, top, `dg-node dg-${kind} st-${role}`)
    shape(ctx, "rect", { x, y: top, w: b.w, h: b.h, r: kind === "end" ? Math.min(b.h / 2, 24) : kind === "decision" ? 6 : 12, cls: `dg-node dg-${kind} st-${role}` })
    if (b.icon) shape(ctx, "icon", { name: b.icon, x: x + ctx.pad + 2, y: top + (b.h - iconSize) / 2, size: iconSize, cls: `role-${n.role}` })
    label(ctx, b.pre, x + ctx.pad + 3 + b.iconW, top + ctx.pad, { anchor: "start", maxW: b.mt.h > ctx.lineH ? b.mt.w : undefined, cls: `dg-nodetext${n.role ? ` role-${n.role}` : ""}`, role: n.role })
  }
  // where a line that comes down at `x + 14` meets a decision below it: on the lower left side of its rhombus
  const edgeY = (b) => (b.rhombus ? b.h / 2 + (14 * b.h) / b.w : 0)
  const visit = (id, depth, edgeText, trunkX, isRef) => {
    const n = byId.get(id)
    const x = m + depth * indent
    if (edgeText) {
      const l = label(ctx, edgeText, x + 8, y, { anchor: "start", cls: "dg-note dg-edgelabel", maxW: R - x - m })
      y += l.h + 2
    }
    const ref = isRef || drawn.has(id)
    const b = box(n, x, R - x - m, ref)
    const top = y
    paint(n, b, x, top, ref)
    rects.set(id, { x, y: top, w: b.w, h: b.h, cy: top + b.h / 2 })
    if (trunkX !== null) shape(ctx, "line", { x1: trunkX, y1: top + b.h / 2, x2: x, y2: top + b.h / 2, cls: "dg-edge" })
    y += b.h
    if (ref) {
      y += 12
      return
    }
    drawn.add(id)
    // the label of a loop that leaves this node sits under it, at the right
    for (const lp of loops) {
      if (lp.from !== id || !lp.label_it) continue
      const l = label(ctx, lp.label_it, R - m, y + 2, { anchor: "end", maxW: Math.max(60, R - m - x - 30), cls: "dg-note dg-edgelabel dg-looplabel" })
      y += l.h + 4
    }
    const kids = out.get(id)
    if (kids.length === 0) {
      y += 12
      return
    }
    const bottom = y
    y += 14
    if (n.kind === "decision") {
      const trunk = x + 14
      for (const k of kids) visit(k.to, depth + 1, k.text, trunk, false)
      shape(ctx, "line", { x1: trunk, y1: top + edgeY(b), x2: trunk, y2: y - 12 - 6, cls: "dg-edge" })
    } else {
      const next = byId.get(kids[0].to)
      const into = next.kind === "decision" && !kids[0].text && !drawn.has(next.id) ? edgeY(box(next, x, R - x - m, false)) : 0
      shape(ctx, "line", { x1: x + 14, y1: bottom, x2: x + 14, y2: y + into, cls: "dg-edge dg-arrow" })
      visit(kids[0].to, depth, kids[0].text, null, false)
    }
  }
  visit(data.nodes[0].id, 0, null, null, false)
  // the loops: out of the right side of a node, up a channel of the gutter (the longer ones outside), into the right corner of the decision
  const span = (lp) => rects.get(lp.from).cy - rects.get(lp.to).cy
  const rank = new Map([...loops].sort((a, b) => span(b) - span(a)).map((lp, j) => [lp, j]))
  for (const lp of loops) {
    const from = rects.get(lp.from)
    const to = rects.get(lp.to)
    const X = R + 8 + 12 * (loops.length - 1 - rank.get(lp))
    const tip = to.x + to.w
    shape(ctx, "path", { d: `M${from.x + from.w},${from.cy} H${X} V${to.cy} H${tip + 8}`, cls: "dg-edge dg-loop" })
    shape(ctx, "polygon", { points: [[tip + 9, to.cy - 6], [tip + 9, to.cy + 6], [tip, to.cy]], cls: "dg-arrowhead" })
  }
  return finish(ctx, y, { states: 1, state: 0 })
}

export function describe(data, ctx) {
  if (data.layout === "line") return describeLine(data, ctx)
  const byId = new Map(data.nodes.map((n) => [n.id, n]))
  const out = new Map(data.nodes.map((n) => [n.id, []]))
  for (const [from, to, text] of data.edges) out.get(from).push({ to, text })
  // where the loops of a node lead: "si torna a «question» (label)"
  const back = (n) => (data.loops ?? []).filter((l) => l.from === n.id).map((l) => `si torna a «${plain(byId.get(l.to)?.text_it)}»${l.label_it ? ` (${plain(l.label_it)})` : ""}`)
  const lines = data.nodes.map((n) => {
    const next = out.get(n.id)
    const t = plain(n.text_it)
    if (n.kind === "end") return `Fine: ${t}.`
    if (n.kind === "decision") return `Domanda: ${t} ${listIt(next.map((k) => `${plain(k.text ?? "")} porta a «${plain(byId.get(k.to).text_it)}»`.trim()))}.${back(n).map((b) => ` Da qui ${b}.`).join("")}`
    const then = next[0] ? [`poi «${plain(byId.get(next[0].to).text_it)}»`] : back(n).map((b) => `poi ${b}`)
    return `Passo: ${t}${then.map((b) => `, ${b}`).join("")}.`
  })
  return `Uno schema a domande. ${lines.join(" ")}`
}

export const layout = (data, opts) => run(data, opts, { semantic, build })

// Every string a state prints (L4); the select targets of a line are its stations.
export function printed(data, state = 0) {
  if (data.layout === "line") return printedLine(data, state)
  const out = data.nodes.flatMap((n) => [n.text_it, n.actor_it]).concat(data.edges.map((e) => e[2]), (data.loops ?? []).map((l) => l.label_it))
  return [...new Set(out.filter(Boolean).map(String))]
}

export const targets = (data, set) => targetsLine(data, set, layout)
