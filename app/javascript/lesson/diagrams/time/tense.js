// The tense scale of `timeline` (WAVE2 2.2, english 3.2, T4a): the ORDER of what happens around "adesso", not clock time. One row per mark: the
// sentence in the target language above, a shape on the axis (a point, a range, a habit as a row of dots, a plan as an arc from the moment it
// was decided), the Italian question beside it. "prima" and "dopo" are named, "adesso" is a dashed line through every row.
import { label, plain, roleInfo, shape, words } from "lesson/diagrams/common"
import { arrowhead } from "lesson/diagrams/graph/kit"
import { fill, TEXT } from "lesson/diagrams/time/texts"

export const CAPS = { tense_mark_words: 8, label_words: 6 }
const LANG_OF = { text_en: "english", text_es: "spanish" }
const LANG_CODE = { text_en: "en", text_es: "es" }

export const sayOf = (m) => m.text_en ?? m.text_es
const rel = (v) => (Number(v) < 0 ? TEXT.rel_before : Number(v) === 0 ? TEXT.rel_now : TEXT.rel_after)

export function staticChecks(data, map, dia) {
  return null
}

export function stateChecks(eff, path, map, dia, subject) {
  const window = eff.window
  if (!window) return null
  const [lo, hi] = window.map(Number)
  if (!(lo < hi && lo <= 0 && hi >= 0)) return dia(`${path}/window`, "the window goes from a smaller number to a larger one and contains 0 (now)")
  const marks = eff.marks ?? []
  if (new Set(marks.map((m) => m.id)).size !== marks.length) return map(`${path}/marks`, "mark ids must be unique")
  for (const [i, m] of marks.entries()) {
    const at = `${path}/marks/${i}`
    const spoken = Object.keys(LANG_OF).filter((k) => m[k])
    if (spoken.length !== 1) return dia(at, "a mark says its sentence in one language: text_en or text_es")
    if (subject !== LANG_OF[spoken[0]]) return dia(`${at}/${spoken[0]}`, `${spoken[0]} is for ${LANG_OF[spoken[0]]} lessons`)
    const n = words(m[spoken[0]])
    if (n > CAPS.tense_mark_words) return { path: `${at}/${spoken[0]}`, message: `a mark has ${n} words (at most ${CAPS.tense_mark_words})`, code: "E-READ" }
    const nl = words(m.label_it)
    if (nl > 8) return dia(`${at}/label_it`, `a label has ${nl} words (at most 8)`)
    const want = { point: [], range: ["to"], habit: [], plan: ["from"] }[m.span]
    const allowed = [...want, ...(m.span === "habit" ? ["to"] : [])]
    for (const k of ["to", "from"]) if (!allowed.includes(k) && m[k]) return dia(`${at}/${k}`, `a ${m.span} mark has no ${k}`)
    for (const k of want) if (m[k] === undefined) return dia(`${at}/${k}`, `a ${m.span} mark needs ${k}`)
    for (const k of ["at", "to", "from"]) if (m[k] !== undefined && !(Number(m[k]) >= lo && Number(m[k]) <= hi)) return dia(`${at}/${k}`, `${k} is outside the window`)
    if (m.to !== undefined && Number(m.to) <= Number(m.at)) return dia(`${at}/to`, "a range or a habit goes from a smaller number to a larger one")
    if (m.from !== undefined && Number(m.from) >= Number(m.at)) return dia(`${at}/from`, "a plan is made before it happens: from is smaller than at")
  }
  return null
}

export function describeTense(eff) {
  const parts = [TEXT.tense_intro]
  const marks = [...(eff.marks ?? [])].sort((a, b) => Number(a.at) - Number(b.at) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
  for (const m of marks) {
    let how
    if (m.span === "point") how = fill(TEXT.mark_point, { at: rel(m.at) })
    else if (m.span === "range") how = fill(TEXT.mark_range, { at: rel(m.at), to: rel(m.to) })
    else if (m.span === "habit") how = TEXT.mark_habit
    else how = fill(TEXT.mark_plan, { from: rel(m.from), at: rel(m.at) })
    if (m.uncertain) how += `, ${TEXT.mark_uncertain}`
    const say = plain(sayOf(m)) === "·" ? TEXT.neutral_point : plain(sayOf(m))
    parts.push(m.label_it ? `${say} (${plain(m.label_it)}): ${how}.` : `${say}: ${how}.`)
  }
  return parts.join(" ")
}

export function printedTense(eff) {
  const out = [TEXT.before, TEXT.now, TEXT.after]
  for (const m of eff.marks ?? []) out.push(m.text_en, m.text_es, m.label_it)
  return out
}

const shapeOf = (ctx, role) => roleInfo(ctx.palette, ctx.subject, role ?? "muted")?.shape ?? "circle"

export function buildTense(data, ctx, eff, legendRow) {
  const W = ctx.width
  const f = ctx.fontPx
  const lineH = ctx.lineH
  const select = ctx.mode === "select"
  const set = ctx.set ?? ctx.targetSet
  const [lo, hi] = eff.window.map(Number)
  const r = Math.round(f * 0.55)
  const x0 = Math.max(18, r + 10)
  const x1 = W - x0
  const xOf = (v) => x0 + ((Number(v) - lo) / (hi - lo)) * (x1 - x0)
  const nowX = xOf(0)
  const marks = eff.marks ?? []
  const roles = []
  let y = 6

  // the header: "adesso" over the axis, "prima" and "dopo" under its ends
  if (!select) {
    const w = Math.ceil(ctx.measure(TEXT.now, f).w)
    label(ctx, TEXT.now, Math.max(4, Math.min(nowX - w / 2, W - 4 - w)), y, { anchor: "start", cls: "dg-tl-now", key: "now" })
  }
  y += lineH + 4
  const axisY = y
  shape(ctx, "line", { x1: x0, y1: axisY, x2: x1, y2: axisY, cls: "dg-tl-axis", key: "axis" })
  for (let v = Math.ceil(lo); v <= hi; v++) shape(ctx, "line", { x1: xOf(v), y1: axisY, x2: xOf(v), y2: axisY + (v === 0 ? 14 : 7), cls: `dg-tl-tick${v === 0 ? " dg-tl-tick-major" : ""}`, key: `tick:${v}` })
  y = axisY + 18
  if (!select) {
    label(ctx, `← ${TEXT.before}`, 8, y, { anchor: "start", cls: "dg-tl-side", key: "before" })
    label(ctx, `${TEXT.after} →`, W - 8, y, { anchor: "end", cls: "dg-tl-side", key: "after" })
  }
  y += lineH + 6
  const rowsTop = y

  for (const [i, m] of marks.entries()) {
    const role = m.role ?? "muted"
    roles.push(m.role)
    const a = xOf(m.at)
    const b = m.span === "range" ? xOf(m.to) : m.span === "habit" ? xOf(m.to ?? hi) : a
    const from = m.span === "plan" ? xOf(m.from) : a
    const lead = Math.min(a, from)
    const tail = Math.max(b, a)
    const say = sayOf(m)
    const probe = select ? { w: 0, h: 0 } : ctx.measure(plain(say), f, W - 12)
    const textW = Math.min(Math.ceil(probe.w), W - 12)
    const arc = m.span === "plan" ? Math.round(f * 0.9) : 0
    const yMark = y + (select ? 0 : probe.h + 4) + arc + r + 2
    // the guide line and the shape
    shape(ctx, "line", { x1: x0, y1: yMark, x2: x1, y2: yMark, cls: "dg-tl-guide", key: `mk:${m.id}:guide` })
    const dashed = m.uncertain ? " dg-tl-uncertain" : ""
    if (m.span === "range") shape(ctx, "rect", { x: a, y: yMark - r * 0.55, w: Math.max(b - a, 2), h: r * 1.1, r: r * 0.55, cls: `dg-tl-range mk-${role}${dashed}`, key: `mk:${m.id}:range` })
    if (m.span === "habit") for (let v = Number(m.at); v <= Number(m.to ?? hi); v++) shape(ctx, "circle", { cx: xOf(v), cy: yMark, r: Math.max(4, Math.round(r * 0.4)), cls: `dg-tl-dot mk-${role}${dashed}`, key: `mk:${m.id}:dot:${v}` })
    if (m.span === "plan") {
      shape(ctx, "circle", { cx: from, cy: yMark, r: Math.round(r * 0.6), cls: `dg-tl-from st-${role}${dashed}`, key: `mk:${m.id}:from` })
      const top = yMark - r - arc
      shape(ctx, "path", { d: `M${from} ${yMark - r * 0.6} Q${(from + a) / 2} ${top - arc * 0.6} ${a - 2} ${yMark - r - 3}`, cls: `dg-tl-arc st-${role}${dashed}`, key: `mk:${m.id}:arc` })
      arrowhead(ctx, { x: a, y: yMark - r + 1, angle: 62 }, "dg-arrowhead dg-tl-head").key = `mk:${m.id}:head`
    }
    shape(ctx, "marker", { shape: shapeOf(ctx, select ? "muted" : role), x: a - r, y: yMark - r, w: 2 * r, h: 2 * r, cls: `mk-${select ? "muted" : role} dg-tl-mark${dashed}`, key: `mk:${m.id}` })
    if (select && set === "marks") {
      const sz = Math.max(2 * r + 8, 28)
      shape(ctx, "rect", { x: lead - sz / 2, y: yMark - sz / 2, w: tail - lead + sz, h: sz, r: 6, cls: "dg-tl-hit", key: `mk:${m.id}:target`, target: `t${i + 1}` })
    }
    let bottom = yMark + r + 4
    if (!select) {
      const cx = (lead + tail) / 2
      const tx = Math.max(6, Math.min(cx - textW / 2, W - 6 - textW))
      label(ctx, plain(say), tx, y, { anchor: "start", maxW: W - 12, cls: `dg-tl-text dg-tl-plate role-${m.role ?? "muted"}`, role: m.role, lang: LANG_CODE[m.text_en ? "text_en" : "text_es"], key: `mk:${m.id}:text` })
      const note = m.uncertain ? `${plain(m.label_it)} (${TEXT.mark_uncertain})` : plain(m.label_it)
      const nw = Math.ceil(ctx.measure(note, f, Math.round(W * 0.42)).w)
      const nh = ctx.measure(note, f, Math.round(W * 0.42)).h
      const right = tail + r + 10
      const left = lead - r - 10 - nw
      if (right + nw <= W - 6 || left >= 6) bottom = Math.max(bottom, yMark - r + nh + 4)
      if (right + nw <= W - 6) label(ctx, note, right, yMark - r, { anchor: "start", maxW: Math.round(W * 0.42), cls: "dg-tl-question dg-plate", key: `mk:${m.id}:q` })
      else if (left >= 6) label(ctx, note, left, yMark - r, { anchor: "start", maxW: Math.round(W * 0.42), cls: "dg-tl-question dg-plate", key: `mk:${m.id}:q` })
      else {
        label(ctx, note, Math.max(6, Math.min(cx - nw / 2, W - 6 - nw)), yMark + r + 4, { anchor: "start", maxW: Math.round(W * 0.42), cls: "dg-tl-question dg-plate", key: `mk:${m.id}:q` })
        bottom = yMark + r + 4 + nh
      }
    }
    y = Math.max(bottom, yMark + r + 4) + 10
  }
  // the dashed line of "adesso", behind the rows
  ctx.shapes.splice(0, 0, { kind: "line", x1: nowX, y1: axisY, x2: nowX, y2: y - 4, cls: "dg-tl-nowline", key: "nowline" })
  if (!select) y = legendRow(ctx, roles, y)
  return { bottom: y + 2, hits: [], live: null }
}

