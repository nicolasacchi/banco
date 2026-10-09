// sentence (A7): logical and grammatical analysis. `line`: the sentence in reading order, each part with
// its role colour, icon and label under it. `centre`: the predicate in the middle, the parts before it on
// its left and the parts after it on its right (stacked under it on a narrow screen), joined by lines.
// Parts that keep their id between states move (draw.js animates them); tapping a part shows its question.
import palette from "lesson/palette"
import { effectiveState, finish, label, listIt, plain, roleInfo, shape, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const states = stateCount

function checkParts(parts, base, text) {
  const ids = new Set()
  let pos = 0
  const taken = []
  for (let i = 0; i < parts.length; i++) {
    const p = parts[i]
    if (p.id) {
      if (ids.has(p.id)) return { path: `${base}/${i}/id`, message: "part ids are unique" }
      ids.add(p.id)
    }
    if (p.implied) continue
    const occurrences = []
    for (let at = text.indexOf(p.text_it); at >= 0; at = text.indexOf(p.text_it, at + 1)) occurrences.push(at)
    if (occurrences.length === 0) return { path: `${base}/${i}/text_it`, message: "a part is a piece of the sentence" }
    const ok = occurrences.find((at) => at >= pos)
    if (ok === undefined) {
      const clash = occurrences.some((at) => taken.some(([a, z]) => at < z && a < at + p.text_it.length))
      return clash ? { path: `${base}/${i}`, message: "parts do not overlap" } : { path: base, message: "parts follow the order of the sentence" }
    }
    taken.push([ok, ok + p.text_it.length])
    pos = ok + p.text_it.length
  }
  return null
}

export function semantic(data) {
  const n = stateCount(data)
  const seenRole = new Map()
  let roleError = null
  for (let j = 0; j < n; j++) {
    const e = effectiveState(data, j)
    const base = data.states ? (data.parts && !data.states[j].parts ? "/parts" : `/states/${j}/parts`) : "/parts"
    const bad = checkParts(e.parts, base, e.text_it)
    if (bad) return bad
    const ids = new Set(e.parts.map((p) => p.id).filter(Boolean))
    for (let k = 0; k < (e.links ?? []).length; k++) {
      const l = e.links[k]
      for (const end of ["from", "to"]) if (!ids.has(l[end])) return { path: `${data.states?.[j]?.links ? `/states/${j}` : ""}/links/${k}/${end}`, message: "a link joins two parts that have an id" }
    }
    e.parts.forEach((p, k) => {
      if (!p.id) return
      if (seenRole.has(p.id) && seenRole.get(p.id) !== p.role) roleError ??= { path: `/states/${j}/parts/${k}/role`, message: "a part keeps its role across states" }
      seenRole.set(p.id, p.role)
    })
  }
  return roleError
}

function info(ctx, role) {
  return roleInfo(palette, ctx.subject, role) ?? { label_it: role }
}

// One node: icon, text, and the role label under it.
function measureNode(ctx, p, maxW) {
  const f = ctx.fontPx
  const r = info(ctx, p.role)
  const iconW = r.icon ? Math.round(f * 1.1) + 4 : 0
  const text = ctx.measure(p.text_it, f, maxW ? maxW - iconW : undefined)
  const labelText = p.label_it ?? r.label_it
  const lab = ctx.measure(labelText, f, maxW)
  return { r, iconW, text, lab, labelText, w: Math.ceil(Math.max(text.w + iconW, lab.w)), th: text.h, lh: lab.h }
}

function drawNode(ctx, p, i, x, y, w, nd, hits, boxed) {
  const f = ctx.fontPx
  const key = `part:${p.id ?? `p${i}`}`
  const cx = x + w / 2
  const tx = nd.text.w + nd.iconW
  const startX = cx - tx / 2
  if (boxed) shape(ctx, "rect", { x, y, w, h: nd.th + nd.lh + 2 * ctx.pad + 6, r: 12, cls: `dg-node st-${p.role}${p.implied ? " dg-implied" : ""}`, key: `${key}:box` })
  const ty = y + (boxed ? ctx.pad : 0)
  if (nd.r.icon) shape(ctx, "icon", { name: nd.r.icon, x: startX, y: ty + (nd.th > ctx.lineH ? 2 : Math.round((nd.th - f * 1.1) / 2)), size: Math.round(f * 1.1), cls: `role-${p.role}`, key: `${key}:icon` })
  label(ctx, p.text_it, startX + nd.iconW, ty, { anchor: "start", maxW: nd.text.h > ctx.lineH ? nd.text.w : undefined, cls: `role-${p.role} dg-parttext${p.implied ? " dg-implied-text" : ""}`, role: p.role, key: `${key}:text` })
  const barY = ty + nd.th + 1
  if (!boxed) shape(ctx, "line", { x1: x + 2, y1: barY + 2, x2: x + w - 2, y2: barY + 2, cls: `dg-bar st-${p.role}${p.implied ? " dg-implied" : ""}`, key: `${key}:bar` })
  const lab = label(ctx, nd.labelText, cx, barY + 6, { maxW: w, cls: `role-${p.role} dg-partlabel`, role: p.role, key: `${key}:label` })
  hits.push({ key, id: p.id ?? `p${i}`, x, y, w, h: barY + 6 + lab.h - y, role: p.role, name: nd.r.label_it, text: p.text_it, question_it: p.question_it ?? null })
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const W = ctx.width
  const m = 8
  const parts = eff.parts
  const hits = []
  const centre = data.layout === "centre" && W >= 300
  let height
  if (centre) height = centreLayout(ctx, parts, hits, W, m)
  if (height === undefined || height === null) height = lineLayout(ctx, parts, eff.links ?? [], hits, W, m)
  if (height.error) return height
  const scene = finish(ctx, height, { states: stateCount(data), state: ctx.state, hits, nextLabel: eff.next_label_it ?? null, op: eff.op_it ?? null })
  return scene
}

function lineLayout(ctx, parts, links, hits, W, m) {
  ctx.shapes.length = 0
  ctx.labels.length = 0
  hits.length = 0
  const gap = 12
  const nodes = parts.map((p) => measureNode(ctx, p, W - 2 * m))
  // rows
  const rows = [[]]
  let x = m
  nodes.forEach((nd, i) => {
    const w = Math.min(nd.w + 6, W - 2 * m)
    if (x + w > W - m && rows[rows.length - 1].length > 0) {
      rows.push([])
      x = m
    }
    rows[rows.length - 1].push({ i, x, w })
    x += w + gap
  })
  const rowH = (row) => Math.max(...row.map(({ i }) => nodes[i].th + nodes[i].lh + 12))
  const linkRows = links.length ? ctx.lineH + 34 : 0
  let y = 6 + linkRows
  const where = new Map()
  rows.forEach((row) => {
    // centre the row
    const used = row[row.length - 1].x + row[row.length - 1].w - row[0].x
    const shift = Math.max(0, Math.round((W - 2 * m - used) / 2))
    for (const cell of row) {
      cell.x += shift
      const nd = nodes[cell.i]
      drawNode(ctx, parts[cell.i], cell.i, cell.x, y, cell.w, nd, hits, false)
      where.set(parts[cell.i].id, { cell, y, row })
    }
    y += rowH(row) + 10
  })
  // links as arcs above the sentence, when both ends are on the first row; otherwise listed under it
  const firstRow = rows[0]
  const extra = []
  links.forEach((l, k) => {
    const a = where.get(l.from)
    const b = where.get(l.to)
    if (a && b && firstRow.includes(a.cell) && firstRow.includes(b.cell)) {
      const xa = a.cell.x + a.cell.w / 2
      const xb = b.cell.x + b.cell.w / 2
      const top = 6 + linkRows - 6
      const lift = 18 + k * 8
      shape(ctx, "path", { d: `M${xa},${top} Q${(xa + xb) / 2},${top - lift * 1.6} ${xb},${top}`, cls: "dg-link", key: `link:${k}` })
      if (l.label_it) label(ctx, l.label_it, (xa + xb) / 2, top - lift * 0.8 - ctx.lineH, { cls: "dg-note" })
    } else extra.push(l)
  })
  for (const l of extra) {
    const lbl = `${parts.find((p) => p.id === l.from)?.text_it} → ${parts.find((p) => p.id === l.to)?.text_it}${l.label_it ? `: ${l.label_it}` : ""}`
    const t = label(ctx, lbl, m, y, { anchor: "start", maxW: W - 2 * m, cls: "dg-note" })
    y += t.h + 4
  }
  return y + 2
}

function centreLayout(ctx, parts, hits, W, m) {
  const f = ctx.fontPx
  const gapX = Math.round(f * 1.6)
  const center = Math.max(0, parts.findIndex((p) => p.role === "predicate"))
  const nodes = parts.map((p) => measureNode(ctx, p, Math.min(Math.round(W * 0.42), 240)))
  const boxW = (nd) => nd.w + 2 * ctx.pad + 8
  const boxH = (nd) => nd.th + nd.lh + 2 * ctx.pad + 6
  const left = parts.map((_, i) => i).filter((i) => i < center)
  const right = parts.map((_, i) => i).filter((i) => i > center)
  const cw = boxW(nodes[center])
  const lw = left.length ? Math.max(...left.map((i) => boxW(nodes[i]))) : 0
  const rw = right.length ? Math.max(...right.map((i) => boxW(nodes[i]))) : 0
  const wide = lw + cw + rw + gapX * (left.length ? 1 : 0) + gapX * (right.length ? 1 : 0) <= W - 2 * m
  if (wide) {
    const total = lw + cw + rw + gapX * ((left.length ? 1 : 0) + (right.length ? 1 : 0))
    const x0 = Math.round((W - total) / 2)
    const cx0 = x0 + lw + (left.length ? gapX : 0)
    const colH = (list) => list.reduce((s, i) => s + boxH(nodes[i]) + 14, -14)
    const height = Math.max(colH(left), colH(right), boxH(nodes[center])) + 12
    const place = (list, colX, colW, side) => {
      let y = 6 + (height - 12 - colH(list)) / 2
      for (const i of list) {
        const nd = nodes[i]
        const w = boxW(nd)
        const x = side === "l" ? colX + colW - w : colX
        drawNode(ctx, parts[i], i, x, y, w, nd, hits, true)
        const cyNode = y + boxH(nd) / 2
        const cyC = 6 + (height - 12 - boxH(nodes[center])) / 2 + boxH(nodes[center]) / 2
        shape(ctx, "line", { x1: side === "l" ? x + w : x, y1: cyNode, x2: side === "l" ? cx0 : cx0 + cw, y2: cyC, cls: "dg-connector dg-thick", key: `edge:${parts[i].id ?? i}` })
        y += boxH(nd) + 14
      }
    }
    place(left, x0, lw, "l")
    place(right, cx0 + cw + gapX, rw, "r")
    drawNode(ctx, parts[center], center, cx0, 6 + (height - 12 - boxH(nodes[center])) / 2, cw, nodes[center], hits, true)
    return height
  }
  // stacked: the predicate first, the others under it in reading order, joined by a trunk
  const maxBox = W - 2 * m - 28
  const nds = parts.map((p) => measureNode(ctx, p, maxBox - 2 * ctx.pad - 8))
  const bw = (nd) => Math.min(maxBox, nd.w + 2 * ctx.pad + 8)
  let y = 6
  const pc = nds[center]
  drawNode(ctx, parts[center], center, m, y, bw(pc), pc, hits, true)
  const trunkTop = y + boxH(pc)
  y = trunkTop + 14
  let last = trunkTop
  parts.forEach((p, i) => {
    if (i === center) return
    const nd = nds[i]
    const w = bw(nd)
    drawNode(ctx, p, i, m + 28, y, w, nd, hits, true)
    shape(ctx, "line", { x1: m + 14, y1: y + boxH(nd) / 2, x2: m + 28, y2: y + boxH(nd) / 2, cls: "dg-connector dg-thick", key: `edge:${p.id ?? i}` })
    last = y + boxH(nd) / 2
    y += boxH(nd) + 14
  })
  shape(ctx, "line", { x1: m + 14, y1: trunkTop, x2: m + 14, y2: last, cls: "dg-connector dg-thick", key: "trunk" })
  return y - 6
}

export function describe(data) {
  const n = stateCount(data)
  const out = []
  for (let i = 0; i < n; i++) {
    const e = effectiveState(data, i)
    const parts = e.parts.map((p) => {
      const r = palette.subjects.italian[p.role] ?? palette.common[p.role]
      return `«${plain(p.text_it)}» è ${p.implied ? "sottinteso: " : ""}${r?.label_it ?? p.role}${p.question_it ? ` (${plain(p.question_it)})` : ""}`
    })
    out.push(`${n > 1 ? `Passo ${i + 1}${e.op_it ? ` (${plain(e.op_it)})` : ""}. ` : ""}La frase «${plain(e.text_it)}» si divide così: ${listIt(parts)}.`)
  }
  return out.join(" ")
}

export const layout = (data, opts) => run(data, opts, { semantic, build })
