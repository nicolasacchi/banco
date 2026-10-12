// flow, layout line (WAVE2 2.1, T4b): a journey. The stations of the main lane in the order they are written, one second lane that
// leaves a station and joins a later one, at most three returns drawn as arcs, and a large token that jumps from station to station
// as the states go on. It is the law designer's `route`. The edges are the order of the stations, none is written; the returns never
// make the edge graph cyclic. Horizontal from 700 px when every station's longest word fits its slot, else vertical (a phone).
import { effectiveState, label, listIt, plain, shape, words, finish, stateCount } from "lesson/diagrams/common"
import { arrowhead, drawMoves, iconSize, measureLabel, plateLabel, polyline, withoutRoles } from "lesson/diagrams/graph/kit"
import { place, route } from "lesson/diagrams/graph/router"
import { TEXT } from "lesson/diagrams/graph/texts"

const CAPS = { stations: 8, branch_stations: 4, returns: 3, station_words: 4, actor_words: 8, label_words: 6 }

const laneOf = (data) => {
  const lanes = new Map()
  data.nodes.forEach((n, i) => lanes.set(n.id, [0, i]))
  ;(data.branch?.nodes ?? []).forEach((n, i) => lanes.set(n.id, [1, i]))
  return lanes
}

// The edges of a line as [from, to] pairs, in the order Ruby lists them.
export function lineEdges(data) {
  const pairs = data.nodes.slice(1).map((n, i) => [data.nodes[i].id, n.id])
  if (data.branch) {
    const chain = [data.branch.from, ...data.branch.nodes.map((n) => n.id), data.branch.to]
    chain.slice(1).forEach((id, i) => pairs.push([chain[i], id]))
  }
  return pairs
}

// The checks of Lessons::Diagrams::Flow for a line, the first finding only.
export function semanticLine(data) {
  const map = (path, message) => ({ path, message, code: "E-LESSON-MAP" })
  const dia = (path, message) => ({ path, message, code: "E-LESSON-DIAGRAM" })
  if ("edges" in data) return dia("/edges", "a line has no edges: the order of the stations is the order they are written")
  if (data.walk || data.case_it) return dia("/walk", "walk is for the tree layout only")
  const main = data.nodes
  const extra = data.branch?.nodes ?? []
  const ids = [...main, ...extra].map((n) => n.id)
  if (new Set(ids).size !== ids.length) return map("/nodes", "node ids must be unique")
  if (main.length > CAPS.stations) return dia("/nodes", `a line has at most ${CAPS.stations} stations (here ${main.length})`)
  for (const [base, list] of [["/nodes", main], ["/branch/nodes", extra]]) {
    for (const [i, n] of list.entries()) {
      if (n.kind === "decision") return dia(`${base}/${i}/kind`, "a station is a step or an end")
      if (words(n.text_it) > CAPS.station_words) return dia(`${base}/${i}/text_it`, `a station label has ${words(n.text_it)} words (at most ${CAPS.station_words})`)
      if (n.actor_it && words(n.actor_it) > CAPS.actor_words) return dia(`${base}/${i}/actor_it`, `an actor has ${words(n.actor_it)} words (at most ${CAPS.actor_words})`)
    }
  }
  const lanes = laneOf(data)
  if (data.branch) {
    const from = lanes.get(data.branch.from)
    const to = lanes.get(data.branch.to)
    if (!from || !to || from[0] !== 0 || to[0] !== 0) return map("/branch", "the second lane leaves and joins stations of the main lane")
    if (from[1] >= to[1]) return map("/branch", "the second lane runs forward: it leaves a station before the one it joins")
    if (data.branch.label_it && words(data.branch.label_it) > CAPS.label_words) return dia("/branch/label_it", `a label has ${words(data.branch.label_it)} words (at most ${CAPS.label_words})`)
  }
  const returns = data.returns ?? []
  if (returns.length > CAPS.returns) return dia("/returns", `a line has at most ${CAPS.returns} returns (here ${returns.length})`)
  for (const [i, r] of returns.entries()) {
    const a = lanes.get(r.from)
    const b = lanes.get(r.to)
    if (!a || !b) return map(`/returns/${i}`, "a return names a station that does not exist")
    if (a[0] !== b[0] || a[1] <= b[1]) return map(`/returns/${i}`, "a return goes backwards along its own lane")
    if (r.label_it && words(r.label_it) > CAPS.label_words) return dia(`/returns/${i}/label_it`, `a label has ${words(r.label_it)} words (at most ${CAPS.label_words})`)
  }
  if (data.token && !lanes.has(data.token)) return map("/token", "the token is not a station")
  const drawn = [...lineEdges(data), ...returns.map((r) => [r.from, r.to])].map((p) => p.join(">"))
  let previous = data.token
  for (const [i, s] of (data.states ?? []).entries()) {
    const at = `/states/${i}`
    if (s.token && !lanes.has(s.token)) return map(`${at}/token`, "the token is not a station")
    const token = s.token ?? previous
    if (s.via) {
      const unknown = s.via.findIndex((id) => !lanes.has(id))
      if (unknown >= 0) return map(`${at}/via/${unknown}`, "via names a station that does not exist")
      if (previous && s.via[0] !== previous) return map(`${at}/via`, `via starts where the token was (${previous})`)
      if (token && s.via[s.via.length - 1] !== token) return map(`${at}/via`, `via ends where the token is now (${token})`)
      const bad = s.via.slice(1).findIndex((id, k) => !drawn.includes(`${s.via[k]}>${id}`))
      if (bad >= 0) return map(`${at}/via`, `via goes from ${s.via[bad]} to ${s.via[bad + 1]}, which no drawn edge or return joins`)
    }
    previous = token
  }
  return null
}

const cap = (t) => `${t.charAt(0).toUpperCase()}${t.slice(1)}`
const byId = (data) => new Map([...data.nodes, ...(data.branch?.nodes ?? [])].map((n) => [n.id, n]))

export function buildLine(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const token = eff.token ?? data.token ?? null
  const select = ctx.mode === "select"
  const W = ctx.width
  const f = ctx.fontPx
  const R = Math.round(f * 1.1)
  const isz = Math.round(R * 1.15)
  const nodes = byId(data)
  const main = data.nodes
  const lane = data.branch?.nodes ?? []
  const returns = data.returns ?? []
  const index = new Map([...main, ...lane].map((n, i) => [n.id, i]))
  const tokenPos = token ? main.findIndex((n) => n.id === token) : -1

  // horizontal when the longest word of every label fits its slot
  const slot = Math.floor((W - 12) / main.length)
  const longest = Math.max(...[...main, ...lane].flatMap((n) => plain(n.text_it).split(/\s+/).map((wd) => ctx.measure(wd, f).w)))
  const horizontal = W >= 700 && longest + 8 <= slot && (lane.length === 0 || longest + 8 <= (slot * 2) / 2)
  const out = horizontal ? horizontalLine() : verticalLine()
  if (out.error) return out
  let y = out.bottom
  const here = token ? nodes.get(token) : null
  if (here && !select) {
    const sentence = `${TEXT.path_here} ${plain(here.text_it)}.${here.actor_it ? ` ${cap(plain(here.actor_it))}.` : ""}`
    const probe = ctx.measure(sentence, f, W - 36)
    shape(ctx, "rect", { x: 6, y: y + 6, w: W - 12, h: probe.h + 2 * ctx.pad + 4, r: 10, cls: "dg-graph-note", key: "herebox" })
    const note = label(ctx, sentence, 18, y + 6 + ctx.pad + 2, { anchor: "start", maxW: W - 36, cls: "dg-flow-here", key: "here" })
    y += note.h + 2 * ctx.pad + 16
  }
  return finish(ctx, y, { states: stateCount(data), state: ctx.state, op: eff.op_it ?? null, live: here ? `${TEXT.path_here} ${plain(here.text_it)}.` : null, liveVisible: false })

  // a station: a circle with its icon, the token ring round the one the token is on
  function station(n, cx, cy, i) {
    const here = !select && n.id === token
    const key = `s:${n.id}`
    shape(ctx, "circle", { cx, cy, r: R, cls: `dg-flow-station st-${select ? "muted" : n.role ?? "muted"}${here ? " dg-flow-here-station" : ""}`, key, ...(select ? { target: `t${i + 1}` } : {}) })
    if (select) return
    if (n.icon) shape(ctx, "icon", { name: n.icon, x: cx - isz / 2, y: cy - isz / 2, size: isz, cls: `${n.role ? `role-${n.role}` : ""}${here ? " dg-flow-token-icon" : ""}`, key: `${key}:icon` })
    else shape(ctx, "circle", { cx, cy, r: Math.round(R * 0.32), cls: `dg-flow-dot${here ? " dg-flow-token-icon" : ""}`, key: `${key}:dot` })
  }

  function tokenRing(cx, cy) {
    shape(ctx, "circle", { cx, cy, r: R + 8, cls: "dg-flow-token", key: "token" })
  }

  function horizontalLine() {
    const labelMax = slot - 8
    const blocks = [...main, ...lane].map((n) => {
      const m = measureLabel(ctx, plain(n.text_it), labelMax)
      return { id: n.id, w: Math.min(slot - 4, Math.max(m.w, 2 * R)), h: 2 * R + 8 + m.h, m, lane: lane.includes(n) ? 1 : 0 }
    })
    // the arcs of the returns need room above the line: measured first, with the stations at the top
    const top = returns.length ? Math.round(f * 2 + 70) : 8
    const boxes = place("line", blocks, { width: W }, { branch: data.branch ? { from: data.branch.from, to: data.branch.to } : undefined, gapY: Math.round(f * 1.6) })
    const shift = (b) => ({ x: b.x, y: b.y + top, w: b.w, h: b.h })
    const sh = new Map([...boxes].map(([id, b]) => [id, shift(b)]))
    const centres = new Map([...sh].map(([id, b]) => [id, [b.x + b.w / 2, b.y + R]]))
    const dots = new Map([...centres].map(([id, [cx, cy]]) => [id, { x: cx - R, y: cy - R, w: 2 * R, h: 2 * R }]))
    // the line behind the stations: done in the primary colour up to the token, the rest quiet
    main.slice(1).forEach((n, i) => {
      const a = main[i].id
      const [ax, ay] = centres.get(a)
      const [bx, by] = centres.get(n.id)
      polyline(ctx, [[ax, ay], [bx, by]], `dg-flow-line${tokenPos >= 0 && index.get(n.id) <= tokenPos ? " dg-flow-done" : ""}`, `seg:${a}>${n.id}`)
    })
    // the second lane leaves the line just after its first station and rejoins just before its last: one road
    if (lane.length) {
      const [fx, fy] = centres.get(data.branch.from)
      const [tx] = centres.get(data.branch.to)
      const laneY = centres.get(lane[0].id)[1]
      const x0 = fx + slot * 0.4
      const x1 = tx - slot * 0.4
      polyline(ctx, [[x0, fy], [x0, laneY], [x1, laneY], [x1, fy]], "dg-flow-line", "lane")
    }
    ;[...main, ...lane].forEach((n, i) => {
      const [cx, cy] = centres.get(n.id)
      station(n, cx, cy, i)
      if (!select) {
        const b = sh.get(n.id)
        label(ctx, plain(n.text_it), b.x + b.w / 2, b.y + 2 * R + 8, { anchor: "middle", maxW: blocks.find((q) => q.id === n.id).m.h > ctx.lineH ? blocks.find((q) => q.id === n.id).m.w : undefined, cls: "dg-flow-label", key: `s:${n.id}:label` })
      }
    })
    if (token && !select && centres.has(token)) tokenRing(...centres.get(token))
    if (data.branch?.label_it && !select) {
      const f0 = centres.get(data.branch.from)
      const lanePlace = lane.length ? sh.get(lane[0].id) : null
      if (lanePlace) plateLabel(ctx, data.branch.label_it, (f0[0] + centres.get(data.branch.to)[0]) / 2, lanePlace.y - ctx.lineH * 0.9, { maxW: Math.round(f * 12), cls: "dg-flow-branchlabel", key: "branchlabel" })
    }
    if (!select) {
      const routed = route(dots, returns.map((r, k) => ({ id: `r${k}`, from: r.from, to: r.to, back: true, label: r.label_it ?? "" })), {})
      const placed = []
      for (const [k, r] of routed.entries()) {
        polyline(ctx, r.points, "dg-flow-return", `ret:${returns[k].from}>${returns[k].to}`)
        arrowhead(ctx, r.arrow, "dg-arrowhead dg-flow-head", Math.round(f * 0.7)).key = `ret:${returns[k].from}>${returns[k].to}:head`
        const text = returns[k].label_it ?? TEXT.return_label
        const m = measureLabel(ctx, text, Math.round(f * 11))
        placed.push(plateLabel(ctx, text, r.label.x, r.label.y - 4, { maxW: Math.round(f * 11), cls: "dg-flow-returnlabel", key: `ret:${returns[k].from}>${returns[k].to}:label` }))
        void m
      }
    }
    const bottom = Math.max(...[...sh.values()].map((b) => b.y + b.h)) + 6
    return { bottom }
  }

  function verticalLine() {
    const lineX = 6 + R + 6
    const textX = lineX + R + 14
    const textW = W - textX - 6
    let yy = 8
    const centres = new Map()
    const placeStations = (list, x, tx) => list.map((n) => {
      const m = measureLabel(ctx, plain(n.text_it), W - tx - 6)
      const a = n.actor_it && !select ? ctx.measure(plain(n.actor_it), f, W - tx - 6) : { h: 0 }
      const h = Math.max(2 * R, m.h + (a.h ? a.h + 2 : 0))
      const cy = yy + Math.max(R, m.h / 2)
      const row = { n, y: yy, h, m, a, cy, cx: x, tx }
      centres.set(n.id, [x, cy])
      yy += h + Math.round(f * 1.1)
      return row
    })
    const rowsMain = placeStations(main, lineX, textX)
    const mainEnd = yy
    let rowsLane = []
    let laneTop = null
    let captionText = ""
    if (lane.length) {
      laneTop = yy + 4
      captionText = `${data.branch.label_it ? `${data.branch.label_it}: ` : ""}da ${plain(nodes.get(data.branch.from).text_it)} a ${plain(nodes.get(data.branch.to).text_it)}`
      yy = laneTop + (select ? 0 : ctx.measure(captionText, f, W - 12).h) + 12
      rowsLane = placeStations(lane, lineX, textX)
    }
    const all = [...rowsMain, ...rowsLane]
    const edges = lineEdges(data)
    const seg = (a, b, lanePair) => {
      const [ax, ay] = centres.get(a)
      const [bx, by] = centres.get(b)
      const done = tokenPos >= 0 && !lanePair && index.get(b) <= tokenPos
      polyline(ctx, [[ax, ay + R], [bx, by - R]], `dg-flow-line${done ? " dg-flow-done" : ""}`, `seg:${a}>${b}`)
    }
    for (const [a, b] of edges) {
      const lanePair = lane.some((n) => n.id === a || n.id === b)
      if (!lanePair) seg(a, b, false)
    }
    // the second lane: its own short line under the main one, with its caption
    if (lane.length) {
      if (!select) label(ctx, captionText, 6, laneTop, { anchor: "start", maxW: W - 12, cls: "dg-flow-branchlabel", key: "branchlabel" })
      const chain = lane.map((n) => n.id)
      chain.slice(1).forEach((id, i) => seg(chain[i], id, true))
    }
    all.forEach((row, i) => {
      station(row.n, row.cx, row.cy, i)
      if (select) return
      const t = label(ctx, plain(row.n.text_it), row.tx, row.cy - row.m.h / 2, { anchor: "start", maxW: W - row.tx - 6, cls: "dg-flow-label", key: `s:${row.n.id}:label` })
      if (row.n.actor_it) label(ctx, plain(row.n.actor_it), row.tx, t.y + t.h + 2, { anchor: "start", maxW: W - row.tx - 6, cls: "dg-flow-actor", key: `s:${row.n.id}:actor` })
    })
    if (token && !select && centres.has(token)) tokenRing(...centres.get(token))
    let bottom = yy
    if (returns.length && !select) {
      const moves = returns.map((r, k) => ({ n: k + 1, text_it: `Da ${plain(nodes.get(r.from).text_it)} a ${plain(nodes.get(r.to).text_it)}${r.label_it ? `: ${r.label_it}` : ""}` }))
      bottom = drawMoves(ctx, moves, bottom + 4, { title: TEXT.return_label })
    }
    void textW
    void mainEnd
    return { bottom }
  }
}

export function describeLine(data, ctx = {}) {
  const eff = effectiveState(data, ctx.state ?? 0)
  const nodes = byId(data)
  const names = (list) => list.map((n) => plain(n.text_it))
  const parts = [`Un percorso con ${data.nodes.length} tappe: ${listIt(names(data.nodes))}.`]
  if (data.branch) {
    parts.push(`Da ${plain(nodes.get(data.branch.from).text_it)} parte una strada più corta${data.branch.label_it ? ` (${data.branch.label_it})` : ""}: ${listIt(names(data.branch.nodes))}, e arriva a ${plain(nodes.get(data.branch.to).text_it)}.`)
  }
  for (const r of data.returns ?? []) parts.push(`Da ${plain(nodes.get(r.from).text_it)} si torna a ${plain(nodes.get(r.to).text_it)}${r.label_it ? `: ${r.label_it}` : ""}.`)
  const here = nodes.get(eff.token ?? data.token)
  if (here) parts.push(`${TEXT.path_here} ${plain(here.text_it)}.${here.actor_it ? ` ${cap(plain(here.actor_it))}.` : ""}`)
  return parts.join(" ")
}

export function printedLine(data, state = 0) {
  const out = [...data.nodes, ...(data.branch?.nodes ?? [])].flatMap((n) => [n.text_it, n.actor_it])
  out.push(data.branch?.label_it)
  for (const r of data.returns ?? []) out.push(r.label_it)
  out.push(effectiveState(data, state).op_it)
  if ((data.returns ?? []).length) out.push(TEXT.return_label, TEXT.station_here)
  out.push(describeLine(data, { state }))
  return [...new Set(out.filter(Boolean).map(String))]
}

export function targetsLine(data, set, layoutFn) {
  if (set !== "stations" || data.layout !== "line") return []
  const scene = layoutFn(withoutRoles(data), { width: 900, fontPx: 20, subject: "math", mode: "select" })
  const all = [...data.nodes, ...(data.branch?.nodes ?? [])]
  return all.map((n, i) => {
    const s = scene.shapes?.find((x) => x.key === `s:${n.id}`)
    return { key: `s:${n.id}`, bbox: s ? { x: s.cx - s.r, y: s.cy - s.r, w: 2 * s.r, h: 2 * s.r } : null, neutral_it: `tappa ${i + 1} di ${all.length}` }
  })
}
