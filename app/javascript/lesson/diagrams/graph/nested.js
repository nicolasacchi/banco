// nested (WAVE2 2.1, biology.md 2.5; T4b, D-312): "is made of", drawn as boxes inside boxes. `levels` go from the inside out (3 to 6); the outermost box
// is the whole figure, each level inside the one after it, every box with its name and, under it, its example; `inside` is a dashed box inside the
// innermost level (the organelles inside a cell: not a level). A state's `focus` lights one level (a thicker outline and a tint, its name marked: never
// colour alone). The same picture at every width: on a phone the boxes are nested with smaller margins, so it reads as an indented outline with frames.
// Select mode (L3): the names are gone, the examples stay, each level's header is a neutral zone; the stored ids are the level ids, outermost first.
// The Ruby twin is Lessons::Diagrams::Nested (the same checks in the same order); both run test/fixtures/diagrams/types/nested.json.
import schema from "lesson/diagram_schemas/nested"
import { effectiveState, finish, label, listIt, shape, stateCount, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const type = "nested"
export { schema }

const LABEL_WORDS = 6

// ---- semantics (the same checks, in the same order, as Lessons::Diagrams::Nested) ----------------------------------------------------------

function staticProblem(data) {
  const levels = data.levels
  for (let i = 0; i < levels.length; i++) {
    const lv = levels[i]
    if (levels.findIndex((x) => x.id === lv.id) !== i) return { path: `/levels/${i}/id`, message: `the id ${lv.id} is used twice` }
    if (words(lv.label_it) > LABEL_WORDS) return { path: `/levels/${i}/label_it`, message: `a label has ${words(lv.label_it)} words (at most ${LABEL_WORDS})` }
    if (levels.findIndex((x) => x.label_it.trim().toLowerCase() === lv.label_it.trim().toLowerCase()) !== i) return { path: `/levels/${i}/label_it`, message: `two levels are called ${lv.label_it}` }
  }
  if (data.inside && words(data.inside.label_it) > LABEL_WORDS) return { path: "/inside/label_it", message: `a label has ${words(data.inside.label_it)} words (at most ${LABEL_WORDS})` }
  return null
}

function stateProblem(eff, path, data) {
  if (eff.focus !== undefined && !data.levels.some((l) => l.id === eff.focus)) return { path: `${path}/focus`, message: `${eff.focus} is not the id of a level` }
  return null
}

export function semantic(data) {
  const top = staticProblem(data)
  if (top) return top
  const count = stateCount(data)
  for (let i = 0; i < count; i++) {
    const found = stateProblem(effectiveState(data, i), data.states?.length ? `/states/${i}` : "", data)
    if (found) return found
  }
  return null
}

// ---- layout -----------------------------------------------------------------------------------------------------------------------------

// A label measured in its own classes (a bold name is wider than the plain text label() measures): its box is the one the page draws.
function say(ctx, text, x, y, opts = {}) {
  const px = Math.max(opts.px ?? ctx.fontPx, ctx.fontPx)
  const m = ctx.measure(text, px, opts.maxW, opts.cls ?? "")
  const item = label(ctx, text, x, y, opts)
  const w = Math.ceil(Math.min(m.w, opts.maxW ?? m.w))
  const h = Math.ceil(m.h)
  if (w > item.w) {
    if (item.anchor === "middle") item.x = Math.round(x - w / 2)
    else if (item.anchor === "end") item.x = Math.round(x - w)
    item.w = w
  }
  if (h > item.h) {
    if ((opts.valign ?? "top") === "middle") item.y = Math.round(y - h / 2)
    else if (opts.valign === "bottom") item.y = Math.round(y - h)
    item.h = h
  }
  if (opts.maxW && h > ctx.lineH) item.wrap = true
  return item
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const select = ctx.mode === "select"
  const F = ctx.fontPx
  const W = ctx.width
  const outer = [...data.levels].reverse() // drawn from the outside in: the reading order
  const n = outer.length
  const minInner = Math.max(170, Math.round(F * 8.5))
  // the margin between a box and the next one inside it: as wide as the text size asks, smaller on a narrow page
  const d = Math.max(6, Math.min(Math.round(F * 1.1), Math.floor((W - 4 - minInner) / (2 * n))))
  const pad = Math.max(6, Math.round(F * 0.4))
  const targets = []
  const boxes = []
  let y = 2
  // the headers, from the outside in
  for (let i = 0; i < n; i++) {
    const lv = outer[i]
    const x = 2 + i * d
    const w = W - 4 - 2 * i * d
    const focus = !select && eff.focus === lv.id
    const textW = w - 2 * pad
    let hy = y + pad
    const top = y
    let exX = x + pad
    let exW = textW
    if (!select) {
      const name = say(ctx, lv.label_it, x + pad, hy, { anchor: "start", maxW: textW, cls: `dg-nname${focus ? " dg-nname-focus" : ""}`, key: `lv:${lv.id}:name` })
      // the example on the name's line when both fit on one line, else under it
      const room = textW - name.w - Math.round(F * 0.8)
      if (lv.example_it && !name.wrap && Math.ceil(ctx.measure(lv.example_it, F).w) <= room) {
        exX = x + pad + name.w + Math.round(F * 0.8)
        exW = room
      } else hy += name.h
    }
    if (lv.example_it) {
      const ex = say(ctx, lv.example_it, exX, hy, { anchor: "start", maxW: exW, cls: "dg-nexample", key: select ? undefined : `lv:${lv.id}:ex` })
      hy += ex.h
    }
    if (select && !lv.example_it) hy += ctx.lineH
    const headerH = hy - top + Math.round(pad / 2)
    boxes.push({ lv, x, y: top, w, headerH, focus })
    if (select) {
      const t = `t${targets.length + 1}`
      const bbox = { x: x + 3, y: top + 3, w: w - 6, h: Math.max(24, headerH - 4) }
      shape(ctx, "rect", { ...bbox, r: 6, cls: "dg-nzone", target: t })
      targets.push({ target: t, bbox })
    }
    y = top + headerH
  }
  // the room inside the innermost box: the dashed `inside`, or a blank band
  const inner = boxes[n - 1]
  let bottom = y + pad
  if (data.inside && !select) {
    const ix = inner.x + pad
    const iw = inner.w - 2 * pad
    const iy = y + Math.round(pad / 2)
    let ty = iy + pad
    const name = say(ctx, data.inside.label_it, ix + pad, ty, { anchor: "start", maxW: iw - 2 * pad, cls: "dg-ninside-name", key: "inside:name" })
    ty += name.h
    if (data.inside.note_it) {
      const note = say(ctx, data.inside.note_it, ix + pad, ty, { anchor: "start", maxW: iw - 2 * pad, cls: "dg-ninside-note", key: "inside:note" })
      ty += note.h
    }
    const ih = ty - iy + pad
    shape(ctx, "rect", { x: ix, y: iy, w: iw, h: ih, r: 10, cls: "dg-ninside" })
    bottom = iy + ih + pad
  } else bottom = y + Math.round(F * 1.2)
  // the boxes, drawn before their text (the labels are HTML over the drawing): each one closes `d` below the next one inside it
  const H = bottom + (n - 1) * d + 2
  const rects = boxes.map((b, i) => ({ x: b.x, y: b.y, w: b.w, h: H - 2 - i * d - b.y, r: Math.max(8, Math.round(F * 0.6) - i), cls: `dg-nbox dg-nbox-${i % 2}${b.focus ? " is-focus" : ""}`, ...(select ? {} : { key: `lv:${b.lv.id}:box` }) }))
  ctx.shapes.unshift(...rects.map((r) => ({ kind: "rect", ...r })))
  const out = finish(ctx, H, { states: stateCount(data), state: ctx.state })
  if (out.error) return out
  if (select) out.targets = targets
  else if (eff.focus) out.live = `In evidenza: ${data.levels.find((l) => l.id === eff.focus).label_it}.`
  return out
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// ---- description, targets, printed --------------------------------------------------------------------------------------------------------

const withExample = (lv) => (lv.example_it ? `${lv.label_it} (${lv.example_it})` : lv.label_it)

function describeState(data, i, ctx) {
  const eff = effectiveState(data, i)
  const outer = [...data.levels].reverse()
  if (ctx?.mode === "select") {
    const ex = outer.filter((l) => l.example_it).map((l) => l.example_it)
    return `Riquadri uno dentro l'altro, senza i nomi: ci sono ${outer.length} riquadri da toccare.${ex.length ? ` Gli esempi, dal più grande al più piccolo: ${listIt(ex)}.` : ""}`
  }
  const out = [`Riquadri uno dentro l'altro, dal più grande al più piccolo: ${listIt(outer.map(withExample))}.`]
  if (data.inside) out.push(`Nel riquadro più piccolo, tratteggiato: ${data.inside.label_it}${data.inside.note_it ? `; ${data.inside.note_it}` : ""}.`)
  if (eff.focus) out.push(`In evidenza: ${data.levels.find((l) => l.id === eff.focus).label_it}.`)
  return out.join(" ")
}

export function describe(data, ctx) {
  if (ctx?.mode === "select") return describeState(data, 0, ctx) // a select check's figure has no states: one neutral sentence
  const single = ctx?.state
  const count = stateCount(data)
  const one = (i) => `${count > 1 ? `Passo ${i + 1}. ${data.states[i]?.op_it ? `${data.states[i].op_it}. ` : ""}` : ""}${describeState(data, i, ctx)}`
  if (single !== undefined || count === 1) return one(Math.min(single ?? 0, count - 1))
  return Array.from({ length: count }, (_, i) => one(i)).join(" ")
}

// The stored ids of set `levels` in reading order: the outermost level first.
export function targetIds(data, set) {
  return set === "levels" ? [...data.levels].reverse().map((l) => l.id) : []
}

// targets(data, set) -> [{ key, bbox, neutral_it }]
export function targets(data, set, opts = {}) {
  const ids = targetIds(data, set)
  if (ids.length === 0) return []
  const scene = layout(data, { width: 360, fontPx: 20, subject: "biology", ...opts, mode: "select", set, state: 0 })
  if (scene.error) return []
  return scene.targets.map((t, i) => ({ key: ids[i], bbox: t.bbox, neutral_it: `Riquadro ${i + 1} di ${ids.length}` }))
}

// Every string the state prints (L4); Ruby's printed() returns the same set.
export function printed(data, state = 0) {
  const out = new Set()
  for (const lv of data.levels) {
    out.add(lv.label_it)
    if (lv.example_it) out.add(lv.example_it)
  }
  if (data.inside) {
    out.add(data.inside.label_it)
    if (data.inside.note_it) out.add(data.inside.note_it)
  }
  const op = data.states?.[state]?.op_it
  if (op) out.add(op)
  return [...out]
}
