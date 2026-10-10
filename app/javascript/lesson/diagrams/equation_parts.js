// equation_parts (A7): the anatomy of an equation. The parts in order as chips (the numbers and the
// unknown in their role colour), a label above a chip, and brackets under whole parts with their label.
import { checkTex } from "items/markup_parser"
import { effectiveState, finish, label, listIt, plain, shape, stackLabels, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export function semantic(data, ctx) {
  const parts = data.parts
  for (let i = 0; i < parts.length; i++) {
    try {
      checkTex(parts[i].tex)
    } catch (_error) {
      return { path: `/parts/${i}/tex`, message: "a command that is not allowed in a formula" }
    }
  }
  if (ctx.validateTex && !ctx.validateTex(parts.map((p) => p.tex).join(" "))) return { path: "/parts", message: "the parts joined are not a valid formula" }
  const n = stateCount(data)
  for (let j = -1; j < (data.states ? n : 0); j++) {
    const brackets = j < 0 ? data.brackets ?? [] : data.states[j].brackets ?? []
    const base = j < 0 ? "/brackets" : `/states/${j}/brackets`
    for (let i = 0; i < brackets.length; i++) {
      const b = brackets[i]
      if (b.to >= parts.length) return { path: `${base}/${i}/to`, message: "a bracket covers parts that exist" }
      if (b.from > b.to) return { path: `${base}/${i}`, message: "a bracket runs from a part to a later one" }
    }
  }
  return null
}

export const states = stateCount

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const W = ctx.width
  // the equation is the picture: big chips (the prototype's sizes), smaller only when the figure is too narrow for them
  let f = ctx.fontPx
  let chipH
  let gap
  let widths
  let total = Infinity
  let big = f
  for (const scale of [1.9, 1.6, 1.3, 1.0]) {
    big = Math.round(ctx.fontPx * scale)
    chipH = Math.round(big * 1.8)
    gap = Math.round(big * 0.3)
    widths = data.parts.map((p) => Math.max(Math.round(big * 1.5), Math.ceil(ctx.measure(p.tex.includes("$") ? p.tex : `$${p.tex}$`, big).w) + 2 * ctx.pad))
    total = widths.reduce((a, b) => a + b, 0) + gap * (widths.length - 1)
    if (total <= W - 8) break
  }
  f = ctx.fontPx
  if (total > W - 8) return { error: { path: "/parts", message: "the formula is wider than the figure", code: "E-DIAGRAM-LAYOUT" } }
  const x0 = Math.round((W - total) / 2)
  const xs = []
  let x = x0
  widths.forEach((w) => {
    xs.push(x)
    x += w + gap
  })

  // labels above the chips, in rows if they would touch
  const withLabel = data.parts.map((p, i) => ({ p, i })).filter(({ p }) => p.label_it)
  const probeRows = (() => {
    // how many rows the upper labels need: run the stacking on a scratch context
    const scratch = { ...ctx, labels: [], shapes: [] }
    return stackLabels(scratch, withLabel.map(({ p, i }) => ({ text: p.label_it, cx: xs[i] + widths[i] / 2, cls: "dg-note" })), 0, -1)
  })()
  const topH = withLabel.length ? probeRows + 8 : 6
  const chipTop = topH
  data.parts.forEach((p, i) => {
    shape(ctx, "rect", { x: xs[i], y: chipTop, w: widths[i], h: chipH, r: 10, cls: `dg-chip tn-${p.role} fl-${p.role}` })
    label(ctx, p.tex.includes("$") ? p.tex : `$${p.tex}$`, xs[i] + widths[i] / 2, chipTop + chipH / 2, { valign: "middle", cls: `role-${p.role} dg-chiptext`, role: p.role, px: big })
  })
  if (withLabel.length) {
    stackLabels(ctx, withLabel.map(({ p, i }) => ({ text: p.label_it, cx: xs[i] + widths[i] / 2, cls: `dg-note role-${p.role}`, connectFrom: chipTop - 2, role: p.role })), chipTop - 6, -1)
  }

  // brackets under the chips: one level per overlap, then their labels
  const brackets = (eff.brackets ?? []).map((b) => ({ ...b }))
  const levels = []
  brackets.forEach((b) => {
    const a = xs[b.from]
    const z = xs[b.to] + widths[b.to]
    let level = 0
    while (levels.some((l) => l.level === level && a < l.z && l.a < z)) level += 1
    levels.push({ a, z, level })
    b.level = level
  })
  const maxLevel = brackets.reduce((m, b) => Math.max(m, b.level), 0)
  const bracketBase = chipTop + chipH + 6
  brackets.forEach((b) => {
    const a = xs[b.from] + 2
    const z = xs[b.to] + widths[b.to] - 2
    const y = bracketBase + b.level * 12
    shape(ctx, "path", { d: `M${a},${y - 6} V${y} H${z} V${y - 6}`, cls: `dg-bracket st-${b.role ?? "muted"}` })
  })
  const labelY = bracketBase + (maxLevel + 1) * 12 + 4
  const used = brackets.length
    ? stackLabels(ctx, brackets.map((b) => ({ text: b.label_it, cx: (xs[b.from] + xs[b.to] + widths[b.to]) / 2, cls: `dg-note role-${b.role ?? "muted"}`, role: b.role, connectFrom: bracketBase + b.level * 12 })), labelY, 1)
    : 0
  const height = brackets.length ? labelY + used : chipTop + chipH + 8
  return finish(ctx, height, { states: stateCount(data), state: ctx.state })
}

export function describe(data) {
  const sentence = (e, prefix = "") => {
    const parts = data.parts.map((p) => `${plain(p.tex)}${p.label_it ? ` (${plain(p.label_it)})` : ""}`)
    const brackets = (e.brackets ?? []).map((b) => `${plain(b.label_it)}: dal pezzo ${b.from + 1} al pezzo ${b.to + 1}`)
    return `${prefix}L'equazione ha questi pezzi, in ordine: ${listIt(parts)}.${brackets.length ? ` Le parentesi indicano: ${listIt(brackets)}.` : ""}`
  }
  const n = stateCount(data)
  const out = []
  for (let i = 0; i < n; i++) out.push(sentence(effectiveState(data, i), n > 1 ? `Passo ${i + 1}. ` : ""))
  return out.join(" ")
}

export const layout = (data, opts) => run(data, opts, { semantic, build })
