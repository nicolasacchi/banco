// seats (T6, WAVE2 2.4; law 1.3): a hemicycle or a grid of seats, with the quorum and the majorities computed in integers.
//   numero legale floor(seats/2)+1 present; maggioranza dei presenti floor(present/2)+1 (a tie fails); assoluta floor(seats/2)+1;
//   two thirds ceil(2 seats/3); three fifths ceil(3 seats/5). Abstention is left out on purpose: everyone present votes yes or no.
// `try` declares the ranges of two sliders (each drawn with its - and + buttons); the figure follows them and reads each change out.
// Which seat is absent or says no is spread evenly and means nothing: only the counts are true.
// Ruby twin: Lessons::Diagrams::Seats; shared vectors: test/fixtures/lesson2/seats.json and test/fixtures/diagrams/types/seats.json.
import schema from "lesson/diagram_schemas/seats"
import { effectiveState, finish, label, listIt, plain, shape, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const type = "seats"
export { schema }
export const states = stateCount

export const THRESHOLDS = ["legal_number", "present_majority", "absolute_majority", "two_thirds", "three_fifths"]
const GRID_MAX = 200
const HEMICYCLE_MAX = 1000
const NAMES = {
  legal_number: "Numero legale",
  present_majority: "Maggioranza dei presenti",
  absolute_majority: "Maggioranza assoluta",
  two_thirds: "Due terzi dei componenti",
  three_fifths: "Tre quinti dei componenti"
}

// ---- the arithmetic (integers only) -------------------------------------------------------------------------------------------------------

// { name: { need, met } } for the listed thresholds; present and yes may be undefined (need or met is then null)
export function thresholds(seats, present, yes, list) {
  const out = {}
  for (const name of list) {
    let need = null
    if (name === "legal_number" || name === "absolute_majority") need = Math.floor(seats / 2) + 1
    else if (name === "present_majority") need = present === undefined || present === null ? null : Math.floor(present / 2) + 1
    else if (name === "two_thirds") need = Math.floor((2 * seats + 2) / 3)
    else if (name === "three_fifths") need = Math.floor((3 * seats + 4) / 5)
    const have = name === "legal_number" ? present : yes
    out[name] = { need, met: need === null || have === undefined || have === null ? null : have >= need }
  }
  return out
}

// true / false when the listed thresholds decide the vote, null when they cannot
export function approved(seats, present, yes, list) {
  const verdicts = Object.values(thresholds(seats, present, yes, list)).map((v) => v.met)
  if (verdicts.length === 0 || verdicts.includes(null)) return null
  return verdicts.every(Boolean)
}

// ---- the figure's numbers in a state, with the sliders applied ----------------------------------------------------------------------------------

function values(data, eff, controls) {
  const try_ = data.try
  let present = eff.present
  let yes = eff.yes
  if (try_?.present && controls?.present !== undefined) present = Math.max(try_.present[0], Math.min(try_.present[1], Math.round(Number(controls.present))))
  else if (try_?.present && present === undefined) present = try_.present[0]
  if (try_?.yes && controls?.yes !== undefined) yes = Math.max(try_.yes[0], Math.min(try_.yes[1], Math.round(Number(controls.yes))))
  else if (try_?.yes && yes === undefined) yes = try_.yes[0]
  if (yes !== undefined && present !== undefined) yes = Math.min(yes, present)
  return { seats: eff.seats, present, yes, list: eff.thresholds ?? [], groups: eff.groups ?? [] }
}

export function semantic(data) {
  const cap = data.layout === "grid" ? GRID_MAX : HEMICYCLE_MAX
  if (data.seats > cap) return { path: "/seats", message: `a ${data.layout} holds at most ${cap} seats` }
  for (let i = 0; i < stateCount(data); i++) {
    const eff = effectiveState(data, i)
    const at = data.states ? `/states/${i}` : ""
    const groups = eff.groups ?? []
    if (groups.reduce((a, g) => a + g.seats, 0) > eff.seats) return { path: `${at}/groups`, message: "the groups hold more seats than the house" }
    if (eff.present !== undefined && eff.present > eff.seats) return { path: `${at}/present`, message: "present is more than the seats" }
    if (eff.yes !== undefined && (eff.present === undefined ? !data.try : eff.yes > eff.present)) return { path: `${at}/yes`, message: "yes needs present and is at most present" }
    if (new Set(eff.thresholds ?? []).size !== (eff.thresholds ?? []).length) return { path: `${at}/thresholds`, message: "a threshold is named once" }
  }
  const t = data.try
  if (t) {
    for (const key of ["present", "yes"]) {
      if (t[key] && (t[key][0] > t[key][1] || t[key][1] > data.seats)) return { path: `/try/${key}`, message: `the range of ${key} runs from a smaller to a larger number inside the seats` }
    }
    if (t.yes && t.present && t.yes[1] > t.present[0]) return { path: "/try", message: "the largest yes must not be above the smallest present" }
  }
  return null
}

// ---- the seats ------------------------------------------------------------------------------------------------------------------------------------

// positions {x, y} (unit radius 1 = outer arc; the half circle opens downwards) of n seats in reading order, left to right
function hemicycle(n, R, r0) {
  const d = Math.sqrt((Math.PI / 2) * (R * R - r0 * r0) / n)
  const rows = Math.max(1, Math.round((R - r0) / d))
  const radii = Array.from({ length: rows }, (_, k) => r0 + ((k + 0.5) * (R - r0)) / rows)
  const total = radii.reduce((a, b) => a + b, 0)
  const counts = radii.map((r) => Math.max(1, Math.round((n * r) / total)))
  let diff = n - counts.reduce((a, b) => a + b, 0)
  for (let k = rows - 1; diff !== 0; k = k === 0 ? rows - 1 : k - 1) {
    const step = diff > 0 ? 1 : -1
    if (counts[k] + step >= 1) {
      counts[k] += step
      diff -= step
    }
  }
  const seats = []
  radii.forEach((r, k) => {
    for (let j = 0; j < counts[k]; j++) {
      const theta = counts[k] === 1 ? Math.PI / 2 : Math.PI - (Math.PI * j) / (counts[k] - 1)
      seats.push({ theta, row: k, x: r * Math.cos(theta), y: -r * Math.sin(theta) })
    }
  })
  seats.sort((a, b) => b.theta - a.theta || a.row - b.row)
  return { seats, d }
}

// Bresenham: seat i is picked when the running share of `count` in `total` crosses a whole number
const spread = (i, count, total) => Math.floor(((i + 1) * count) / total) > Math.floor((i * count) / total)

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const v = values(data, eff, ctx.controls)
  const f = ctx.fontPx
  const W = ctx.width
  const n = v.seats
  let seats
  let dot
  let height
  const pad = 8
  if (data.layout === "grid") {
    const cols = n <= 100 ? 10 : 20
    const cell = Math.min((W - 2 * pad) / cols, 44)
    const x0 = (W - cols * cell) / 2
    seats = Array.from({ length: n }, (_, i) => ({ x: x0 + (i % cols) * cell + cell / 2, y: pad + Math.floor(i / cols) * cell + cell / 2 }))
    dot = cell * 0.36
    height = pad * 2 + Math.ceil(n / cols) * cell
  } else {
    const R = Math.min(W / 2 - pad - 4, 40 * Math.sqrt(n) + 12)
    const r0 = R * 0.38
    const h = hemicycle(n, R, r0)
    dot = Math.max(1.6, Math.min(h.d * 0.4, 15))
    const cxm = W / 2
    seats = h.seats.map((s) => ({ x: cxm + s.x * 1, y: pad + dot + R + s.y }))
    height = pad * 2 + dot + R
  }
  // groups in reading order, then the seats that belong to no group
  const owner = new Array(n).fill(-1)
  let at = 0
  v.groups.forEach((g, gi) => {
    for (let k = 0; k < g.seats && at < n; k++) owner[at++] = gi
  })
  const voting = v.present !== undefined
  const absent = voting ? n - v.present : 0
  const presentIdx = []
  const isAbsent = new Array(n).fill(false)
  for (let i = 0; i < n; i++) {
    if (voting && spread(i, absent, n)) isAbsent[i] = true
    else presentIdx.push(i)
  }
  const noVote = new Set()
  if (voting && v.yes !== undefined) {
    const nos = presentIdx.length - v.yes
    presentIdx.forEach((seat, j) => {
      if (spread(j, nos, presentIdx.length)) noVote.add(seat)
    })
  }
  seats.forEach((s, i) => {
    const role = owner[i] >= 0 ? v.groups[owner[i]].role : null
    const tone = owner[i] >= 0 ? (role ? `mk-${role}` : `dgs-g${owner[i] % 4}`) : "dgs-other"
    if (isAbsent[i]) shape(ctx, "circle", { cx: s.x, cy: s.y, r: Math.max(1.2, dot * 0.45), cls: `dgs-absent ${tone}` })
    else if (noVote.has(i)) shape(ctx, "circle", { cx: s.x, cy: s.y, r: dot * 0.8, cls: `dgs-no ${tone}` })
    else shape(ctx, "circle", { cx: s.x, cy: s.y, r: dot, cls: `dgs-yes ${tone}` })
  })
  let y = height + 12

  // the legend: groups, and what full, empty and small mean when the house votes
  const items = []
  v.groups.forEach((g, gi) => items.push({ tone: g.role ? `mk-${g.role}` : `dgs-g${gi % 4}`, text: `${plain(g.label_it)}: ${g.seats}` }))
  const rest = n - v.groups.reduce((a, g) => a + g.seats, 0)
  if (v.groups.length && rest > 0) items.push({ tone: "dgs-other", text: `Altri seggi: ${rest}` })
  if (voting) {
    items.push({ mark: "yes", text: v.yes !== undefined ? "Pieno: vota sì" : "Pieno: presente" })
    if (v.yes !== undefined) items.push({ mark: "no", text: "Vuoto: vota no" })
    items.push({ mark: "absent", text: "Piccolo: assente" })
  }
  let rowX = 0
  let rowY = y
  let rowH = ctx.lineH
  for (const it of items) {
    const maxW = W - 30
    const m = ctx.measure(it.text, f, maxW)
    const w = 26 + Math.min(m.w, maxW) + 14
    if (rowX > 0 && rowX + w > W) {
      rowX = 0
      rowY += rowH + 4
      rowH = ctx.lineH
    }
    const sy = rowY + ctx.lineH / 2
    if (it.mark === "yes") shape(ctx, "circle", { cx: rowX + 10, cy: sy, r: 7, cls: "dgs-yes dgs-other" })
    else if (it.mark === "no") shape(ctx, "circle", { cx: rowX + 10, cy: sy, r: 6, cls: "dgs-no dgs-other" })
    else if (it.mark === "absent") shape(ctx, "circle", { cx: rowX + 10, cy: sy, r: 3, cls: "dgs-absent dgs-other" })
    else shape(ctx, "circle", { cx: rowX + 10, cy: sy, r: 7, cls: `dgs-yes ${it.tone}` })
    const l = label(ctx, it.text, rowX + 26, rowY, { anchor: "start", maxW, cls: "dgs-legend" })
    rowH = Math.max(rowH, l.h)
    rowX += w
  }
  y = rowY + (items.length ? rowH + 8 : 0)

  // the readout: short lines, the same sentences the live region reads
  const lines = readout(v)
  for (const text of lines) y += label(ctx, text, 4, y, { anchor: "start", maxW: W - 8, cls: "dgs-line" }).h + 4
  return finish(ctx, y + 2, { states: stateCount(data), state: ctx.state, live: lines.join(" ") })
}

// the readout sentences of a state (the numbers a student can read; L5 enumerates them in Ruby)
export function readout(v) {
  const lines = []
  lines.push(v.present === undefined ? `Seggi: ${v.seats}.` : `Seggi: ${v.seats}. Presenti: ${v.present}.`)
  const t = thresholds(v.seats, v.present, v.yes, v.list)
  for (const name of v.list) {
    const { need, met } = t[name]
    if (need === null) continue
    const unit = name === "legal_number" ? "presenti" : "sì"
    lines.push(`${NAMES[name]}: servono ${need} ${unit}.${met === null ? "" : met ? " Ci sono." : " Non ci sono."}`)
  }
  if (v.yes !== undefined) lines.push(`Voti sì: ${v.yes}.`)
  const ok = approved(v.seats, v.present, v.yes, v.list)
  if (ok !== null) lines.push(`Esito: ${ok ? "approvata" : "non approvata"}.`)
  return lines
}

export function controls(data) {
  const t = data?.try
  if (!t) return []
  const out = []
  if (t.present) out.push({ id: "present", kind: "slider", range: [String(t.present[0]), String(t.present[1])], step: "1", value: data.present ?? t.present[0], label_it: "Presenti" })
  if (t.yes) out.push({ id: "yes", kind: "slider", range: [String(t.yes[0]), String(t.yes[1])], step: "1", value: data.yes ?? t.yes[0], label_it: "Voti sì" })
  return out
}

export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const out = [eff.seats, eff.present, eff.yes, ...(eff.groups ?? []).map((g) => g.seats)]
  for (const v of Object.values(thresholds(eff.seats, eff.present, eff.yes, eff.thresholds ?? []))) out.push(v.need)
  const seen = [...new Set(out.filter((x) => x !== undefined && x !== null))]
  return seen.sort((a, b) => a - b).map(String)
}

function describeState(data, eff, index, total, controls) {
  const v = values(data, eff, controls)
  const how = data.layout === "grid" ? "disposti in una griglia di righe da dieci" : "disposti a semicerchio"
  const bits = [`Una camera di ${v.seats} seggi ${how}.`]
  if (v.groups.length) bits.push(`Gruppi: ${listIt(v.groups.map((g) => `${plain(g.label_it)}, ${g.seats} seggi`))}.`)
  const [first, ...rest] = readout(v)
  if (v.present !== undefined) bits.push(`Presenti: ${v.present}.`)
  void first
  bits.push(...rest)
  return `${total > 1 ? `Passo ${index + 1}. ` : ""}${bits.join(" ")}`
}

export function describe(data, ctx = {}) {
  const n = stateCount(data)
  if (typeof ctx?.state === "number") return describeState(data, effectiveState(data, ctx.state), ctx.state, n, ctx.controls)
  const out = []
  for (let i = 0; i < n; i++) out.push(describeState(data, effectiveState(data, i), i, n, ctx?.controls))
  return out.join(" ")
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })
