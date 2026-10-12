// column_calc (WAVE2 2.5, computer_science.md 1.3; T9): an addition, subtraction or multiplication in columns inside a register of `width`
// digits. Our code computes the carries, the borrows (the borrow across zeros drawn as the digits it changes), the partial products and the
// result (lesson/lib/bits; Lessons::Bits is the Ruby twin): an agent cannot write a wrong sum. What does not fit the register falls out
// to the left, drawn dashed in the role carry. `reveal: columns` shows the work one column at a time from the right (one partial product at
// a time for a multiplication).
import schema from "lesson/diagram_schemas/column_calc"
import * as B from "lesson/lib/bits"
import { clampX, effectiveState, finish, label, plain, shape, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { cellH, groupings, MINUS, show } from "lesson/diagrams/computing/bits_common"

export const type = "column_calc"
export { schema }

const OP_SIGN = { add: "+", sub: MINUS, mul: "×" }
const OP_WORD = { add: "Somma", sub: "Sottrazione", mul: "Moltiplicazione" }
const ALPHABET = "0123456789ABCDEF"

// ---- semantics (the same checks, in the same order, as Lessons::Diagrams::ColumnCalc) --------------------------------------------

function problems(eff, path) {
  const base = eff.base
  const at = (field) => `${path}/${field}`
  if (eff.width > (base === 2 ? 16 : 10)) return { path: at("width"), message: "a register has at most 16 bits, or 10 digits in another base" }
  for (const key of ["a", "b"]) {
    const text = eff[key]
    if (![...text].every((ch) => ALPHABET.indexOf(ch) >= 0 && ALPHABET.indexOf(ch) < base)) return { path: at(key), message: `a digit of ${key} is not a digit of base ${base}` }
    if (text.length > eff.width) return { path: at(key), message: `${key} has more digits than the register (${eff.width})` }
  }
  if (eff.op === "mul" && eff.b.length > 4) return { path: at("b"), message: "the multiplier has at most 4 digits" }
  if (eff.read === "twos" && base !== 2) return { path: at("read"), message: "two's complement is for base 2" }
  return null
}

export function semantic(data) {
  const count = stateCount(data)
  for (let i = 0; i < count; i++) {
    const found = problems(effectiveState(data, i), data.states?.length ? `/states/${i}` : "")
    if (found) return found
  }
  return null
}

// ---- the work, computed ------------------------------------------------------------------------------------------------------------

const pad = (text, width) => text.padStart(width, "0")

// Everything the figure shows, from the digits: the library's columns, the outside digits and the steps of the reveal.
export function work(eff) {
  const { base, op, width } = eff
  const a = pad(eff.a, width)
  const b = pad(eff.b, width)
  if (op === "add") {
    const r = B.add(a, b, width, base)
    return { op, base, width, a, b, result: r.digits, carries: r.carries, carryOut: r.carry_out, extra: r.carry_out ? 1 : 0, steps: width }
  }
  if (op === "sub") {
    const r = B.sub(a, b, width, base)
    // the digit of a after the borrows: it gives one (-1) when the column on its right borrowed, and takes `base` when it borrows itself
    const adjusted = [...a].map((ch, i) => ALPHABET.indexOf(ch) - (i + 1 < width ? r.borrows[i + 1] : 0) + base * r.borrows[i])
    return { op, base, width, a, b, result: r.digits, borrows: r.borrows, adjusted, borrowOut: r.borrows[0], extra: r.borrows[0] ? 1 : 0, steps: width }
  }
  const r = B.mul(a, eff.b, width, base)
  return { op, base, width, a, b: eff.b, result: r.digits, full: r.full, partials: r.partials, overflow: r.overflow, extra: Math.max(0, ...r.partials.map((p) => p.digits.length - width), r.full.length - width), steps: r.partials.length + 1 }
}

// How many steps are on show: all, or what the stepper has reached.
export function shown(eff, ctx, w) {
  if (eff.reveal !== "columns" || ctx.mode === "print" || ctx.mode === "select") return w.steps
  return Math.max(0, Math.min(w.steps, ctx.controls?.reveal ?? 0))
}

// The sentence that tells column number `step` (1-based from the right) of an addition or a subtraction.
function columnSentence(w, step) {
  const i = w.width - step
  const digit = (text) => ALPHABET.indexOf(text[i])
  const res = w.result[i]
  if (w.op === "add") {
    const carryIn = i + 1 < w.width ? w.carries[i + 1] : 0
    const sum = digit(w.a) + digit(w.b) + carryIn
    const inBase = w.base === 10 || sum < w.base ? "" : `, cioè ${B.write(sum, 2, w.base) ?? sum} in base ${w.base}`
    return `Colonna ${step}: ${w.a[i]} più ${w.b[i]}${carryIn ? " più il riporto 1" : ""} fa ${sum}${inBase}${sum >= w.base ? `. Scrivo ${res} e riporto 1.` : "."}`
  }
  const own = w.borrows[i]
  const lent = i + 1 < w.width ? w.borrows[i + 1] : 0
  const from = digit(w.a) - lent
  const parts = [`Colonna ${step}: la cifra è ${w.a[i]}.`]
  if (lent && own) parts.push(`Ho dato 1 alla colonna accanto e prendo ${w.base} dalla colonna a sinistra: ora vale ${from + w.base}.`)
  else if (lent) parts.push(`Ho dato 1 alla colonna accanto: ora vale ${from}.`)
  else if (own) parts.push(`${from} è meno di ${w.b[i]}: prendo ${w.base} dalla colonna a sinistra. Ora vale ${from + w.base}.`)
  parts.push(`${from + w.base * own} meno ${w.b[i]} fa ${res}.`)
  return parts.join(" ")
}

function stepSentence(w, step) {
  if (w.op === "mul") {
    if (step <= w.partials.length) {
      const p = w.partials[step - 1]
      return `Cifra ${step} di b, che è ${p.digit}: ${w.a} per ${p.digit}${p.shift ? `, spostato di ${p.shift} ${p.shift === 1 ? "posto" : "posti"}` : ""}.`
    }
    return `Somma dei prodotti: ${w.full}${w.overflow ? `, ma il registro tiene ${w.width} cifre: ${w.result}` : ""}.`
  }
  return columnSentence(w, step)
}

// ---- layout ------------------------------------------------------------------------------------------------------------------------

function plan(ctx, w, groups) {
  const columns = w.extra + w.width
  const opW = 1
  const total = columns + opW
  const gapW = groups ? Math.round(ctx.fontPx * 0.4) : 0
  const gaps = groups ? Math.floor((w.width - 1) / groups) : 0
  const avail = ctx.width - 8
  const cell = Math.min(52, Math.floor((avail - gaps * gapW) / total))
  const digitW = ctx.measure("0", ctx.fontPx).w
  const x0 = Math.round((ctx.width - (total * cell + gaps * gapW)) / 2)
  // x of the column c (0 = the op column, 1.. = outside then register columns); gaps every `groups` columns from the right of the register
  const xOf = (c) => {
    let g = 0
    if (groups) for (let r = 1; r <= c - 1 - w.extra; r++) if ((w.width - r) % groups === 0) g += 1
    return x0 + c * cell + g * gapW
  }
  return { cell, xOf, fits: cell >= digitW + 6, total, x0, width: total * cell + gaps * gapW }
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const select = ctx.mode === "select"
  const w = work(eff)
  const k = shown(eff, ctx, w)
  const all = k >= w.steps
  const groups = w.base === 2 && w.width > 4 ? 4 : 0
  const p = plan(ctx, w, groups)
  if (!p.fits) return { error: { path: "", message: "the columns do not fit this width: the digits would touch", code: "E-DIAGRAM-LAYOUT" } }
  const f = ctx.fontPx
  const lineH = ctx.lineH
  const cell = p.cell
  const rowH = cellH(ctx, cell)
  const targets = []
  const target = () => {
    if (!select) return undefined
    const t = `t${targets.length + 1}`
    return t
  }
  // the column of register digit i (0 = leftmost) sits at column index extra + 1 + i
  const colOf = (i) => w.extra + 1 + i
  let y = 6
  const row = (text, rowKey, { dim = false, startCol = 0, role, hideBefore = 0, show: visible } = {}) => {
    const top = y
    for (let i = 0; i < w.width; i++) {
      const x = p.xOf(colOf(i))
      if (visible && !visible(i)) {
        shape(ctx, "rect", { x, y: top, w: cell, h: rowH, r: 6, cls: "dg-bit dg-empty" })
        continue
      }
      const t = target()
      const c = shape(ctx, "rect", { x, y: top, w: cell, h: rowH, r: 6, cls: `dg-bit${text[i] === "1" && w.base === 2 && !select ? " dg-on" : ""}${dim && i > w.width - 1 - startCol ? "" : ""}` })
      if (t) {
        c.target = t
        targets.push({ target: t, bbox: { x, y: top, w: cell, h: rowH } })
      }
      label(ctx, text[i], x + cell / 2, top + rowH / 2, { valign: "middle", cls: `dg-digit${role ? ` role-${role}` : ""}` })
    }
    y += rowH + 4
    return top
  }
  // outside digits: dashed cells at the left of a row, in the role carry
  const outside = (digits, top, visible = true) => {
    for (let c = 0; c < w.extra; c++) {
      const x = p.xOf(1 + c)
      const d = digits[c]
      shape(ctx, "rect", { x, y: top, w: cell, h: rowH, r: 6, cls: `dg-bit dg-outside${select ? "" : " st-carry"}${d && visible ? "" : " dg-empty"}` })
      if (d && visible) label(ctx, d, x + cell / 2, top + rowH / 2, { valign: "middle", cls: `dg-digit${select ? "" : " role-carry"}` })
    }
  }
  const opSign = (top) => label(ctx, OP_SIGN[w.op], p.xOf(0) + cell / 2, top + rowH / 2, { valign: "middle", cls: "dg-opsign" })
  let anyCarry = false

  if (w.op === "add") {
    // carries over the columns already worked (the carry into column i is written over it)
    const top = y
    const visible = (i) => w.width - i <= k
    // the carry into column i is made by the column on its right: it appears with that column
    for (let i = 0; i < w.width; i++) {
      if (select || !w.carries[i] || w.width - i > k + 1) continue
      const x = p.xOf(colOf(i))
      shape(ctx, "rect", { x, y: top, w: cell, h: rowH, r: 6, cls: "dg-bit dg-chip st-carry" })
      label(ctx, "1", x + cell / 2, top + rowH / 2, { valign: "middle", cls: "dg-digit role-carry" })
      anyCarry = true
    }
    y += rowH + 4
    row(w.a)
    const bTop = row(w.b)
    opSign(bTop)
    shape(ctx, "line", { x1: p.xOf(0), y1: y, x2: p.xOf(columnsEnd(w)) + cell, y2: y, cls: "dg-rule" })
    y += 6
    const rTop = row(w.result, "r", { show: (i) => select || visible(i) })
    if (w.extra) {
      outside(["1"], rTop, select || all)
      if (all && !select) anyCarry = true
    }
  } else if (w.op === "sub") {
    const top = y
    const visibleOwn = (i) => w.width - i <= k
    const visibleChip = (i) => visibleOwn(i) || (i + 1 < w.width && w.borrows[i + 1] === 1 && w.width - (i + 1) <= k)
    for (let i = 0; i < w.width; i++) {
      if (select || w.adjusted[i] === ALPHABET.indexOf(w.a[i]) || !visibleChip(i)) continue
      const x = p.xOf(colOf(i))
      shape(ctx, "rect", { x, y: top, w: cell, h: rowH, r: 6, cls: "dg-bit dg-chip st-carry" })
      label(ctx, ALPHABET[w.adjusted[i]] ?? String(w.adjusted[i]), x + cell / 2, top + rowH / 2, { valign: "middle", cls: "dg-digit role-carry" })
      anyCarry = true
    }
    if (w.extra && !select && visibleOwn(0)) {
      const x = p.xOf(1)
      shape(ctx, "rect", { x, y: top, w: cell, h: rowH, r: 6, cls: "dg-bit dg-chip dg-outside st-carry" })
      label(ctx, "−1", x + cell / 2, top + rowH / 2, { valign: "middle", cls: "dg-digit role-carry" })
      anyCarry = true
    }
    y += rowH + 4
    const aTop = row(w.a)
    // the digits a borrow changed are struck through
    for (let i = 0; i < w.width && !select; i++) {
      if (w.adjusted[i] !== ALPHABET.indexOf(w.a[i]) && visibleChip(i)) {
        const x = p.xOf(colOf(i))
        shape(ctx, "line", { x1: x + cell * 0.22, y1: aTop + rowH * 0.8, x2: x + cell * 0.78, y2: aTop + rowH * 0.2, cls: "dg-strike" })
      }
    }
    const bTop = row(w.b)
    opSign(bTop)
    shape(ctx, "line", { x1: p.xOf(0), y1: y, x2: p.xOf(columnsEnd(w)) + cell, y2: y, cls: "dg-rule" })
    y += 6
    row(w.result, "r", { show: (i) => select || visibleOwn(i) })
  } else {
    row(w.a)
    const bTop = row(pad(w.b, w.width))
    opSign(bTop)
    shape(ctx, "line", { x1: p.xOf(0), y1: y, x2: p.xOf(columnsEnd(w)) + cell, y2: y, cls: "dg-rule" })
    y += 6
    // partial products: shifted to the left by their place, the digits beyond the register outside
    w.partials.forEach((part, idx) => {
      const on = select || idx < k
      const top = y
      const digits = part.digits.padStart(w.width + w.extra, "0")
      outside([...digits.slice(0, w.extra)], top, on)
      for (let i = 0; i < w.width; i++) {
        const x = p.xOf(colOf(i))
        const d = digits[w.extra + i]
        const t = on && select ? target() : undefined
        const c = shape(ctx, "rect", { x, y: top, w: cell, h: rowH, r: 6, cls: `dg-bit${on ? "" : " dg-empty"}` })
        if (t) {
          c.target = t
          targets.push({ target: t, bbox: { x, y: top, w: cell, h: rowH } })
        }
        if (on) label(ctx, d, x + cell / 2, top + rowH / 2, { valign: "middle", cls: `dg-digit${i >= w.width - part.shift ? " dg-dim" : ""}` })
      }
      y += rowH + 4
    })
    shape(ctx, "line", { x1: p.xOf(0), y1: y, x2: p.xOf(columnsEnd(w)) + cell, y2: y, cls: "dg-rule" })
    y += 6
    const top = row(w.result, "r", { show: (i) => select || all })
    if (w.extra) outside([...w.full.slice(0, w.extra)], top, select || all)
    anyCarry = w.extra > 0 && all
  }

  // what the step says, the legend, the values
  let live = ""
  if (!select) {
    if (w.steps > 0 && k > 0) {
      const text = stepSentence(w, k)
      live = text
      if (eff.reveal === "columns") {
        const status = label(ctx, text, ctx.width / 2, y + 8, { cls: "dg-stepline", maxW: ctx.width - 16 })
        clampX(ctx, status)
        y += status.h + 14
      }
    } else if (eff.reveal === "columns") {
      const status = label(ctx, w.op === "mul" ? "Tocca Avanti: appare un prodotto." : "Tocca Avanti: appare una colonna.", ctx.width / 2, y + 8, { cls: "dg-stepline", maxW: ctx.width - 16 })
      clampX(ctx, status)
      y += status.h + 14
    }
    if (anyCarry) {
      const word = w.op === "sub" ? "cifra cambiata dal prestito, o il prestito che esce" : "riporto, o cifra che esce dal registro"
      shape(ctx, "rect", { x: 8, y: y + 3, w: 16, h: 16, r: 4, cls: "dg-bit dg-sample st-carry" })
      const item = label(ctx, word, 32, y, { anchor: "start", cls: "dg-legend role-carry", maxW: ctx.width - 40 })
      y += item.h + 6
    }
    if (eff.read && eff.read !== "none") {
      const twos = eff.read === "twos"
      const lines = [["Primo numero", w.a], ["Secondo numero", w.op === "mul" ? pad(w.b, w.width) : w.b]]
      if (all) lines.push(["Risultato", w.result])
      for (const [name, digits] of lines) {
        const item = label(ctx, `${name} vale ${show(B.read(digits, w.base, twos))}`, 8, y, { anchor: "start", cls: "dg-readout-line", maxW: ctx.width - 16 })
        y += item.h + 2
      }
    }
  }
  const out = finish(ctx, y + 4, { states: stateCount(data), state: ctx.state })
  if (!out.error) {
    out.controls = {}
    out.live = live
    if (select) out.targets = targets
  }
  return out
}

const columnsEnd = (w) => w.extra + w.width

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// ---- description, controls, targets, printed -------------------------------------------------------------------------------------

function describeState(eff, ctx) {
  const w = work(eff)
  const k = shown(eff, ctx ?? {}, w)
  const all = k >= w.steps
  const g = (s) => (w.base === 2 && w.width > 4 ? s.replace(/(?=(\d{4})+$)/g, " ").trim() : s)
  const bits = [`${OP_WORD[w.op]} in colonna, in base ${w.base}, su ${w.width} cifre: ${g(w.a)} ${w.op === "add" ? "più" : w.op === "sub" ? "meno" : "per"} ${g(w.op === "mul" ? pad(w.b, w.width) : w.b)}.`]
  if (eff.reveal === "columns" && !all) {
    if (k === 0) bits.push(w.op === "mul" ? "Il lavoro non è ancora cominciato: appare un prodotto alla volta." : "Il lavoro non è ancora cominciato: appare una colonna alla volta, da destra.")
    for (let s = 1; s <= k; s++) bits.push(stepSentence(w, s))
    return bits.join(" ")
  }
  if (eff.reveal === "columns") for (let s = 1; s <= w.steps; s++) bits.push(stepSentence(w, s))
  if (w.op === "add" && w.carryOut) bits.push("Il riporto dell'ultima colonna esce dal registro.")
  if (w.op === "sub" && w.borrowOut) bits.push("Il prestito dell'ultima colonna esce dal registro: il risultato torna da capo.")
  if (w.op === "mul" && w.overflow) bits.push(`Il prodotto intero è ${w.full}, ma il registro tiene ${w.width} cifre.`)
  bits.push(`Il risultato nel registro è ${g(w.result)}.`)
  if (eff.read && eff.read !== "none") {
    const twos = eff.read === "twos"
    bits.push(`Letti ${twos ? "con segno" : "senza segno"} i numeri valgono ${show(B.read(w.a, w.base, twos))}, ${show(B.read(pad(w.b, w.width), w.base, twos))} e ${show(B.read(w.result, w.base, twos))}.`)
  }
  return bits.join(" ")
}

export function describe(data, ctx) {
  const count = stateCount(data)
  const single = ctx?.state
  if (single !== undefined || count === 1) {
    const i = Math.min(single ?? 0, count - 1)
    const op = data.states?.[i]?.op_it
    return `${count > 1 ? `Passo ${i + 1}. ${op ? `${plain(op)}. ` : ""}` : ""}${describeState(effectiveState(data, i), ctx)}`
  }
  return Array.from({ length: count }, (_, i) => `Passo ${i + 1}. ${data.states[i]?.op_it ? `${plain(data.states[i].op_it)}. ` : ""}${describeState(effectiveState(data, i), {})}`).join(" ")
}

export function controls(data) {
  if (data.reveal !== "columns") return []
  const steps = Math.max(...Array.from({ length: stateCount(data) }, (_, i) => work(effectiveState(data, i)).steps))
  return [{ id: "reveal", kind: "stepper", range: [0, steps], initial: 0, less_it: "Indietro", more_it: "Avanti", label_it: data.op === "mul" ? "Prodotti" : "Colonne" }]
}

// The stored ids of the select set "digits": the digits of a, b, the partial products and the result, rows from the top, left to right.
export function targetIds(data) {
  const eff = effectiveState(data, 0)
  const w = work(eff)
  const ids = []
  for (const [name, count] of [["a", w.width], ["b", w.width]]) for (let i = 1; i <= count; i++) ids.push(`${name}${i}`)
  if (w.op === "mul") w.partials.forEach((_, k) => { for (let i = 1; i <= w.width; i++) ids.push(`p${k + 1}.${i}`) })
  for (let i = 1; i <= w.width; i++) ids.push(`r${i}`)
  return ids
}

export function targets(data, set, opts = {}) {
  if (set !== "digits") return []
  const ids = targetIds(data)
  const scene = layout(data, { width: 360, fontPx: 20, subject: "computer_science", ...opts, mode: "select" })
  if (scene.error) return []
  return scene.targets.map((t, i) => ({ key: ids[i], bbox: t.bbox, neutral_it: `Cifra ${i + 1} di ${ids.length}` }))
}

// Every string the state prints (L4): the operands and the result (with and without groups), the carries, the partial products, the
// outside digit, the values.
export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const w = work(eff)
  const out = new Set()
  for (const s of [w.a, w.b, pad(w.b, w.width), w.result]) for (const form of groupings(s, w.base === 2 ? 4 : 0)) out.add(form)
  if (w.op === "mul") {
    out.add(w.full)
    for (const part of w.partials) out.add(part.digits)
  }
  // the values the step sentences say: the sum of a column (and how it is written in the base), the digit after a borrow
  if (w.op === "add") {
    for (let i = 0; i < w.width; i++) {
      const sum = ALPHABET.indexOf(w.a[i]) + ALPHABET.indexOf(w.b[i]) + (i + 1 < w.width ? w.carries[i + 1] : 0)
      out.add(String(sum))
      if (sum >= w.base && w.base !== 10) out.add(B.write(sum, 2, w.base) ?? String(sum))
    }
    for (const c of w.carries) if (c) out.add(String(c))
  }
  if (w.op === "sub") {
    for (let i = 0; i < w.width; i++) {
      const from = ALPHABET.indexOf(w.a[i]) - (i + 1 < w.width ? w.borrows[i + 1] : 0)
      out.add(String(from))
      out.add(String(from + w.base * w.borrows[i]))
    }
    for (const d of w.adjusted) out.add(ALPHABET[d] ?? String(d))
  }
  if (eff.read && eff.read !== "none") {
    const twos = eff.read === "twos"
    for (const digits of [w.a, pad(w.b, w.width), w.result]) out.add(show(B.read(digits, w.base, twos)))
  }
  if (data.states?.[state]?.op_it) out.add(data.states[state].op_it)
  return [...out]
}

