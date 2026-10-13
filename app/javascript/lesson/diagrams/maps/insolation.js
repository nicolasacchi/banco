// insolation (T5, W2-1, D-276): the Earth's profile with parallel rays on up to four latitudes and, with `stepper`, one movable beam
// (-80 to 80 degrees, every 10). The same beam of light covers 1/cos(latitude - subsolar latitude) times the ground; that number is computed
// here and in Ruby (lib/lessons/diagrams/insolation.rb), printed with one decimal and never written by the author. `subsolar` is the latitude
// where the Sun is overhead (0 at an equinox, 23,4 on 21 June, -23,4 on 21 December). The 3D globe with the Sun is W2-3.
//
// Geometry (screen, y down): the Sun is at the left; its direction from the centre is S = (-cos d, -sin d); the rays travel along
// D = (cos d, sin d); a ray at offset t along N = (-sin d, cos d) hits the sunlit side at C + t N - sqrt(R^2 - t^2) D; the surface point of
// latitude f has t = R sin(d - f). A beam is two such rays a fixed width apart; its patch on the ground is the arc between the two hits.
import schema from "lesson/diagram_schemas/insolation"
import * as N from "lesson/num"
import * as G from "lesson/diagrams/maps/geo"
import { finish, label, shape } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const type = "insolation"
export { schema }

const MAX_ANGLE = 85
const TROPIC = N.make(235n, 10n)
const STEP = 10
const rad = (d) => (d * Math.PI) / 180

const sub = (eff) => N.parse(eff.subsolar ?? "0") ?? N.int(0)
const spreadOf = (lat, s) => 1 / Math.cos(rad(N.toNumber(N.sub(lat, s))))
const spreadStr = (lat, s) => G.fmt1f(spreadOf(lat, s))
const stepperOn = (eff) => eff.stepper === true
const spreadOn = (eff) => eff.spread !== false

// The latitudes the movable beam can stand on in a state with subsolar latitude s.
export function stepperValues(s) {
  const out = []
  for (let v = -80; v <= 80; v += STEP) if (Math.abs(N.toNumber(N.sub(N.int(v), s))) <= MAX_ANGLE) out.push(v)
  return out
}

// Where the movable beam starts: 0, else the nearest step to 0 that no fixed beam stands on (the two would be drawn over one another).
export function startBeam(eff) {
  const values = stepperValues(sub(eff))
  const taken = (eff.latitudes ?? []).map((l) => N.toNumber(N.parse(l)))
  const free = values.filter((v) => !taken.includes(v))
  const pool = free.length ? free : values
  return pool.length ? pool.reduce((best, v) => (Math.abs(v) < Math.abs(best) || (Math.abs(v) === Math.abs(best) && v > best) ? v : best)) : 0
}

function beamOf(eff, controls) {
  const values = stepperValues(sub(eff))
  const want = controls?.lat !== undefined ? Number(controls.lat) : startBeam(eff)
  if (values.includes(want)) return want
  return values.length ? values.reduce((best, v) => (Math.abs(v - want) < Math.abs(best - want) ? v : best)) : 0
}

export function semanticAll(data) {
  const out = []
  const n = Array.isArray(data.states) && data.states.length > 0 ? data.states.length : 1
  for (let i = 0; i < n; i++) {
    const eff = G.effective(data, i)
    const path = Array.isArray(data.states) && data.states.length > 0 ? `/states/${i}` : ""
    const add = (p, message) => out.push({ path: p, message })
    const s0 = N.parse(eff.subsolar ?? "0")
    if (s0 === null || N.compare(absOf(s0), TROPIC) > 0) add(`${path}/subsolar`, "the Sun is overhead between the tropics: subsolar goes from -23,5 to 23,5")
    const s = s0 ?? N.int(0)
    const lats = (eff.latitudes ?? []).map((l) => N.parse(l))
    lats.forEach((lat, k) => {
      const at = `${path}/latitudes/${k}`
      if (lat === null || N.compare(absOf(lat), N.int(90)) > 0) add(at, "a latitude goes from -90 to 90")
      else if (Math.abs(N.toNumber(N.sub(lat, s))) > MAX_ANGLE) add(at, `at ${G.latWord(lat)} the Sun is more than ${MAX_ANGLE} degrees from overhead (subsolar ${G.latWord(s)}): the beam would graze the ground`)
    })
    const canon = lats.filter((l) => l !== null).map((l) => N.canonical(l))
    if (new Set(canon).size !== canon.length) add(`${path}/latitudes`, "a latitude is listed twice")
  }
  return out
}
const absOf = (r) => N.make(r.n < 0n ? -r.n : r.n, r.d)
export const semantic = (data) => semanticAll(data)[0] ?? null

const sunPhrase = (s) => (N.isZero(s) ? "l'equatore" : G.latWord(s))
const sentence = (lat, s, moving) => `${moving ? "Il raggio mobile" : "Il raggio"} a ${G.latWord(lat)}: la luce si spalma su ${spreadStr(lat, s)} volte il terreno.`

export function describe(data, ctx = {}) {
  const eff = G.effective(data, ctx.state ?? 0)
  const s = sub(eff)
  const lats = (eff.latitudes ?? []).map((l) => N.parse(l))
  const out = [`La Terra vista di lato, con i raggi del Sole paralleli. Il Sole è alto sopra ${sunPhrase(s)}.`]
  for (const lat of lats) out.push(spreadOn(eff) ? sentence(lat, s, false) : `C'è un raggio a ${G.latWord(lat)}.`)
  if (stepperOn(eff)) {
    const beam = N.int(beamOf(eff, ctx.controls))
    out.push(spreadOn(eff) ? sentence(beam, s, true) : `Il raggio mobile è a ${G.latWord(beam)}.`)
  }
  if (eff.op_it) out.push(`${eff.op_it}.`)
  return out.join(" ")
}

export function printed(data, state = 0) {
  const eff = G.effective(data, state)
  const s = sub(eff)
  const lats = (eff.latitudes ?? []).map((l) => N.parse(l))
  const out = [describe(data, { state })]
  for (const lat of lats) out.push(G.latWord(lat))
  if (spreadOn(eff)) for (const lat of lats) out.push(spreadStr(lat, s))
  if (eff.op_it) out.push(eff.op_it)
  if (data.caption_it) out.push(data.caption_it)
  return [...new Set(out.filter(Boolean))]
}

export function reachable(data) {
  const out = []
  const n = G.hasStates(data) ? data.states.length : 1
  for (let i = 0; i < n; i++) {
    const eff = G.effective(data, i)
    const s = sub(eff)
    for (const l of eff.latitudes ?? []) out.push(spreadStr(N.parse(l), s))
    if (stepperOn(eff)) for (const v of stepperValues(s)) out.push(G.latWord(N.int(v)), spreadStr(N.int(v), s))
  }
  const all = [...new Set(out)]
  return all.length > 500 ? null : all
}

export function controls(data, ctx = {}) {
  const eff = G.effective(data, ctx.state ?? 0)
  if (!stepperOn(eff)) return []
  const values = stepperValues(sub(eff))
  return [{ id: "lat", kind: "stepper", values, label_it: "Latitudine del raggio mobile", format: "lat", initial: startBeam(eff) }]
}

// Every state prints (P1: all states, as small multiples when at most 4).
export function printViews(data) {
  const n = G.hasStates(data) ? data.states.length : 1
  return n > 1 ? Array.from({ length: Math.min(n, 4) }, (_, i) => ({ state: i, controls: {} })) : []
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

function build(data, ctx) {
  const eff = G.effective(data, ctx.state)
  const s = sub(eff)
  const sd = N.toNumber(s)
  const f = ctx.fontPx
  const lats = (eff.latitudes ?? []).map((l) => N.parse(l))
  const moving = stepperOn(eff) ? N.int(beamOf(eff, ctx.controls)) : null
  const beams = [...lats.map((lat) => ({ lat, moving: false })), ...(moving ? [{ lat: moving, moving: true }] : [])]
  const names = beams.map((b) => G.latWord(b.lat))
  const lw = Math.max(...names.map((t) => ctx.measure(t, f).w)) + 6
  const x0 = lw + 14
  const R = Math.max(60, Math.min(Math.max(70, Math.min(170, ctx.width * 0.28)), (ctx.width - x0 - 14 - 60) / 2))
  const cx = ctx.width - R - 14
  const topPad = ctx.lineH + 6
  const cy = topPad + R
  const height = cy + R + ctx.lineH + 8
  const dx = Math.cos(rad(sd))
  const dy = Math.sin(rad(sd))
  const nx = -dy
  const ny = dx
  const BW = Math.max(12, R * 0.12)
  const hit = (t) => {
    const k = Math.sqrt(Math.max(R * R - t * t, 0))
    return [cx + t * nx - k * dx, cy + t * ny - k * dy]
  }
  const startOf = (t) => {
    const sParam = (x0 - cx - t * nx) / dx
    return [cx + t * nx + sParam * dx, cy + t * ny + sParam * dy]
  }
  const clampT = (t) => Math.max(-R * 0.995, Math.min(R * 0.995, t))

  // the Earth and its night half
  shape(ctx, "circle", { cx, cy, r: R, cls: "dg-earth" })
  const night = [cx + R * nx, cy + R * ny]
  const night2 = [cx - R * nx, cy - R * ny]
  shape(ctx, "path", { d: `M${night[0].toFixed(1)} ${night[1].toFixed(1)} A${R} ${R} 0 0 0 ${night2[0].toFixed(1)} ${night2[1].toFixed(1)}Z`, cls: "dg-night" })
  shape(ctx, "line", { x1: cx - R, y1: cy, x2: cx + R, y2: cy, cls: "dg-equator" })
  label(ctx, "Nord", cx, cy - R - ctx.lineH - 2, { anchor: "middle", cls: "dg-compass" })
  label(ctx, "Sud", cx, cy + R + 2, { anchor: "middle", cls: "dg-compass" })
  const nightLabel = [cx + R * 0.55 * dx - R * 0.3 * nx, cy + R * 0.55 * dy - R * 0.3 * ny]
  if (R >= 70) label(ctx, "notte", nightLabel[0], nightLabel[1], { anchor: "middle", valign: "middle", cls: "dg-nightlabel" })

  // the beams: two rays, the patch between the two hits
  const placed = []
  const rows = beams.map((b) => {
    const lat = N.toNumber(b.lat)
    const t0 = R * Math.sin(rad(sd - lat))
    const t1 = clampT(t0 - BW / 2)
    const t2 = clampT(t0 + BW / 2)
    return { b, lat, t0, t1, t2 }
  })
  for (const r of rows) {
    const [s1, s2] = [startOf(r.t1), startOf(r.t2)]
    const [h1, h2] = [hit(r.t1), hit(r.t2)]
    shape(ctx, "polygon", { points: [s1, h1, h2, s2], cls: `dg-beam${r.b.moving ? " dg-beam-move" : ""}` })
    shape(ctx, "path", { d: `M${h1[0].toFixed(1)} ${h1[1].toFixed(1)} A${R} ${R} 0 0 ${arcSweep(h1, h2, cx, cy)} ${h2[0].toFixed(1)} ${h2[1].toFixed(1)}`, cls: `dg-patch${r.b.moving ? " dg-patch-move" : ""}` })
    r.y = (s1[1] + s2[1]) / 2
  }
  // the latitude of each beam, at its left end, kept apart
  rows.sort((a, c) => a.y - c.y)
  let last = -Infinity
  for (const r of rows) {
    const y = Math.max(r.y, last + ctx.lineH + 2)
    last = y
    placed.push({ r, y })
  }
  const shift = Math.max(0, placed.length ? placed[placed.length - 1].y + ctx.lineH / 2 - (height - 4) : 0)
  for (const { r, y } of placed) {
    const text = G.latWord(r.b.lat) + (r.b.moving ? "" : "")
    label(ctx, text, 4, y - shift, { anchor: "start", valign: "middle", cls: `dg-name${r.b.moving ? " dg-name-move" : ""}` })
  }
  // the Sun overhead: a mark on the Earth where the rays are vertical
  const sp = hit(0)
  shape(ctx, "circle", { cx: sp[0], cy: sp[1], r: 5, cls: "dg-sunmark" })

  const legend = []
  if (spreadOn(eff)) {
    for (const r of [...rows].sort((a, c) => c.lat - a.lat)) {
      legend.push({ text_it: `${G.latWord(r.b.lat)}: la luce si spalma su ${spreadStr(r.b.lat, s)} volte il terreno${r.b.moving ? " (raggio mobile)" : ""}`, swatch: { kind: r.b.moving ? "beam-move" : "beam" } })
    }
  }
  return finish(ctx, height + shift, {
    legend,
    live: moving ? sentence(moving, s, true) : "",
    states: Array.isArray(data.states) ? data.states.length : 1,
    state: ctx.state
  })
}

// 0 or 1: the short way round from a to b (the beam's patch is always less than half the Earth).
function arcSweep(a, b, cx, cy) {
  const cross = (a[0] - cx) * (b[1] - cy) - (a[1] - cy) * (b[0] - cx)
  return cross > 0 ? 1 : 0
}
