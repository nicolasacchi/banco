// register (WAVE2 2.5, computer_science.md 1.3; T9): one type for the n-bit value space, two views.
//   view row   a register of digits, each in its own cell, with weights, groups, a readout that is computed, and bit toggles
//   view ring  every code of 3 or 4 bits on a circle, the unsigned value outside, the signed one inside, a seam, a pointer, arcs
// Everything shown is computed here with lesson/lib/bits (Lessons::Bits is the Ruby twin): weights, readouts, group digits, landings.
// The module draws served values; the only thing it computes in the student's page is what the declared controls change (L5).
import schema from "lesson/diagram_schemas/register"
import * as B from "lesson/lib/bits"
import { clampX, effectiveState, finish, label, listIt, plain, roleInfo, shape, stateCount, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { cellH, digitCell, groupings, grouped, rowPlan, show, sumLine, valueOf, weightAt } from "lesson/diagrams/computing/bits_common"
import { drawRing, ringCodes, ringDescribe, ringPrinted, ringReadout } from "lesson/diagrams/computing/register_ring"

export const type = "register"
export { schema }

const ROW_ONLY = ["value", "weights", "groups", "group_digits", "toggle", "goals", "mark"]
const RING_ONLY = ["cliff", "pointer", "step", "highlight", "moves"]
const HOME = "computer_science"

export const maxOf = (data, key) => Math.max(data[key] ?? 0, ...(data.states ?? []).map((s) => s[key] ?? 0))

// ---- semantics (the same checks, in the same order, as Lessons::Diagrams::Register) -------------------------------------------------

function problems(eff, path) {
  const view = eff.view
  const at = (field) => `${path}/${field}`
  const base = eff.base ?? 2
  const n = eff.width
  if (view === "row") {
    for (const k of RING_ONLY) if (eff[k] !== undefined) return { path: at(k), message: `${k} is for the ring view` }
    if (n > (base === 2 ? 16 : 10)) return { path: at("width"), message: "a register has at most 16 bits, or 10 digits in another base" }
    if (eff.value === undefined) return { path: at("value"), message: "a row needs its value" }
    if (eff.value.length !== n) return { path: at("value"), message: `the value has ${eff.value.length} digits, the register ${n}` }
    try {
      B.read(eff.value, base, false)
    } catch (_error) {
      return { path: at("value"), message: `a digit of the value is not a digit of base ${base}` }
    }
    if (eff.read === "both") return { path: at("read"), message: "read: both is for the ring" }
    if (eff.read === "twos" && base !== 2) return { path: at("read"), message: "two's complement is for base 2" }
    if (eff.group_digits && !eff.groups) return { path: at("group_digits"), message: "group_digits needs groups" }
    if (eff.group_digits && base !== 2) return { path: at("group_digits"), message: "group_digits is for base 2: the hex or octal digit under each group" }
    if (eff.toggle && base !== 2) return { path: at("toggle"), message: "only the bits of a base 2 register can be toggled" }
    if (eff.goals !== undefined && !eff.toggle) return { path: at("goals"), message: "goals need toggle: true" }
    const read = eff.read ?? "none"
    for (let i = 0; i < (eff.goals ?? []).length; i++) {
      const g = eff.goals[i]
      if (read === "none") return { path: at(`goals/${i}`), message: "goals need a readout (read: unsigned or twos)" }
      if (!/^-?\d+$/.test(g) || B.write(g, n, 2, read === "twos") === null) return { path: at(`goals/${i}`), message: `${g} cannot be written in ${n} bits` }
    }
    for (let i = 0; i < (eff.mark ?? []).length; i++) {
      const m = eff.mark[i]
      if (m.at > n) return { path: at(`mark/${i}/at`), message: "a mark points past the last digit" }
      if (words(m.label_it) > 6) return { path: at(`mark/${i}/label_it`), message: "a label has at most 6 words" }
    }
    return null
  }
  // ring
  for (const k of ROW_ONLY) if (eff[k] !== undefined) return { path: at(k), message: `${k} is for the row view` }
  if (eff.base !== undefined && eff.base !== 2) return { path: at("base"), message: "the ring has base 2 codes" }
  if (n !== 3 && n !== 4) return { path: at("width"), message: "the ring has 3 or 4 bits" }
  if ((eff.read ?? "unsigned") === "none") return { path: at("read"), message: "the ring needs unsigned, twos or both" }
  if (eff.pointer !== undefined && eff.pointer.length !== n) return { path: at("pointer"), message: `the pointer is a code of ${n} bits` }
  if (eff.step && eff.pointer === undefined) return { path: at("step"), message: "step needs a pointer" }
  for (let i = 0; i < (eff.highlight ?? []).length; i++) {
    const h = eff.highlight[i]
    if (h.code.length !== n) return { path: at(`highlight/${i}/code`), message: `a code of ${n} bits` }
    if (words(h.label_it) > 6) return { path: at(`highlight/${i}/label_it`), message: "a label has at most 6 words" }
  }
  for (let i = 0; i < (eff.moves ?? []).length; i++) {
    const m = eff.moves[i]
    if (m.from.length !== n) return { path: at(`moves/${i}/from`), message: `a code of ${n} bits` }
    if (words(m.label_it) > 6) return { path: at(`moves/${i}/label_it`), message: "a label has at most 6 words" }
  }
  return null
}

export function semantic(data) {
  const count = stateCount(data)
  for (let i = 0; i < count; i++) {
    const eff = effectiveState(data, i)
    const found = problems(eff, data.states?.length ? `/states/${i}` : "")
    if (found) return found
  }
  return null
}

// ---- what the student has done -----------------------------------------------------------------------------------------------------

// The digits on show: the state's value with the bits the student flipped.
export function digitsNow(eff, ctx) {
  const digits = [...eff.value]
  if (eff.toggle) digits.forEach((d, i) => { if (ctx.controls?.[`bit-${i}`]) digits[i] = d === "1" ? "0" : "1" })
  return digits.join("")
}

// The pointer on show: the state's code moved by the stepper (round the circle).
export function pointerNow(eff, ctx) {
  if (eff.pointer === undefined) return null
  const n = 2 ** eff.width
  const moved = ctx.controls?.pointer ?? 0
  return ((parseInt(eff.pointer, 2) + moved) % n + n) % n
}

const readWord = (read) => (read === "twos" ? "con segno" : "senza segno")

// The readout of a row: [{ word, value }] for the readings the figure shows.
export function rowReadout(eff, digits) {
  const read = eff.read ?? "none"
  if (read === "none") return null
  const twos = read === "twos"
  return { twos, value: valueOf(digits, eff.base ?? 2, twos) }
}

// ---- layout ------------------------------------------------------------------------------------------------------------------------

function roleShape(ctx, role) {
  return roleInfo(ctx.palette, HOME, role)?.shape ?? roleInfo(ctx.palette, ctx.subject, role)?.shape ?? "circle"
}

function weightLabels(ctx, plan, eff, base, twos, n) {
  const f = ctx.fontPx
  const texts = Array.from({ length: n }, (_, i) => show(weightAt(i, n, base, twos)))
  const widest = Math.max(...texts.map((t) => ctx.measure(t, f).w))
  // the lines the labels are staggered over: a number wider than its cell borrows the room of the cells beside it
  const rowsFor = (w) => Math.max(1, Math.ceil((w + 4) / plan.cell))
  if (rowsFor(widest) <= 2) return { texts, rows: rowsFor(widest) }
  // powers when the numbers do not fit: 2^7 instead of 128 (the sign weight keeps its minus)
  const powers = Array.from({ length: n }, (_, i) => `$${twos && i === 0 ? "-" : ""}${base}^{${n - 1 - i}}$`)
  const widestPower = Math.max(...powers.map((t) => ctx.measure(t, f).w))
  return { texts: powers, rows: Math.min(4, rowsFor(widestPower)), powers: true }
}

function buildRow(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const select = ctx.mode === "select"
  const base = eff.base ?? 2
  const n = eff.width
  const digits = digitsNow(eff, ctx)
  const readout = select ? null : rowReadout(eff, digits)
  const twos = eff.read === "twos"
  const weights = eff.weights === true
  const f = ctx.fontPx
  const groups = eff.groups ?? 0
  const plan = rowPlan(ctx, n, groups)
  const lineH = ctx.lineH
  const w = weights ? weightLabels(ctx, plan, eff, base, twos, n) : null
  const markFor = (i) => (select ? undefined : (eff.mark ?? []).find((m) => m.at === i + 1))
  let y = 6
  const controls = {}
  const rowTops = []
  const targets = []
  plan.chunks.forEach(([a, b], r) => {
    // weights over the digits (two staggered lines when a number is wider than its cell)
    if (weights) {
      const top = y
      for (let j = a; j < b; j++) {
        const x = plan.xOf(j) + plan.cell / 2
        const level = (b - 1 - j) % w.rows
        const second = level > 0
        const sign = twos && j === 0
        const ly = top + level * lineH
        clampX(ctx, label(ctx, w.texts[j], x, ly, { cls: `dg-weight${select ? "" : sign ? " role-sign" : " role-weight"}`, role: select ? undefined : sign ? "sign" : "weight" }))
        if (second && w.rows === 2) shape(ctx, "line", { x1: x, y1: ly + lineH - 2, x2: x, y2: top + lineH * 2 + 2, cls: "dg-connector" })
      }
      y += lineH * w.rows + 4
    }
    rowTops.push(y)
    for (let j = a; j < b; j++) {
      const x = plan.xOf(j)
      const sign = !select && twos && j === 0
      const mark = markFor(j)
      const index = targets.length
      const cell = digitCell(ctx, x, y, plan.cell, digits[j], { on: !select && base === 2 && digits[j] === "1", cls: sign ? "dg-sign st-sign" : mark ? `st-${mark.role}` : "", target: select ? `t${index + 1}` : undefined })
      targets.push({ index, j, box: cell })
      if (eff.toggle && !select) {
        const weight = weightAt(j, n, base, twos)
        controls[`bit-${j}`] = { x: cell.x, y: cell.y, w: cell.w, h: cell.h, on: digits[j] === "1", label_it: `Bit di peso ${show(weight)}: ora ${digits[j]}. Tocca per cambiarlo.` }
      }
    }
    y += cellH(ctx, plan.cell) + 4
    // the hex or octal digit under each group
    if (eff.group_digits && groups) {
      const spans = []
      for (let end = b; end > a; end -= groups) spans.unshift([Math.max(a, end - groups), end])
      for (const [start, end] of spans) {
        const chunk = digits.slice(start, end)
        const value = parseInt(chunk, 2)
        const text = groups === 4 ? value.toString(16).toUpperCase() : String(value)
        const cx = (plan.xOf(start) + plan.xOf(end - 1) + plan.cell) / 2
        clampX(ctx, label(ctx, text, cx, y, { cls: "dg-groupdigit" }))
      }
      y += lineH + 2
    }
    // marks: a marker of the role's shape and its word under the digit
    let markRow = false
    for (let j = a; j < b; j++) {
      const mark = markFor(j)
      if (!mark) continue
      const cx = plan.xOf(j) + plan.cell / 2
      shape(ctx, "marker", { shape: roleShape(ctx, mark.role), x: cx - 8, y, w: 16, h: 16, cls: `mk-${mark.role}` })
      if (mark.label_it) clampX(ctx, label(ctx, mark.label_it, cx, y + 18, { cls: `dg-note role-${mark.role}`, role: mark.role }))
      markRow = true
    }
    if (markRow) y += 18 + (( eff.mark ?? []).some((m) => m.label_it) ? lineH : 0) + 2
    y += r < plan.chunks.length - 1 ? 10 : 4
  })
  // the readout
  let live = `Il registro è ${grouped(digits, groups || 4)}.`
  if (readout) {
    const text = `Il registro ${readout.twos ? "con segno " : ""}vale ${show(readout.value)}`
    shape(ctx, "line", { x1: plan.left, y1: y, x2: plan.left + plan.width, y2: y, cls: "dg-rule" })
    y += 8
    const head = label(ctx, text, plan.left + plan.width / 2, y, { cls: "dg-readout-line", maxW: Math.min(plan.width + 20, ctx.width - 8) })
    y += head.h + 2
    live = `${live} ${text}.`
    if (weights && base === 2 && sumLine(digits, twos)) {
      const sum = label(ctx, sumLine(digits, twos), plan.left + plan.width / 2, y, { cls: "dg-sumline", maxW: Math.min(plan.width + 20, ctx.width - 8) })
      y += sum.h + 2
    }
    // the goals of a lab: "Prova a fare ...", a local "Sì" once reached
    if (eff.goals?.length) {
      y += 6
      const reading = readout.value
      const tag = label(ctx, "Prova a fare:", plan.left, y, { anchor: "start", cls: "dg-goaltag" })
      let gx = plan.left + tag.w + 12
      let gy = y
      for (const g of eff.goals) {
        const reached = Number(g) === reading
        const text = reached ? `${show(Number(g))}  Sì` : show(Number(g))
        const m = ctx.measure(text, f)
        const gw = m.w + 22
        if (gx + gw > plan.left + plan.width + 20 && gx > plan.left + tag.w + 12) {
          gx = plan.left
          gy += lineH + 12
        }
        shape(ctx, "rect", { x: gx, y: gy - 2, w: gw, h: lineH + 6, r: 12, cls: `dg-goal${reached ? " dg-reached" : ""}` })
        label(ctx, text, gx + gw / 2, gy + 1, { cls: `dg-goaltext${reached ? " dg-reachedtext" : ""}` })
        gx += gw + 8
      }
      y = gy + lineH + 10
    }
  }
  const out = finish(ctx, y + 4, { states: stateCount(data), state: ctx.state })
  if (!out.error) {
    out.controls = controls
    out.live = live
    out.plan = { cell: plan.cell, per: plan.per, rows: plan.rows }
    if (select) out.targets = targets.map((t) => ({ target: `t${t.index + 1}`, bbox: t.box }))
  }
  return out
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  return eff.view === "ring" ? drawRing(data, ctx) : buildRow(data, ctx)
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// ---- description, controls, targets, printed -------------------------------------------------------------------------------------------

function describeState(data, i, ctx) {
  const eff = effectiveState(data, i)
  if (eff.view === "ring") return ringDescribe(eff, ctx)
  const digits = digitsNow(eff, ctx ?? {})
  const base = eff.base ?? 2
  const n = eff.width
  const bits = [`Un registro di ${n} ${base === 2 ? "bit" : "cifre"} in base ${base}: ${grouped(digits, eff.groups || 4)}.`]
  if (eff.weights) {
    const twos = eff.read === "twos"
    bits.push(`I pesi, da sinistra: ${listIt(Array.from({ length: n }, (_, k) => show(weightAt(k, n, base, twos))))}.`)
  }
  const readout = rowReadout(eff, digits)
  if (readout) {
    bits.push(`Letto ${readout.twos ? "con segno" : "senza segno"} vale ${show(readout.value)}.`)
    if (eff.weights && base === 2 && sumLine(digits, readout.twos)) bits.push(`${sumLine(digits, readout.twos)}.`)
  }
  for (const m of eff.mark ?? []) bits.push(`Il bit ${m.at} è il ${m.label_it ?? "bit segnato"}.`)
  if (eff.toggle) bits.push("Ogni bit si può cambiare con un tocco.")
  if (eff.goals?.length) bits.push(`Prova a fare ${listIt(eff.goals.map((g) => show(Number(g))))}.`)
  return bits.join(" ")
}

export function describe(data, ctx) {
  const single = ctx?.state
  const count = stateCount(data)
  if (single !== undefined || count === 1) {
    const i = Math.min(single ?? 0, count - 1)
    const eff = effectiveState(data, i)
    const op = data.states?.[i]?.op_it
    return `${count > 1 ? `Passo ${i + 1}. ${op ? `${plain(op)}. ` : ""}` : ""}${describeState(data, i, ctx)}`
  }
  return Array.from({ length: count }, (_, i) => `Passo ${i + 1}. ${data.states[i]?.op_it ? `${plain(data.states[i].op_it)}. ` : ""}${describeState(data, i, ctx)}`).join(" ")
}

export function controls(data) {
  const list = []
  if (data.view === "row" && data.toggle) {
    for (let i = 0; i < maxOf(data, "width"); i++) list.push({ id: `bit-${i}`, kind: "toggle", label_it: "Bit del registro" })
  }
  if (data.view === "ring" && data.step) {
    const n = 2 ** maxOf(data, "width")
    list.push({ id: "pointer", kind: "stepper", range: [-(n - 1), n - 1], initial: 0, less_it: "−1", more_it: "+1", label_it: "Muovi il puntatore" })
  }
  return list
}

// The stored ids of a select set: the bits of a row ("b1" is the leftmost), the codes of a ring (the code itself, from 0 up).
export function targetIds(data, set) {
  const eff = effectiveState(data, 0)
  if (set === "bits" && eff.view === "row") return Array.from({ length: eff.width }, (_, i) => `b${i + 1}`)
  if (set === "codes" && eff.view === "ring") return ringCodes(eff.width)
  return []
}

// targets(data, set) -> [{ key, bbox, neutral_it }] in reading order (the order of the layout in mode "select"; cells of a row from the
// top left, codes of a ring clockwise from the top). The optional third argument is the layout context (width, fontPx, measure).
export function targets(data, set, opts = {}) {
  const ids = targetIds(data, set)
  if (ids.length === 0) return []
  const scene = layout(data, { width: 360, fontPx: 20, subject: HOME, ...opts, mode: "select" })
  if (scene.error) return []
  const noun = set === "bits" ? "Bit" : "Codice"
  return scene.targets.map((t, i) => ({ key: ids[i], bbox: t.bbox, neutral_it: `${noun} ${i + 1} di ${ids.length}` }))
}

// Every string the state prints (L4): the digits and their groups, the weights, the group digits, the readouts, the goals, the labels.
export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  if (eff.view === "ring") return ringPrinted(eff)
  const out = new Set()
  const base = eff.base ?? 2
  const n = eff.width
  const twos = eff.read === "twos"
  for (const form of groupings(eff.value, eff.groups || 4)) out.add(form)
  if (eff.weights) for (let i = 0; i < n; i++) out.add(show(weightAt(i, n, base, twos)))
  if (eff.group_digits && eff.groups) {
    for (let end = n; end > 0; end -= eff.groups) {
      const value = parseInt(eff.value.slice(Math.max(0, end - eff.groups), end), 2)
      out.add(eff.groups === 4 ? value.toString(16).toUpperCase() : String(value))
    }
  }
  const readout = rowReadout(eff, eff.value)
  if (readout) {
    out.add(show(readout.value))
    if (eff.weights && base === 2 && sumLine(eff.value, twos)) out.add(sumLine(eff.value, twos))
  }
  for (const g of eff.goals ?? []) out.add(show(Number(g)))
  for (const m of eff.mark ?? []) if (m.label_it) out.add(m.label_it)
  if (data.states?.[state]?.op_it) out.add(data.states[state].op_it)
  return [...out]
}

