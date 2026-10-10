// flow (A8): a decision flow as an indented tree, top to bottom: steps in a chain, a decision's branches
// indented under it with their label ("sì", "no") on the connector, ends as pills. A node already drawn
// that a branch rejoins is shown as a small "vai a" box. Readable at any width.
import { finish, hasOverlap, label, listIt, plain, roleInfo, shape } from "lesson/diagrams/common"
import palette from "lesson/palette"
import { run } from "lesson/diagrams/run"

export const states = () => 1

export function semantic(data) {
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
      if (id === from) return { path: `/edges/${i}`, message: "a flow has no cycles", code: "E-LESSON-MAP" }
      if (seen.has(id)) continue
      seen.add(id)
      stack.push(...out.get(id).map(([t]) => t))
    }
    out.get(from).push([to, text])
  }
  for (let i = 0; i < data.nodes.length; i++) {
    const n = data.nodes[i]
    const k = out.get(n.id).length
    if (n.kind === "decision" && (k < 2 || k > 3)) return { path: `/nodes/${i}`, message: "a decision has 2 or 3 branches", code: "E-LESSON-MAP" }
    if (n.kind === "step" && k > 1) return { path: `/nodes/${i}`, message: "a step leads to one node", code: "E-LESSON-MAP" }
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

// A tree that fits the width is drawn centred, top to bottom, with arrows: the first step as a dark box, a decision's
// branches side by side under a bus line. Anything else (a node joined twice, a narrow screen) takes the indented layout.
function buildTree(data, ctx) {
  const W = ctx.width
  const f = ctx.fontPx
  const m = 8
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
  const boxOf = (n) => {
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
    const kids = out.get(id).map((k) => ({ ...k, s: sub(k.to) }))
    const own = boxOf(byId.get(id))
    const kw = kids.length ? kids.reduce((a, k) => a + k.s.width, 0) + gapX * (kids.length - 1) : 0
    return { id, kids, own, kw, width: Math.max(own.w, kw) }
  }
  const root = sub(data.nodes[0].id)
  if (root.width > W - 2 * m) return null
  const arrow = (x, y) => shape(ctx, "polygon", { points: [[x - 6, y - 9], [x + 6, y - 9], [x, y]], cls: "dg-arrowhead" })
  let bottomMost = 0
  const place = (t, x0, y, isRoot, isDecisionKid) => {
    const n = byId.get(t.id)
    const cx = x0 + t.width / 2
    const left = Math.round(cx - t.own.w / 2)
    const kind = isRoot && n.kind === "step" ? "start" : n.kind
    shape(ctx, "rect", { x: left, y, w: t.own.w, h: t.own.h, r: n.kind === "end" ? Math.min(t.own.h / 2, 24) : n.kind === "decision" ? 6 : 12, cls: `dg-node dg-${kind} st-${n.role ?? "muted"}` })
    const tcls = `dg-nodetext${kind === "start" ? " dg-starttext" : ""}${n.role ? ` role-${n.role}` : ""}`
    if (t.own.icon) {
      shape(ctx, "icon", { name: t.own.icon, x: left + ctx.pad + 2, y: y + (t.own.h - iconSize) / 2, size: iconSize, cls: `role-${n.role}` })
      label(ctx, n.text_it, left + ctx.pad + 4 + t.own.iconW, y + ctx.pad, { anchor: "start", maxW: t.own.mt.h > ctx.lineH ? t.own.mt.w : undefined, cls: tcls, role: n.role })
    } else label(ctx, n.text_it, cx, y + ctx.pad, { anchor: "middle", maxW: t.own.mt.h > ctx.lineH ? t.own.mt.w : undefined, cls: tcls, role: n.role })
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
  place(root, m + (W - 2 * m - root.width) / 2, 6, true, false)
  if (hasOverlap(ctx)) {
    ctx.shapes.length = 0
    ctx.labels.length = 0
    return null
  }
  return finish(ctx, bottomMost + 6, { states: 1, state: 0 })
}

function build(data, ctx) {
  return buildTree(data, ctx) ?? buildIndented(data, ctx)
}

function buildIndented(data, ctx) {
  const W = ctx.width
  const f = ctx.fontPx
  const m = 8
  const indent = 26
  const out = new Map(data.nodes.map((n) => [n.id, []]))
  for (const [from, to, text] of data.edges) out.get(from).push({ to, text })
  const byId = new Map(data.nodes.map((n) => [n.id, n]))
  const drawn = new Set()
  let y = 6
  const iconSize = Math.round(f * 1.1)

  const box = (n, x, maxW, ref) => {
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
    shape(ctx, "rect", { x, y: top, w: b.w, h: b.h, r: kind === "end" ? Math.min(b.h / 2, 24) : kind === "decision" ? 4 : 12, cls: `dg-node dg-${kind} st-${role}` })
    if (b.icon) shape(ctx, "icon", { name: b.icon, x: x + ctx.pad + 2, y: top + (b.h - iconSize) / 2, size: iconSize, cls: `role-${n.role}` })
    label(ctx, b.pre, x + ctx.pad + 3 + b.iconW, top + ctx.pad, { anchor: "start", maxW: b.mt.h > ctx.lineH ? b.mt.w : undefined, cls: `dg-nodetext${n.role ? ` role-${n.role}` : ""}`, role: n.role })
  }
  const visit = (id, depth, edgeText, trunkX, isRef) => {
    const n = byId.get(id)
    const x = m + depth * indent
    if (edgeText) {
      const l = label(ctx, edgeText, x + 8, y, { anchor: "start", cls: "dg-note dg-edgelabel", maxW: W - x - m })
      y += l.h + 2
    }
    const ref = isRef || drawn.has(id)
    const b = box(n, x, W - x - m, ref)
    const top = y
    paint(n, b, x, top, ref)
    if (trunkX !== null) shape(ctx, "line", { x1: trunkX, y1: top + b.h / 2, x2: x, y2: top + b.h / 2, cls: "dg-edge" })
    y += b.h
    if (ref) {
      y += 12
      return
    }
    drawn.add(id)
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
      shape(ctx, "line", { x1: trunk, y1: bottom, x2: trunk, y2: y - 12 - 6, cls: "dg-edge" })
    } else {
      shape(ctx, "line", { x1: x + 14, y1: bottom, x2: x + 14, y2: y, cls: "dg-edge dg-arrow" })
      visit(kids[0].to, depth, kids[0].text, null, false)
    }
  }
  visit(data.nodes[0].id, 0, null, null, false)
  return finish(ctx, y, { states: 1, state: 0 })
}

export function describe(data) {
  const byId = new Map(data.nodes.map((n) => [n.id, n]))
  const out = new Map(data.nodes.map((n) => [n.id, []]))
  for (const [from, to, text] of data.edges) out.get(from).push({ to, text })
  const lines = data.nodes.map((n) => {
    const next = out.get(n.id)
    const t = plain(n.text_it)
    if (n.kind === "end") return `Fine: ${t}.`
    if (n.kind === "decision") return `Domanda: ${t} ${listIt(next.map((k) => `${plain(k.text ?? "")} porta a «${plain(byId.get(k.to).text_it)}»`.trim()))}.`
    return `Passo: ${t}${next[0] ? `, poi «${plain(byId.get(next[0].to).text_it)}»` : ""}.`
  })
  return `Uno schema a domande. ${lines.join(" ")}`
}

export const layout = (data, opts) => run(data, opts, { semantic, build })
