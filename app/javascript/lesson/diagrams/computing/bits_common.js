// Shared by register and column_calc (T9): the digits of a register in their own cells, the weights over them, the groups, the
// Italian way of writing a number, and the cell sizes that keep a target at 24 px or more (A2). Pure.
import * as B from "lesson/lib/bits"
import { label, shape } from "lesson/diagrams/common"

export const MINUS = "−"
export const THIN = "\u202f" // a narrow no-break space between groups of digits

// A whole number the way S reads it: the true minus sign, no plus.
export const show = (n) => `${n < 0 ? MINUS : ""}${Math.abs(n)}`

// Digits in groups from the right ("11111011" by 4 -> "1111 1011", with a narrow no-break space).
export function grouped(digits, g) {
  if (!g) return digits
  const out = []
  for (let end = digits.length; end > 0; end -= g) out.unshift(digits.slice(Math.max(0, end - g), end))
  return out.join(THIN)
}

// The forms in which digits are printed (L4): bare, in groups with the narrow no-break space, and with a plain space (what an author types).
export function groupings(digits, g) {
  if (!g || digits.length <= g) return [digits]
  return [...new Set([digits, grouped(digits, g), grouped(digits, g).replaceAll(THIN, " ")])]
}

// The value of digits in a base, as a number: unsigned, or two's complement.
export const valueOf = (digits, base, twos) => B.read(digits, base, twos)

// The weight of the digit at position i (0 = leftmost) in a register of n digits: base^(n-1-i); the first one is negative in two's complement.
export function weightAt(i, n, base, twos) {
  const w = base ** (n - 1 - i)
  return twos && i === 0 ? -w : w
}

// "−128 + 64 + 8 + 2 + 1 = −5": the weights of the digits that count, and their sum ("" when none counts). Only for base 2 (a digit is on or off).
export function sumLine(digits, twos) {
  const parts = []
  let total = 0
  for (let i = 0; i < digits.length; i++) {
    if (digits[i] !== "1") continue
    const w = weightAt(i, digits.length, 2, twos)
    parts.push(show(w))
    total += w
  }
  if (parts.length === 0) return "" // nothing counts: there is nothing to add
  return `${parts.join(" + ").replace(`+ ${MINUS}`, `${MINUS}`)} = ${show(total)}`
}

// Where the digits go. n digits in rows of `per` (at most n; a multiple of the group size so a group never splits), cells of `cell` px,
// a gap of `gapW` between groups; rows are right-aligned and the block is centred in the width left after `reserve`.
export function rowPlan(ctx, n, groups, { reserve = 0, maxCell = 56 } = {}) {
  const avail = ctx.width - reserve - 4
  const gapW = groups ? Math.round(ctx.fontPx * 0.5) : 0
  const minCell = Math.max(24, Math.round(ctx.fontPx * 1.25))
  const gapsFor = (per) => (groups ? Math.ceil(per / groups) - 1 : 0)
  let per = n
  let cell = Math.min(maxCell, Math.floor((avail - gapsFor(per) * gapW) / per))
  for (let rows = 2; cell < minCell && rows <= n; rows++) {
    per = Math.ceil(n / rows)
    if (groups) per = Math.ceil(per / groups) * groups
    if (per >= n) continue
    cell = Math.min(maxCell, Math.floor((avail - gapsFor(per) * gapW) / per))
  }
  cell = Math.max(cell, 12)
  const chunks = []
  for (let end = n; end > 0; end -= per) chunks.unshift([Math.max(0, end - per), end])
  const width = per * cell + gapsFor(per) * gapW
  const left = Math.round(reserve + Math.max(2, (avail - width) / 2))
  // the x of the slot t (0 = leftmost of a full row)
  const slotX = (t) => {
    let gaps = 0
    if (groups) for (let s = 1; s <= t; s++) if ((per - s) % groups === 0) gaps += 1
    return left + t * cell + gaps * gapW
  }
  return { per, cell, gapW, chunks, width, left, slotX, rows: chunks.length, xOf: (j) => {
    const chunk = chunks.find(([a, b]) => j >= a && j < b)
    return slotX(per - (chunk[1] - j))
  }, rowOf: (j) => chunks.findIndex(([a, b]) => j >= a && j < b) }
}

// The height of a row of cells: square, but never under the line of text it holds (the labels of two rows must not touch).
export const cellH = (ctx, size) => Math.max(size, ctx.lineH)

// A cell with its digit. `on` fills the cell (a 1 in a register); `cls` adds classes (dg-outside for a digit that fell out). Returns the box.
export function digitCell(ctx, x, y, size, text, { on = false, cls = "", target, digitCls = "" } = {}) {
  const h = cellH(ctx, size)
  const s = shape(ctx, "rect", { x, y, w: size, h, r: 6, cls: `dg-bit${on ? " dg-on" : ""}${cls ? ` ${cls}` : ""}` })
  if (target) s.target = target
  label(ctx, text, x + size / 2, y + h / 2, { valign: "middle", cls: `dg-digit${digitCls ? ` ${digitCls}` : ""}` })
  return { x, y, w: size, h }
}
