// chain (WAVE2 2.1, T4b): causes, effects and cycles. A line (one path, down the page, or across when it fits), a fan (many causes into
// one event) or a ring (stages that start again). The nodes are written in reading order, so a link goes to the next node or into the
// event; "Togli una causa" greys what is left without a causal path from a present cause and prints a fixed sentence. Fixed positions,
// the same for every state; a state only decides which nodes show (`show`).
import schema from "lesson/diagram_schemas/chain"
import { effectiveState, finish, label, listIt, overlaps, plain, shape, stateCount, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { arrowhead, iconSize, measureLabel, plateLabel, polyline, withoutRoles } from "lesson/diagrams/graph/kit"
import { place, route } from "lesson/diagrams/graph/router"
import { AREAS, DEFAULT_WORD, TEXT } from "lesson/diagrams/graph/texts"

export { schema }
export const type = "chain"
export const states = stateCount

const CAPS = { node_words: 8, not_causal_links: 2, back_links: 1 }

export const wordOf = (data, link) => (link.causal === false ? TEXT.not_causal : link.word ?? DEFAULT_WORD[data.layout])

// The same checks as Lessons::Diagrams::Chain, the first finding only.
export function semantic(data) {
  const map = (path, message) => ({ path, message, code: "E-LESSON-MAP" })
  const dia = (path, message) => ({ path, message, code: "E-LESSON-DIAGRAM" })
  const nodes = data.nodes
  const ids = nodes.map((n) => n.id)
  const layout = data.layout
  if (new Set(ids).size !== ids.length) return map("/nodes", "node ids must be unique")
  for (const [i, n] of nodes.entries()) {
    if (words(n.text_it) > CAPS.node_words) return dia(`/nodes/${i}/text_it`, `a node has ${words(n.text_it)} words (at most ${CAPS.node_words})`)
    if ((n.kind === "stage") !== (layout === "ring")) return dia(`/nodes/${i}/kind`, "a ring has stages only; a line or a fan has none")
  }
  const links = data.links
  const index = new Map(ids.map((id, i) => [id, i]))
  for (const [i, l] of links.entries()) {
    if (!index.has(l.from) || !index.has(l.to)) return map(`/links/${i}`, "the link names a node that does not exist")
    if (l.from === l.to) return map(`/links/${i}`, "a link joins two different nodes")
    if (l.causal === false && l.word) return dia(`/links/${i}/word`, "a link that is not causal carries no word")
  }
  if (links.filter((l) => l.causal === false).length > CAPS.not_causal_links) return dia("/links", `at most ${CAPS.not_causal_links} links are not causal`)
  const backs = links.map((l, i) => (l.back ? i : -1)).filter((i) => i >= 0)
  if (backs.length > CAPS.back_links) return dia("/links", `at most ${CAPS.back_links} link goes back`)
  for (const i of backs) {
    if (layout !== "line") return dia(`/links/${i}/back`, "only a line has a link that goes back")
    if (!(index.get(links[i].from) > index.get(links[i].to))) return map(`/links/${i}`, "a link that goes back runs from a later node to an earlier one")
  }
  const pairs = links.filter((l) => !l.back).map((l) => `${index.get(l.from)}>${index.get(l.to)}`)
  if (new Set(pairs).size !== pairs.length) return map("/links", "the same link is written twice")
  const layoutError = { line: checkLine, fan: checkFan, ring: checkRing }[layout](data, ids, links, index, map, dia)
  if (layoutError) return layoutError
  if (data.remove) {
    if (layout === "ring") return dia("/remove", 'a ring has no "Togli una causa"')
    if (!nodes.some((n) => n.kind === "cause")) return dia("/remove", '"Togli una causa" needs at least one cause')
    for (const [i, n] of nodes.entries()) {
      if (n.kind === "cause" || n.kind === "stage") continue
      if (!links.some((l) => l.to === n.id && l.causal !== false && !l.back)) return map(`/nodes/${i}`, `${n.id} is an ${n.kind} with no cause behind it`)
    }
  }
  for (const [i, s] of (Array.isArray(data.states) ? data.states : []).entries()) {
    for (const [k, id] of (s.show ?? []).entries()) if (!index.has(id)) return map(`/states/${i}/show/${k}`, "show names a node that does not exist")
  }
  return null
}

function checkLine(data, ids, links, index, map, dia) {
  const wanted = ids.slice(1).map((_, i) => `${i}>${i + 1}`).sort()
  const have = links.filter((l) => !l.back).map((l) => `${index.get(l.from)}>${index.get(l.to)}`).sort()
  if (JSON.stringify(have) !== JSON.stringify(wanted)) return map("/links", "a line is one path: each node is linked to the next, in the order the nodes are written")
  if (data.nodes.filter((n) => n.kind === "event").length > 1) return dia("/nodes", "a line has at most one event")
  return null
}

function checkFan(data, ids, links, index, map, dia) {
  const nodes = data.nodes
  const events = nodes.map((n, i) => (n.kind === "event" ? i : -1)).filter((i) => i >= 0)
  if (events.length !== 1) return dia("/nodes", `a fan has exactly one event (here ${events.length})`)
  const e = events[0]
  for (const [i, n] of nodes.entries()) if ((i < e && n.kind !== "cause") || (i > e && n.kind !== "effect")) return dia(`/nodes/${i}/kind`, "in a fan the nodes before the event are causes and the ones after it are effects")
  const into = []
  for (const [i, l] of links.entries()) {
    const from = index.get(l.from)
    const to = index.get(l.to)
    if (to === e) into.push(l)
    else if (to !== from + 1) return map(`/links/${i}`, "in a fan a link goes to the next node or into the event")
  }
  const causal = into.filter((l) => l.causal !== false)
  if (causal.length < 2) return dia("/links", `a fan needs at least 2 causal links into the event (here ${causal.length})`)
  if (new Set(causal.map((l) => l.word ?? DEFAULT_WORD.fan)).size > 1) return dia("/links", "the links into the event use the same word")
  return null
}

function checkRing(data, ids, links, index, map, dia) {
  const wanted = ids.map((_, i) => `${i}>${(i + 1) % ids.length}`).sort()
  const have = links.map((l) => `${index.get(l.from)}>${index.get(l.to)}`).sort()
  if (JSON.stringify(have) !== JSON.stringify(wanted)) return map("/links", "a ring is one cycle through every node, in the order the nodes are written")
  if (links.some((l) => l.causal === false)) return dia("/links", "a ring has only causal links")
  return null
}

// The nodes still alive when the student has taken the causes in `removed` away: a present cause, or a node with a causal link from an alive one.
export function alive(data, removed) {
  const live = new Set(data.nodes.filter((n) => n.kind === "cause" && !removed.includes(n.id)).map((n) => n.id))
  for (let grew = true; grew;) {
    grew = false
    for (const l of data.links) {
      if (l.causal !== false && !l.back && live.has(l.from) && !live.has(l.to) && !removed.includes(l.to)) {
        live.add(l.to)
        grew = true
      }
    }
  }
  return live
}

const removedOf = (data, ctx) => (data.remove ? (ctx.controls?.remove ?? []).filter((id) => data.nodes.some((n) => n.id === id && n.kind === "cause")) : [])

export const controls = (data) => (data.remove
  ? [{ id: "remove", kind: "chips", multi: true, label_it: TEXT.remove_label, hint_it: TEXT.remove_hint, values: data.nodes.filter((n) => n.kind === "cause").map((n) => ({ value: n.id, label_it: plain(n.text_it) })) }]
  : [])

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const select = ctx.mode === "select"
  // a select figure shows every candidate, whatever the state
  const shown = new Set(select ? data.nodes.map((n) => n.id) : eff.show ?? data.nodes.map((n) => n.id))
  const removed = removedOf(data, ctx)
  const live = data.remove ? alive(data, removed) : new Set(data.nodes.map((n) => n.id))
  const W = ctx.width
  const f = ctx.fontPx
  const pad = ctx.pad
  const isz = iconSize(ctx)
  const narrow = W < 600
  const n = data.nodes.length
  const index = new Map(data.nodes.map((nd, i) => [nd.id, i]))
  const eventIdx = data.nodes.findIndex((nd) => nd.kind === "event")
  const fanIn = data.layout === "fan" ? data.links.filter((l) => index.get(l.to) === eventIdx) : []
  const hasTag = Boolean(data.remove)

  function chooseShape(d, width, fontPx, isNarrow, count) {
    if (d.layout === "ring") return { shape: isNarrow ? "column" : "ring" }
    if (d.layout === "fan") return { shape: isNarrow ? "column" : "fan" }
    return { shape: !isNarrow && count <= 4 && width >= 760 ? "row" : "column" }
  }

  function sizeNodes(boxW, withIcon = true) {
    return data.nodes.map((nd) => {
      if (select) return { id: nd.id, w: Math.min(boxW, Math.round(f * 6)), h: ctx.lineH * 2 + 2 * pad }
      const lead = nd.kind === "stage" ? Math.round(f * 1.5) + 6 : nd.area && withIcon ? isz + 6 : 0
      const m = measureLabel(ctx, plain(nd.text_it), boxW - 2 * pad - 6 - lead)
      const h = pad + Math.max(m.h, isz) + (hasTag ? ctx.lineH : 0) + pad + 2
      return { id: nd.id, w: boxW, h: Math.max(h, ctx.lineH * 2 + 2 * pad), lead, textW: m.w }
    })
  }

  function drawNode(nd, box, size, i) {
    if (!shown.has(nd.id)) return
    const isLive = live.has(nd.id)
    const isRemoved = removed.includes(nd.id)
    const state = isRemoved ? "removed" : isLive ? "live" : "grey"
    const key = `n:${nd.id}`
    shape(ctx, "rect", { x: box.x, y: box.y, w: box.w, h: box.h, r: select ? 10 : nd.kind === "stage" || nd.kind === "effect" ? 22 : 10, cls: select ? "dg-node dg-chain-node dg-chain-neutral" : `dg-node dg-chain-node dg-chain-${nd.kind} dg-chain-${state}`, key, ...(select ? { target: `t${i + 1}` } : {}) })
    if (select) return
    if (nd.kind === "stage") {
      const r = Math.round(f * 0.75)
      shape(ctx, "circle", { cx: box.x + pad + 4 + r, cy: box.y + pad + r + 2, r, cls: "dg-numplate" })
      label(ctx, String(i + 1), box.x + pad + 4 + r, box.y + pad + 2 + r - Math.ceil(f * 0.7), { anchor: "middle", cls: "dg-numlabel", key: `${key}:num` })
    } else if (nd.area) shape(ctx, "icon", { name: AREAS[nd.area].icon, x: box.x + pad + 2, y: box.y + pad + 1, size: isz, cls: "dg-chain-area", key: `${key}:icon` })
    label(ctx, plain(nd.text_it), box.x + pad + 3 + size.lead, box.y + pad, { anchor: "start", maxW: box.w - 2 * pad - 6 - size.lead, cls: `dg-nodetext dg-chain-text dg-chain-text-${state}`, key: `${key}:label` })
    if (hasTag && state !== "live") label(ctx, state === "removed" ? TEXT.removed : TEXT.grey_tag, box.x + box.w - pad - 3, box.y + box.h - pad - ctx.lineH, { anchor: "end", cls: "dg-chain-tag", key: `${key}:tag` })
  }

  function linkClass(l) {
    const dead = !live.has(l.from) || !live.has(l.to)
    return `dg-chain-link${l.causal === false ? " dg-chain-notcausal" : ""}${dead ? " dg-chain-dead" : ""}`
  }

  const visibleLink = (l) => shown.has(l.from) && shown.has(l.to)

  function drawWith(p) {
    ctx.shapes.length = 0
    ctx.labels.length = 0
    const out = p.shape === "ring" ? ring() : p.shape === "fan" ? fan() : p.shape === "row" ? row() : column()
    if (out.error) return out
    let y = out.bottom
    y = footer(y)
    return finish(ctx, y, { states: stateCount(data), state: ctx.state, op: eff.op_it ?? null, live: livePhrase() })
  }

  // The fixed sentence after a removal, the areas' key under the figure.
  function footer(y) {
    let top = y + 8
    if (removed.length) {
      const grey = data.nodes.filter((nd) => shown.has(nd.id) && !live.has(nd.id) && !removed.includes(nd.id))
      const sentence = `${grey.length ? `${TEXT.grey_tag[0].toUpperCase()}${TEXT.grey_tag.slice(1)}: ${listIt(grey.map((g) => plain(g.text_it)))}.` : TEXT.nothing_grey} ${TEXT.hypothesis}`
      const probe = ctx.measure(sentence, f, W - 36)
      shape(ctx, "rect", { x: 6, y: top, w: W - 12, h: probe.h + 2 * pad + 4, r: 10, cls: "dg-graph-note", key: "notebox" })
      const note = label(ctx, sentence, 18, top + pad + 2, { anchor: "start", maxW: W - 36, cls: "dg-chain-note", key: "note" })
      top += note.h + 2 * pad + 12
    }
    const areas = [...new Set(data.nodes.filter((nd) => shown.has(nd.id) && nd.area).map((nd) => nd.area))]
    if (areas.length && !select) {
      let x = 6
      let rowTop = top
      for (const a of areas) {
        const m = measureLabel(ctx, AREAS[a].label_it)
        const need = isz + 6 + m.w + 18
        if (x + need > W && x > 6) {
          x = 6
          rowTop += ctx.lineH + 4
        }
        shape(ctx, "icon", { name: AREAS[a].icon, x, y: rowTop + (ctx.lineH - isz) / 2, size: isz, cls: "dg-chain-area", key: `key:${a}:icon` })
        label(ctx, AREAS[a].label_it, x + isz + 6, rowTop, { anchor: "start", cls: "dg-chain-key", key: `key:${a}` })
        x += need
      }
      top = rowTop + ctx.lineH + 4
    }
    return top
  }

  function livePhrase() {
    if (!removed.length) return null
    return `${TEXT.removed_now}: ${listIt(removed.map((r) => plain(data.nodes.find((nd) => nd.id === r).text_it)))}.`
  }

  const wordLabel = (text, cx, cy, key, maxW) => plateLabel(ctx, text, cx, cy, { maxW: maxW ?? Math.round(f * 7), cls: "dg-chain-word", key })

  // ---- a column: one node under another, arrows between neighbours, brackets on the right for what goes back or into the event
  function column() {
    const rails = (data.layout === "fan" ? fanIn.length : 0) + (data.links.some((l) => l.back) || data.layout === "ring" ? 1 : 0)
    const railSpace = rails ? 18 + rails * 10 : 0
    const boxW = Math.min(W - 12 - railSpace, Math.round(f * 20))
    const left = Math.round((W - railSpace - boxW) / 2)
    const sizes = sizeNodes(boxW)
    const gap = ctx.lineH + 18
    const boxes = new Map()
    let y = 6
    sizes.forEach((s) => {
      boxes.set(s.id, { x: left, y, w: s.w, h: s.h })
      y += s.h + gap
    })
    const bottom = y - gap + 6
    data.nodes.forEach((nd, i) => drawNode(nd, boxes.get(nd.id), sizes[i], i))
    if (select) return { bottom }
    // arrows between neighbours
    data.links.forEach((l, k) => {
      const a = boxes.get(l.from)
      const b = boxes.get(l.to)
      if (!visibleLink(l)) return
      const key = `l:${l.from}>${l.to}`
      const ia = index.get(l.from)
      const ib = index.get(l.to)
      if (!l.back && ib === ia + 1 && !(data.layout === "fan" && ib === eventIdx)) {
        const cx = a.x + a.w / 2
        polyline(ctx, [[cx, a.y + a.h + 2], [cx, b.y - 3]], linkClass(l), key)
        arrowhead(ctx, { x: cx, y: b.y - 2, angle: 90 }, "dg-arrowhead dg-chain-head").key = `${key}:head`
        wordLabel(wordOf(data, l), cx + 6 + Math.round(f * 2.2), (a.y + a.h + b.y) / 2, `${key}:word`)
      }
    })
    // fan-in rails, nearest cause innermost
    if (data.layout === "fan") {
      const ev = boxes.get(data.nodes[eventIdx].id)
      const mine = fanIn.filter(visibleLink).sort((p, q) => index.get(q.from) - index.get(p.from))
      mine.forEach((l, k) => {
        const a = boxes.get(l.from)
        const rx = left + boxW + 10 + k * 10
        const ey = ev.y + ((k + 1) * ev.h) / (mine.length + 1)
        polyline(ctx, [[a.x + a.w + 2, a.y + a.h / 2], [rx, a.y + a.h / 2], [rx, ey], [ev.x + ev.w + 2, ey]], linkClass(l), `l:${l.from}>${l.to}`)
        arrowhead(ctx, { x: ev.x + ev.w + 2, y: ey, angle: 180 }, "dg-arrowhead dg-chain-head").key = `l:${l.from}>${l.to}:head`
      })
      if (mine.length) {
        // the word of the fan-in, once, at the right edge above the event
        const text = wordOf(data, mine[0])
        const m = measureLabel(ctx, text, undefined, 0, "dg-plate dg-chain-word")
        const word = wordLabel(text, W - 6 - m.w / 2, ev.y - ctx.lineH * 0.7, "fanword", m.w + 2)
        // the word is bold: its box is the bold width, ending at the right margin (the regular width left the end of the word outside the figure)
        word.w = m.w + 2
        word.x = Math.max(0, W - 6 - word.w)
      }
    }
    // a closing link of a ring, or a link that goes back: a bracket on the right
    const closing = data.layout === "ring" ? [data.links.find((l) => index.get(l.from) === n - 1)] : data.links.filter((l) => l.back)
    for (const l of closing.filter((x) => x && visibleLink(x))) {
      const a = boxes.get(l.from)
      const b = boxes.get(l.to)
      const rx = left + boxW + 14
      polyline(ctx, [[a.x + a.w + 2, a.y + a.h / 2], [rx, a.y + a.h / 2], [rx, b.y + b.h / 2], [b.x + b.w + 2, b.y + b.h / 2]], linkClass(l), `l:${l.from}>${l.to}`)
      arrowhead(ctx, { x: b.x + b.w + 2, y: b.y + b.h / 2, angle: 180 }, "dg-arrowhead dg-chain-head").key = `l:${l.from}>${l.to}:head`
      // the words fit beside the bracket on a wide page; on a phone the bracket is the picture and the description says the rest
      const hx = rx + 8
      const m = measureLabel(ctx, TEXT.return_label)
      if (hx + m.w + 4 <= W) label(ctx, TEXT.return_label, hx, (a.y + b.y + a.h) / 2 - ctx.lineH / 2, { anchor: "start", cls: "dg-chain-word dg-plate", key: `l:${l.from}>${l.to}:word` })
    }
    return { bottom }
  }

  // ---- a row: a short line across the page
  function row() {
    const gapX = Math.round(f * 6)
    const boxW = Math.floor((W - 12 - gapX * (n - 1)) / n)
    if (boxW < f * 7) return column()
    const sizes = sizeNodes(boxW)
    const boxes = place("row", sizes, { width: W }, { gap: gapX })
    return flat(sizes, boxes)
  }

  function ring() {
    const boxW = Math.min(Math.round(W * 0.26), Math.round(f * 10))
    const sizes = sizeNodes(boxW)
    const boxes = place("ring", sizes, { width: W }, {})
    return flat(sizes, boxes)
  }

  // arrows straight between boxes, the word on each
  function flat(sizes, boxes) {
    data.nodes.forEach((nd, i) => drawNode(nd, boxes.get(nd.id), sizes[i], i))
    const bottom = Math.max(...[...boxes.values()].map((b) => b.y + b.h)) + 8
    if (select) return { bottom }
    const links = data.links.filter(visibleLink)
    const routed = route(boxes, links.map((l, k) => ({ id: `r${k}`, from: l.from, to: l.to, back: l.back, label: "" })), { gap: ctx.lineH + 10 })
    const placed = []
    routed.forEach((r, k) => {
      const l = links[k]
      const key = `l:${l.from}>${l.to}`
      polyline(ctx, r.points, linkClass(l), key)
      arrowhead(ctx, r.arrow, "dg-arrowhead dg-chain-head").key = `${key}:head`
      const text = l.back ? TEXT.return_label : wordOf(data, l)
      const m = measureLabel(ctx, text, Math.round(f * 7))
      // beside an upright arrow, on a plate over a slanted one
      const upright = Math.abs(Math.abs(r.arrow.angle) - 90) < 12
      const at = { x: r.label.x + (upright ? m.w / 2 + 12 : 0), y: r.label.y }
      const rect = { x: Math.round(at.x - m.w / 2), y: Math.round(at.y - m.h / 2), w: m.w, h: m.h }
      if (rect.x < 0 || rect.x + rect.w > W || placed.some((q) => overlaps(q, rect)) || [...boxes.values()].some((b) => overlaps(b, rect))) placed.push(null)
      else {
        placed.push(rect)
        plateLabel(ctx, text, at.x, at.y, { maxW: Math.round(f * 7), cls: "dg-chain-word", key: `${key}:word` })
      }
    })
    if (placed.includes(null)) return { error: { path: "", message: "the words of the links do not fit this width", code: "E-DIAGRAM-LAYOUT" } }
    return { bottom }
  }

  function fan() {
    const boxW = Math.min(Math.round((W - 12 - Math.round(f * 7)) / 2), Math.round(f * 14))
    const sizes = sizeNodes(boxW)
    const boxes = place("fan", sizes.slice(0, eventIdx + 1), { width: W }, { into: sizes[eventIdx].id, gapY: ctx.lineH + 20 })
    const ev = boxes.get(sizes[eventIdx].id)
    let y = ev.y + ev.h + ctx.lineH + 18
    for (const s of sizes.slice(eventIdx + 1)) {
      boxes.set(s.id, { x: ev.x, y, w: s.w, h: s.h })
      y += s.h + ctx.lineH + 18
    }
    return flat(sizes, boxes)
  }

  const plan = chooseShape(data, W, f, narrow, n)
  const result = drawWith(plan)
  if (result.error && plan.shape !== "column") return drawWith({ ...plan, shape: "column" })
  return result
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// The description of the visible state (ctx.state, ctx.controls.remove).
export function describe(data, ctx = {}) {
  const state = ctx.state ?? 0
  const eff = effectiveState(data, state)
  const shown = new Set(eff.show ?? data.nodes.map((n) => n.id))
  const nodes = data.nodes.filter((n) => shown.has(n.id))
  const by = new Map(data.nodes.map((n) => [n.id, n]))
  const parts = [{ line: "Una catena di cause.", fan: "Tante cause per un fatto solo.", ring: "Un giro che ricomincia." }[data.layout]]
  let any = false
  for (const l of data.links) {
    if (!shown.has(l.from) || !shown.has(l.to)) continue
    any = true
    const from = plain(by.get(l.from).text_it)
    const to = plain(by.get(l.to).text_it)
    const word = wordOf(data, l)
    parts.push(l.causal === false ? `${from}: ${word}, non è una causa di ${to}.` : word === "perché" ? `${to} perché ${from}.` : l.back ? `Poi si torna indietro: ${from} ${word} ${to}.` : `${from} ${word} ${to}.`)
  }
  if (nodes.length === 1 || !any) parts.push(`${listIt(nodes.map((n) => plain(n.text_it)))}.`)
  const removed = removedOf(data, ctx)
  if (data.remove && removed.length) {
    const live = alive(data, removed)
    const grey = nodes.filter((n) => !live.has(n.id) && !removed.includes(n.id))
    parts.push(`${TEXT.removed_now}: ${listIt(removed.map((r) => plain(by.get(r).text_it)))}.`)
    parts.push(grey.length ? `${TEXT.grey_tag[0].toUpperCase()}${TEXT.grey_tag.slice(1)}: ${listIt(grey.map((n) => plain(n.text_it)))}.` : TEXT.nothing_grey)
    parts.push(TEXT.hypothesis)
  }
  return parts.join(" ")
}

export function printed(data, state = 0) {
  const out = data.nodes.map((n) => n.text_it)
  for (const l of data.links) out.push(wordOf(data, l))
  out.push(effectiveState(data, state).op_it)
  if (data.remove) out.push(TEXT.hypothesis, TEXT.nothing_grey, TEXT.grey_tag, TEXT.removed)
  out.push(describe(data, { state }))
  return [...new Set(out.filter(Boolean).map(String))]
}

export function targets(data, set) {
  if (set !== "nodes") return []
  const scene = layout(withoutRoles(data), { width: 700, fontPx: 20, subject: "math", mode: "select" })
  return data.nodes.map((n, i) => {
    const s = scene.shapes?.find((x) => x.key === `n:${n.id}`)
    return { key: `n:${n.id}`, bbox: s ? { x: s.x, y: s.y, w: s.w, h: s.h } : null, neutral_it: `casella ${i + 1} di ${data.nodes.length}` }
  })
}
