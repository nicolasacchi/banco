// timeline (WAVE2 2.2, T4a): two scales on one time-axis engine. `years` is history's dated line (years.js: no year 0, Chrono, periods, events,
// lanes, spans, centuries, zoom as states); `tense` is the order of tenses around "adesso" (tense.js). The Ruby twin is
// Lessons::Diagrams::Timeline; both run test/fixtures/diagrams/types/timeline.json. Fixed positions: the same for every student and in print.
import schema from "lesson/diagram_schemas/timeline"
import { effectiveState, finish, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { withoutRoles } from "lesson/diagrams/graph/kit"
import { plain } from "lesson/diagrams/common"
import { TEXT } from "lesson/diagrams/time/texts"
import * as years from "lesson/diagrams/time/years"
import * as tense from "lesson/diagrams/time/tense"

export { schema }
export const type = "timeline"
export const states = stateCount

const YEAR_KEYS = ["from", "to", "every", "centuries", "lanes", "periods", "events", "spans", "measure"]
const TENSE_KEYS = ["window", "marks"]

// The state a figure is drawn in: a select figure shows its top level whatever the state.
const stateOf = (data, i, mode) => (mode === "select" ? (({ states: _s, ...top }) => top)(data) : effectiveState(data, i))

// The same checks as Lessons::Diagrams::Timeline, the first finding only.
export function semantic(data, ctx) {
  const map = (path, message) => ({ path, message, code: "E-LESSON-MAP" })
  const dia = (path, message) => ({ path, message, code: "E-LESSON-DIAGRAM" })
  const isYears = data.scale === "years"
  for (const k of isYears ? TENSE_KEYS : YEAR_KEYS) if (k in data) return dia(`/${k}`, `a ${data.scale} timeline has no ${k}`)
  for (const [i, s] of (data.states ?? []).entries()) for (const k of isYears ? TENSE_KEYS : ["from", "to", "periods", "events", "spans"]) if (k in s) return dia(`/states/${i}/${k}`, `a ${data.scale} timeline has no ${k}`)
  const first = isYears ? years.staticChecks(data, map, dia) : tense.staticChecks(data, map, dia)
  if (first) return first
  const list = (data.states ?? []).length ? data.states.map((_, i) => ["/states/" + i, effectiveState(data, i)]) : [["", data]]
  for (const [path, eff] of list) {
    const found = isYears ? years.stateChecks(eff, path, map, dia) : tense.stateChecks(eff, path, map, dia, ctx?.subject)
    if (found) return found
  }
  return null
}

function build(data, ctx) {
  const eff = stateOf(data, ctx.state, ctx.mode)
  const out = data.scale === "years" ? years.buildYears(data, ctx, eff) : tense.buildTense(data, ctx, eff, years.legendRow)
  if (out.error) return out
  const op = ctx.mode === "select" ? null : eff.op_it ?? null
  return finish(ctx, out.bottom, { states: stateCount(data), state: ctx.state, op, hits: out.hits, ...(out.live ? { live: out.live } : {}) })
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// The measure control (events only): choose two facts and read the years between them.
export function controls(data) {
  if (!data.measure) return []
  const seen = new Map()
  for (const eff of [data, ...(data.states ?? []).map((_, i) => effectiveState(data, i))]) for (const e of eff.events ?? []) seen.set(e.id, e)
  return [{ id: "measure", kind: "chips", multi: true, label_it: TEXT.measure_label, hint_it: TEXT.measure_hint, values: [...seen.values()].map((e) => ({ value: e.id, label_it: plain(e.label_it) })) }]
}

export function describe(data, ctx = {}) {
  const eff = effectiveState(data, ctx.state ?? 0)
  return data.scale === "years" ? years.describeYears(eff, ctx.controls) : tense.describeTense(eff)
}

export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const out = data.scale === "years" ? years.printedYears(eff) : tense.printedTense(eff)
  out.push(eff.op_it, describe(data, { state }))
  return [...new Set(out.filter(Boolean).map(String))]
}

export function reachable(data) {
  const all = [data, ...(data.states ?? []).map((_, i) => effectiveState(data, i))]
  const out = years.reachableYears(data, all)
  return out.length > 500 ? "over_cap" : out
}

// The select targets of a set, in the order of the data: events and marks by id, periods by position.
export function targets(data, set) {
  if (!["events", "periods", "marks"].includes(set)) return []
  const scene = layout(withoutRoles(data), { width: 700, fontPx: 20, subject: (data.marks ?? []).some((m) => m.text_es) ? "spanish" : data.scale === "tense" ? "english" : "math", mode: "select", set })
  const list = set === "events" ? data.events ?? [] : set === "periods" ? data.periods ?? [] : data.marks ?? []
  return list.map((item, i) => {
    const key = set === "events" ? `ev:${item.id}` : set === "periods" ? `pd:${i + 1}` : `mk:${item.id}`
    const s = scene.shapes?.find((x) => x.key === `${key}:target`) ?? scene.shapes?.find((x) => x.key === key)
    return { key, bbox: s ? { x: s.x, y: s.y, w: s.w ?? 2 * s.r, h: s.h ?? 2 * s.r } : null, neutral_it: `${set === "events" ? "punto" : set === "periods" ? "periodo" : "segno"} ${i + 1} di ${list.length}` }
  })
}

