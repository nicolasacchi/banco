// concept_map (A8): a tree of ideas, root at the top. Tidy top-down tree from 640 px; below that an
// indented outline with connectors (still a map, readable on a phone). Edge labels sit on the connector.
// Cross links are dashed lines (tree) and are always also listed as text under the map.
import palette from "lesson/palette"
import { fail, finish, hasOverlap, label, listIt, plain, roleInfo, shape, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const states = () => 1

export function semantic(data, ctx) {
  const ids = new Map(data.nodes.map((n, i) => [n.id, i]))
  if (ids.size !== data.nodes.length) return { path: "/nodes", message: "node ids are unique", code: "E-LESSON-MAP" }
  if (!ids.has(data.root)) return { path: "/root", message: "the root is one of the nodes", code: "E-LESSON-MAP" }
  const allowed = ctx.icons ?? new Set([...palette.icons.structural, ...(palette.icons.subjects[ctx.subject] ?? [])])
  for (let i = 0; i < data.nodes.length; i++) {
    const nd = data.nodes[i]
    if (words(nd.text_it) > 6) return { path: `/nodes/${i}/text_it`, message: "a node has at most 6 words" }
    if (nd.icon && !allowed.has(nd.icon)) return { path: `/nodes/${i}/icon`, message: "an icon that is not in our list", code: "E-LESSON-ICON" }
  }
  const parent = new Map()
  const children = new Map()
  for (let i = 0; i < data.edges.length; i++) {
    const e = data.edges[i]
    if (e.label_it && words(e.label_it) > 3) return { path: `/edges/${i}/label_it`, message: "an edge label has at most 3 words" }
    if (!ids.has(e.from) || !ids.has(e.to)) return { path: `/edges/${i}`, message: "an edge joins two nodes", code: "E-LESSON-MAP" }
    if (e.to === data.root || parent.has(e.to)) return { path: `/edges/${i}`, message: "the edges form a tree", code: "E-LESSON-MAP" }
    parent.set(e.to, e.from)
    children.set(e.from, [...(children.get(e.from) ?? []), e.to])
  }
  for (const [, list] of children) if (list.length > 4) return { path: "/edges", message: "at most 4 children per node", code: "E-LESSON-MAP" }
  const depth = (id) => (id === data.root ? 0 : 1 + depth(parent.get(id)))
  for (const nd of data.nodes) {
    if (nd.id !== data.root && !parent.has(nd.id)) return { path: "/nodes", message: "every node hangs from the root", code: "E-LESSON-MAP" }
    if (depth(nd.id) > 3) return { path: "/edges", message: "a tree of depth 3 at most", code: "E-LESSON-MAP" }
  }
  for (let i = 0; i < (data.links ?? []).length; i++) {
    const l = data.links[i]
    if (!ids.has(l.from) || !ids.has(l.to)) return { path: `/links/${i}`, message: "a link joins two nodes", code: "E-LESSON-MAP" }
    if (l.label_it && words(l.label_it) > 3) return { path: `/links/${i}/label_it`, message: "an edge label has at most 3 words" }
  }
  return null
}

function tree(data) {
  const byId = new Map(data.nodes.map((n) => [n.id, n]))
  const kids = new Map()
  for (const e of data.edges) kids.set(e.from, [...(kids.get(e.from) ?? []), { id: e.to, label: e.label_it }])
  return { byId, kids }
}

function nodeBox(ctx, nd, maxW) {
  const f = ctx.fontPx
  const r = nd.role ? roleInfo(palette, ctx.subject, nd.role) : null
  const iconName = nd.icon ?? (r?.carrier === "icon" ? r.icon : null)
  const iconW = iconName ? Math.round(f * 1.1) + 6 : 0
  const m = ctx.measure(nd.text_it, f, maxW - iconW - 2 * ctx.pad - 4)
  return { iconName, iconW, w: Math.ceil(m.w) + iconW + 2 * ctx.pad + 4, h: Math.max(m.h, Math.round(f * 1.2)) + 2 * ctx.pad, textH: m.h, textW: Math.ceil(m.w) }
}

function drawBox(ctx, nd, box, x, y) {
  const role = nd.role ?? "muted"
  shape(ctx, "rect", { x, y, w: box.w, h: box.h, r: 12, cls: `dg-node st-${role}` })
  if (box.iconName) shape(ctx, "icon", { name: box.iconName, x: x + ctx.pad + 2, y: y + (box.h - Math.round(ctx.fontPx * 1.1)) / 2, size: Math.round(ctx.fontPx * 1.1), cls: `role-${role}` })
  label(ctx, nd.text_it, x + ctx.pad + 2 + box.iconW, y + (box.h - box.textH) / 2, { anchor: "start", maxW: box.textH > ctx.lineH ? box.textW : undefined, cls: `dg-nodetext role-${role}`, role: nd.role })
}

function build(data, ctx) {
  const { byId, kids } = tree(data)
  const W = ctx.width
  const m = 8
  const depthOf = (id, d = 0) => Math.max(d, ...(kids.get(id) ?? []).map((c) => depthOf(c.id, d + 1)))
  let height
  if (W >= 640) {
    height = treeLayout(ctx, data, byId, kids, W, m, depthOf(data.root))
  }
  if (height === undefined || height.error || hasOverlap(ctx)) {
    ctx.shapes.length = 0
    ctx.labels.length = 0
    height = outline(ctx, data, byId, kids, W, m)
  }
  if (height.error) return height
  let y = height
  for (const l of data.links ?? []) {
    const text = `${byId.get(l.from).text_it} ↔ ${byId.get(l.to).text_it}${l.label_it ? `: ${l.label_it}` : ""}`
    shape(ctx, "icon", { name: "link", x: m, y: y + 4, size: Math.round(ctx.fontPx * 1.1), cls: "role-muted" })
    const t = label(ctx, text, m + Math.round(ctx.fontPx * 1.1) + 6, y, { anchor: "start", maxW: W - 2 * m - Math.round(ctx.fontPx * 1.1) - 6, cls: "dg-note" })
    y += t.h + 4
  }
  return finish(ctx, y + 4, { states: 1, state: 0 })
}

function treeLayout(ctx, data, byId, kids, W, m, depth) {
  const f = ctx.fontPx
  const maxNodeW = Math.min(230, Math.floor((W - 2 * m) / 3))
  const boxes = new Map(data.nodes.map((n) => [n.id, nodeBox(ctx, n, maxNodeW)]))
  const gap = 14
  const widthOf = new Map()
  const subtree = (id) => {
    const list = kids.get(id) ?? []
    const own = boxes.get(id).w
    const w = list.length === 0 ? own : Math.max(own, list.reduce((s, c) => s + subtree(c.id), 0) + gap * (list.length - 1))
    widthOf.set(id, w)
    return w
  }
  const total = subtree(data.root)
  if (total > W - 2 * m) return { error: true }
  const levelGap = (data.edges.some((e) => e.label_it) ? 2 * ctx.lineH : ctx.lineH) + 26
  const rowH = []
  const heightAt = (id, d = 0) => {
    rowH[d] = Math.max(rowH[d] ?? 0, boxes.get(id).h)
    for (const c of kids.get(id) ?? []) heightAt(c.id, d + 1)
  }
  heightAt(data.root)
  const yAt = (d) => 6 + rowH.slice(0, d).reduce((s, h) => s + h + levelGap, 0)
  const centres = new Map()
  const place = (id, left, d) => {
    const box = boxes.get(id)
    const w = widthOf.get(id)
    const cx = left + w / 2
    centres.set(id, { cx, y: yAt(d), h: box.h })
    let x = left
    const list = kids.get(id) ?? []
    const used = list.reduce((s, c) => s + widthOf.get(c.id), 0) + gap * Math.max(0, list.length - 1)
    x += (w - used) / 2
    for (const c of list) {
      place(c.id, x, d + 1)
      x += widthOf.get(c.id) + gap
    }
  }
  place(data.root, Math.round((W - total) / 2), 0)
  for (const [id, kidList] of kids) {
    const p = centres.get(id)
    for (const c of kidList) {
      const q = centres.get(c.id)
      shape(ctx, "path", { d: `M${p.cx},${p.y + p.h} V${(p.y + p.h + q.y) / 2} H${q.cx} V${q.y}`, cls: "dg-edge" })
      if (c.label) {
        const probe = ctx.measure(c.label, f, 150)
        const l = label(ctx, c.label, q.cx, q.y - probe.h - 6, { cls: "dg-note dg-edgelabel", maxW: 150 })
        l.x = Math.max(0, Math.min(l.x, W - l.w))
      }
    }
  }
  for (const nd of data.nodes) {
    const c = centres.get(nd.id)
    const box = boxes.get(nd.id)
    drawBox(ctx, nd, box, c.cx - box.w / 2, c.y)
  }
  for (const l of data.links ?? []) {
    const a = centres.get(l.from)
    const b = centres.get(l.to)
    shape(ctx, "line", { x1: a.cx, y1: a.y + a.h / 2, x2: b.cx, y2: b.y + b.h / 2, cls: "dg-link" })
  }
  return yAt(rowH.length - 1) + rowH[rowH.length - 1] + 8
}

function outline(ctx, data, byId, kids, W, m) {
  const indent = 26
  let y = 6
  const walk = (id, d, edgeLabel, parentTrunk) => {
    const x = m + d * indent
    const nd = byId.get(id)
    const box = nodeBox(ctx, nd, W - x - m)
    if (edgeLabel) {
      const l = label(ctx, edgeLabel, x + 4, y, { anchor: "start", maxW: W - x - m, cls: "dg-note dg-edgelabel" })
      y += l.h + 2
    }
    const top = y
    drawBox(ctx, nd, box, x, y)
    if (d > 0) shape(ctx, "line", { x1: parentTrunk, y1: top + box.h / 2, x2: x, y2: top + box.h / 2, cls: "dg-edge" })
    y += box.h + 10
    const list = kids.get(id) ?? []
    const trunk = x + 12
    const startY = top + box.h
    let lastMid = startY
    for (const c of list) {
      const childTop = y
      walk(c.id, d + 1, c.label, trunk)
      lastMid = Math.max(lastMid, childTop)
    }
    if (list.length) shape(ctx, "line", { x1: trunk, y1: startY, x2: trunk, y2: y - 10 - ctx.fontPx * 0.5, cls: "dg-edge" })
  }
  walk(data.root, 0, null, 0)
  return y
}

export function describe(data) {
  const { byId, kids } = tree(data)
  const line = (id, depth) => {
    const list = kids.get(id) ?? []
    const here = plain(byId.get(id).text_it)
    if (list.length === 0) return here
    return `${here}, da cui ${listIt(list.map((c) => `${c.label ? `${plain(c.label)}: ` : ""}${line(c.id, depth + 1)}`))}`
  }
  const links = (data.links ?? []).map((l) => `«${plain(byId.get(l.from).text_it)}» è collegato a «${plain(byId.get(l.to).text_it)}»${l.label_it ? ` (${plain(l.label_it)})` : ""}`)
  return `Una mappa di idee. ${line(data.root, 0)}.${links.length ? ` Collegamenti: ${listIt(links)}.` : ""}`
}

export const layout = (data, opts) => run(data, opts, { semantic, build })
export { fail }
