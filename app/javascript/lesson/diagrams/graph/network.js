// network (WAVE2 2.1, T4b): who is linked to whom, by what. Typed, directed relations between actors, in both directions at once, with a
// note on a node, badges at the ends of an arrow, "holds" under a node, kind chips that filter the arrows and states with Avanti.
// Fixed positions per layout (pair, row, triangle, hub, fan, grid) from the graph router, the same for every state; below 600 px the
// nodes stack and the arrows become a numbered list of moves under the figure (A5, A3). Nothing here is random.
import KINDS from "lesson/data/network-kinds"
import schema from "lesson/diagram_schemas/network"
import { effectiveState, finish, label, listIt, overlaps, plain, shape, stateCount, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { arrowhead, drawMoves, iconSize, measureLabel, numberPlate, polyline, withoutRoles } from "lesson/diagrams/graph/kit"
import { moveList, place, route } from "lesson/diagrams/graph/router"
import { TEXT } from "lesson/diagrams/graph/texts"

export { schema }
export const type = "network"
export const states = stateCount

const NOTE_WORDS = 25
const LABEL_WORDS = 6
const EVERYONE = "everyone"

const eachState = (data) => (Array.isArray(data.states) && data.states.length ? data.states.map((_, i) => ({ eff: effectiveState(data, i), path: `/states/${i}` })) : [{ eff: effectiveState(data, 0), path: "" }])
const short = (text) => String(text ?? "").split(",")[0].trim()
const idsOf = (data) => new Set([...data.nodes.map((n) => n.id), ...(data.everyone ? [EVERYONE] : [])])
const edgeText = (e) => e.label_it ?? KINDS.kinds[e.kind]?.label_it ?? e.kind

// The same checks as Lessons::Diagrams::Network (static, then each effective state), the first finding only.
export function semantic(data) {
  const map = (path, message) => ({ path, message, code: "E-LESSON-MAP" })
  const dia = (path, message) => ({ path, message, code: "E-LESSON-DIAGRAM" })
  const ids = idsOf(data)
  const declared = data.nodes.map((n) => n.id)
  if (new Set(declared).size !== declared.length) return map("/nodes", "node ids must be unique")
  if (data.everyone && declared.includes(EVERYONE)) return map("/nodes", `the id ${EVERYONE} is kept for the node "tutti gli altri"`)
  const n = data.nodes.length
  if (data.layout === "pair" && n !== 2) return dia("/nodes", `a pair has exactly 2 nodes (here ${n})`)
  if (data.layout === "triangle" && n !== 3) return dia("/nodes", `a triangle has exactly 3 nodes (here ${n})`)
  if (data.layout === "hub") {
    if (!data.centre) return dia("/centre", "a hub names its centre")
    if (!declared.includes(data.centre)) return map("/centre", "the centre is not a node")
    if (n < 3) return dia("/nodes", "a hub has a centre and at least 2 more nodes")
  } else if (data.centre !== undefined) return dia("/centre", "centre is for the hub layout only")
  if (data.layout === "fan") {
    if (!data.into) return dia("/into", "a fan names the node everything flows into")
    if (!declared.includes(data.into)) return map("/into", "into is not a node")
    if (n < 3) return dia("/nodes", "a fan has a target and at least 2 sources")
    const incoming = new Set((data.edges ?? []).filter((e) => e.to === data.into).map((e) => e.from))
    if (incoming.size < 2) return dia("/edges", `a fan needs at least 2 arrows into ${data.into} (here ${incoming.size})`)
  } else if (data.into !== undefined) return dia("/into", "into is for the fan layout only")
  if (data.filter && data.layout !== "hub") return dia("/filter", "the kind chips are for the hub layout only")
  if (data.everyone && data.layout === "pair" && n !== 2) return dia("/nodes", "a pair has exactly 2 nodes")
  for (let i = 0; i < n; i++) {
    const node = data.nodes[i]
    if (words(node.label_it) > LABEL_WORDS) return dia(`/nodes/${i}/label_it`, `a label has ${words(node.label_it)} words (at most ${LABEL_WORDS})`)
    if (node.note_it && words(node.note_it) > NOTE_WORDS) return dia(`/nodes/${i}/note_it`, `a note has ${words(node.note_it)} words (at most ${NOTE_WORDS})`)
  }
  for (const { eff, path } of eachState(data)) {
    const hidden = new Set(eff.hide ?? [])
    for (const [i, h] of (eff.hide ?? []).entries()) if (!ids.has(h)) return map(`${path}/hide/${i}`, "a hidden id is not a node")
    const seen = new Set()
    for (const [i, e] of (eff.edges ?? []).entries()) {
      const at = `${path}/edges/${i}`
      if (!ids.has(e.from) || !ids.has(e.to)) return map(at, "the arrow names a node that does not exist")
      if (e.from === e.to) return map(at, "an arrow joins two different nodes")
      if (hidden.has(e.from) || hidden.has(e.to)) return map(at, "an arrow cannot reach a hidden node")
      const key = `${e.from}>${e.to}:${e.kind}`
      if (seen.has(key)) return map(at, "the same arrow is written twice")
      seen.add(key)
      if (e.label_it && words(e.label_it) > LABEL_WORDS) return dia(`${at}/label_it`, `a label has ${words(e.label_it)} words (at most ${LABEL_WORDS})`)
    }
    for (const [i, h] of (eff.holds ?? []).entries()) {
      if (!declared.includes(h.node)) return map(`${path}/holds/${i}/node`, "holds names a node that does not exist")
      if (hidden.has(h.node)) return map(`${path}/holds/${i}/node`, "a hidden node holds nothing")
      for (const [k, item] of h.items_it.entries()) if (words(item) > LABEL_WORDS) return dia(`${path}/holds/${i}/items_it/${k}`, `an item has ${words(item)} words (at most ${LABEL_WORDS})`)
    }
    for (const [i, b] of (eff.badges ?? []).entries()) if (!declared.includes(b.node)) return map(`${path}/badges/${i}/node`, "a badge names a node that does not exist")
  }
  return null
}

// The badge of a node in a state: the state's own badge for it, else the node's.
const badgeOf = (eff, node) => (eff.badges ?? []).find((b) => b.node === node.id)?.badge_it ?? node.badge_it ?? null
const holdsOf = (eff, node) => (eff.holds ?? []).find((h) => h.node === node.id)?.items_it ?? []

function visibleEdges(eff, ctx) {
  const chosen = ctx.controls?.kinds ?? []
  return (eff.edges ?? []).filter((e) => !chosen.length || chosen.includes(e.kind))
}

export const controls = (data) => (data.filter && data.layout === "hub"
  ? [{ id: "kinds", kind: "chips", multi: true, label_it: TEXT.filter_label, hint_it: TEXT.filter_hint, values: [...new Set(allEdges(data).map((e) => e.kind))].map((k) => ({ value: k, label_it: KINDS.kinds[k].label_it })) }]
  : [])

function allEdges(data) {
  return eachState(data).flatMap(({ eff }) => eff.edges ?? [])
}

function build(data, ctx) {
  const select = ctx.mode === "select"
  const eff = effectiveState(data, ctx.state)
  const hidden = new Set(eff.hide ?? [])
  const W = ctx.width
  const f = ctx.fontPx
  const pad = ctx.pad
  const narrow = W < 600 || ctx.forceNarrow
  const all = eachState(data).map((s) => s.eff)
  const base = [...data.nodes, ...(data.everyone ? [{ id: EVERYONE, label_it: TEXT.everyone, icon: "users", role: undefined, note_it: undefined }] : [])]
  const maxBox = narrow ? W - 12 : Math.min(Math.round(W * 0.3), Math.round(f * 12))
  const isz = iconSize(ctx)

  // One size for a node in every state, so that nothing moves when a badge or a list appears.
  const sized = base.map((node) => {
    if (select) return { node, w: Math.min(maxBox, Math.round(f * 7)), h: ctx.lineH * 2 + 2 * pad, parts: null }
    const minH = narrow ? ctx.lineH + 2 * pad : ctx.lineH * 2 + 2 * pad
    const iconW = node.icon ? isz + 6 : 0
    const inner = maxBox - 2 * pad - 4
    const title = measureLabel(ctx, node.label_it, inner, iconW)
    let w = title.w
    let extra = 0
    for (const state of all) {
      const badge = badgeOf(state, node)
      const items = holdsOf(state, node)
      let h = 0
      if (badge) {
        const m = measureLabel(ctx, badge, inner - 2 * pad)
        w = Math.max(w, m.w + 2 * pad)
        h += 6 + m.h + 2 * pad
      }
      for (const item of items) {
        const m = measureLabel(ctx, item, inner - 2 * pad)
        w = Math.max(w, m.w + 2 * pad)
        h += 6 + m.h + 2 * pad
      }
      extra = Math.max(extra, h)
    }
    return { node, w: Math.min(maxBox, w + 2 * pad + 4), h: Math.max(minH, pad + Math.max(title.h, isz) + extra + pad + 2), iconW }
  })
  const order = data.layout === "pair" && data.everyone ? "triangle" : data.layout
  const list = order === "triangle" && data.layout === "pair" ? [sized.find((s) => s.node.id === EVERYONE), ...sized.filter((s) => s.node.id !== EVERYONE)] : sized
  const labelsW = Math.round(f * 14)
  const boxes = place(order, list.map((s) => ({ id: s.node.id, w: s.w, h: s.h })), { width: W, narrow }, { centre: data.centre, into: data.into, gap: labelsW + 40, gapY: narrow ? Math.round(f * 0.8) : Math.round(f * 2.4) })
  let bottom = Math.max(...[...boxes.values()].map((b) => b.y + b.h)) + 6

  const visible = visibleEdges(eff, ctx).filter((e) => !hidden.has(e.from) && !hidden.has(e.to))
  const nodeById = new Map(base.map((n) => [n.id, n]))
  const move = moveList(base, visible.map((e) => ({ from: e.from, to: e.to, label_it: edgeText(e) })))
  const hits = []

  const drawNodes = () => {
    sized.forEach((s, index) => {
      const node = s.node
      if (hidden.has(node.id)) return
      const b = boxes.get(node.id)
      const key = `n:${node.id}`
      shape(ctx, "rect", { x: b.x, y: b.y, w: b.w, h: b.h, r: 12, cls: `dg-node dg-net-node st-${select ? "muted" : node.role ?? "muted"}`, key, ...(select && ctx.targetSet !== "edges" ? { target: `t${index + 1}` } : {}) })
      if (select) return
      let top = b.y + pad
      const tx = b.x + pad + 2 + s.iconW
      if (node.icon) shape(ctx, "icon", { name: node.icon, x: b.x + pad + 2, y: top + 1, size: isz, cls: node.role ? `role-${node.role}` : "", key: `${key}:icon` })
      const title = label(ctx, node.label_it, tx, top, { anchor: "start", maxW: b.w - 2 * pad - 4 - s.iconW, cls: `dg-nodetext dg-net-title${node.role ? ` role-${node.role}` : ""}`, role: node.role, key: `${key}:label` })
      top += Math.max(title.h, isz) + 2
      const badge = badgeOf(eff, node)
      if (badge) {
        const m = measureLabel(ctx, badge, b.w - 4 * pad - 4)
        shape(ctx, "rect", { x: b.x + pad, y: top + 4, w: b.w - 2 * pad, h: m.h + 2 * pad, r: (m.h + 2 * pad) / 2, cls: "dg-net-badgebox", key: `${key}:badge` })
        label(ctx, badge, b.x + b.w / 2, top + 4 + pad, { anchor: "middle", maxW: b.w - 4 * pad - 4, cls: "dg-net-badge", key: `${key}:badgetext` })
        top += 6 + m.h + 2 * pad
      }
      for (const item of holdsOf(eff, node)) {
        const m = measureLabel(ctx, item, b.w - 4 * pad - 4)
        shape(ctx, "rect", { x: b.x + pad, y: top + 4, w: b.w - 2 * pad, h: m.h + 2 * pad, r: 8, cls: "dg-net-item", key: `${key}:item:${item}` })
        label(ctx, item, b.x + pad * 2, top + 4 + pad, { anchor: "start", maxW: b.w - 4 * pad - 4, cls: "dg-net-itemtext", key: `${key}:itemtext:${item}` })
        top += 6 + m.h + 2 * pad
      }
      if (node.note_it) hits.push({ key: `${key}:hit`, id: node.id, x: b.x, y: b.y, w: b.w, h: b.h, name: plain(node.label_it), text: node.note_it, note_it: node.note_it, hint_it: TEXT.note_hint })
    })
  }

  // The arrows with their words on them; false when the words would touch each other or a node (then the numbered form is drawn).
  const drawEdges = (numbered) => {
    if (visible.length === 0) return true
    const routed = route(boxes, visible.map((e, i) => ({ id: `e${i}`, from: e.from, to: e.to, label: numbered || select ? null : "" })), { gap: ctx.lineH + 10 })
    const placed = []
    const nodeRects = [...boxes.entries()].filter(([id]) => !hidden.has(id)).map(([, b]) => b)
    for (const [i, r] of routed.entries()) {
      const e = visible[i]
      const style = KINDS.kinds[e.kind]?.arrow ?? "solid"
      const key = `e:${e.from}>${e.to}:${e.kind}`
      polyline(ctx, r.points, `dg-net-edge dg-net-${style}`, key)
      if (style === "double") polyline(ctx, r.points, "dg-net-double-core", `${key}:core`)
      arrowhead(ctx, r.arrow, "dg-arrowhead dg-net-arrowhead", Math.round(f * 0.7)).key = `${key}:head`
      if (select) {
        if (ctx.targetSet === "edges") ctx.shapes.find((x) => x.key === key).target = `t${i + 1}`
        continue
      }
      const mx = (r.points[0][0] + r.points[1][0]) / 2
      const my = (r.points[0][1] + r.points[1][1]) / 2
      if (numbered) {
        numberPlate(ctx, i + 1, mx, my)
        continue
      }
      const text = edgeText(e)
      const iconName = e.what ? KINDS.what[e.what]?.icon : null
      const iconW = iconName ? isz + 4 : 0
      const m = measureLabel(ctx, text, labelsW)
      const total = m.w + iconW
      const rect = { x: Math.round(mx - total / 2), y: Math.round(my - m.h / 2), w: total, h: m.h }
      if (rect.x < 0 || rect.x + rect.w > W || placed.some((p) => overlaps(p, rect)) || nodeRects.some((n) => overlaps(n, rect))) return false
      placed.push(rect)
      shape(ctx, "rect", { x: rect.x - 5, y: rect.y - 2, w: total + 10, h: m.h + 4, r: 7, cls: "dg-plate-rect", key: `${key}:plate` })
      if (iconName) shape(ctx, "icon", { name: iconName, x: rect.x, y: rect.y + (m.h - isz) / 2, size: isz, cls: "dg-net-what", key: `${key}:what` })
      label(ctx, text, rect.x + iconW, rect.y, { anchor: "start", maxW: m.w, cls: "dg-net-edgelabel", key: `${key}:label` })
    }
    return true
  }

  let numbered = narrow && !select
  const attempt = (asList) => {
    ctx.shapes.length = 0
    ctx.labels.length = 0
    hits.length = 0
    drawNodes()
    // on a phone the nodes stack and no arrow is drawn: the moves are the list under them
    const ok = narrow && !select ? true : drawEdges(asList)
    return ok
  }
  if (!attempt(numbered)) {
    numbered = true
    attempt(true)
  }
  let y = bottom
  if (select) {
    const scene = finish(ctx, bottom, { states: stateCount(data), state: ctx.state, hits: [] })
    return scene
  }
  if (numbered && visible.length) y = drawMoves(ctx, move, bottom + 10, { title: TEXT.moves_title })
  else if (!visible.length && (eff.edges ?? []).length === 0 && !narrow) y = bottom
  const scene = finish(ctx, y, { states: stateCount(data), state: ctx.state, hits, op: eff.op_it ?? null })
  if (scene.error) return scene
  scene.mode = numbered ? "list" : "arrows"
  return scene
}

// A figure whose arrows cannot be told apart at this width (words, then numbers, touch each other) is drawn as on a phone.
function drawn(data, ctx) {
  const scene = build(data, ctx)
  if (scene.error && scene.error.code === "E-DIAGRAM-LAYOUT" && !ctx.forceNarrow && ctx.width >= 600) {
    ctx.shapes.length = 0
    ctx.labels.length = 0
    return build(data, { ...ctx, forceNarrow: true })
  }
  return scene
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build: drawn })

// The description of what is visible in a state (ctx.state, ctx.controls): the nodes, one sentence per arrow, badges and what each node holds.
export function describe(data, ctx = {}) {
  const state = ctx.state ?? 0
  const eff = effectiveState(data, state)
  const hidden = new Set(eff.hide ?? [])
  const nodes = [...data.nodes, ...(data.everyone ? [{ id: EVERYONE, label_it: TEXT.everyone }] : [])].filter((n) => !hidden.has(n.id))
  const parts = [`Relazioni tra ${listIt(nodes.map((n) => plain(short(n.label_it))))}.`]
  const edges = visibleEdges(eff, ctx).filter((e) => !hidden.has(e.from) && !hidden.has(e.to))
  if (edges.length === 0) parts.push(TEXT.no_edges)
  for (const m of moveList(nodes, edges.map((e) => ({ from: e.from, to: e.to, label_it: edgeText(e) })))) parts.push(`${m.text_it}.`)
  for (const n of nodes) {
    const badge = badgeOf(eff, n)
    if (badge) parts.push(`${plain(short(n.label_it))}: ${badge}.`)
    const items = holdsOf(eff, n)
    if (items.length) parts.push(`${plain(short(n.label_it))} ha: ${listIt(items)}.`)
  }
  return parts.join(" ")
}

// Every string a state prints: node labels (hidden ones too, L4), notes, badges, holds, the words of every arrow, the op and the description.
export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const out = []
  for (const n of data.nodes) out.push(n.label_it, n.note_it, badgeOf(eff, n), ...holdsOf(eff, n))
  if (data.everyone) out.push(TEXT.everyone)
  for (const e of eff.edges ?? []) out.push(edgeText(e))
  out.push(eff.op_it)
  out.push(describe(data, { state }))
  return [...new Set(out.filter(Boolean).map(String))]
}

// The select targets in reading order: nodes as declared, arrows as written (top level, or the first state's).
export function targets(data, set) {
  if (set === "nodes") return data.nodes.map((n, i) => ({ key: `n:${n.id}`, bbox: bboxOf(data, `n:${n.id}`, "nodes"), neutral_it: `casella ${i + 1} di ${data.nodes.length}` }))
  if (set === "edges") {
    const edges = effectiveState(data, 0).edges ?? []
    return edges.map((e, i) => ({ key: `e:${e.from}>${e.to}:${e.kind}`, bbox: bboxOf(data, `e:${e.from}>${e.to}:${e.kind}`, "edges"), neutral_it: `freccia ${i + 1} di ${edges.length}` }))
  }
  return []
}

function bboxOf(data, key, set) {
  const scene = layout(withoutRoles(data), { width: 700, fontPx: 20, subject: "math", mode: "select", set })
  const s = scene.shapes?.find((x) => x.key === key)
  if (!s) return null
  if (s.kind === "rect") return { x: s.x, y: s.y, w: s.w, h: s.h }
  if (s.kind === "path") {
    const nums = s.d.match(/-?\d+(\.\d+)?/g).map(Number)
    const xs = nums.filter((_, i) => i % 2 === 0)
    const ys = nums.filter((_, i) => i % 2 === 1)
    return { x: Math.min(...xs) - 6, y: Math.min(...ys) - 6, w: Math.max(...xs) - Math.min(...xs) + 12, h: Math.max(...ys) - Math.min(...ys) + 12 }
  }
  return null
}
