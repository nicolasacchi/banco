// area_model (A7): a grid of rows x cols with the header labels and the product in each cell (the box
// method for the distributive law and special products). States fill cells in; an empty cell is a
// dashed box. Cell labels are formulas: the grid is as wide as its widest cell.
import { effectiveState, finish, label, plain, shape, stateCount, words, listIt } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const states = stateCount

export function semantic(data) {
  for (let i = 0; i < data.rows.length; i++) if (words(data.rows[i]) > 6) return { path: `/rows/${i}`, message: "a label has at most 6 words" }
  for (let i = 0; i < data.cols.length; i++) if (words(data.cols[i]) > 6) return { path: `/cols/${i}`, message: "a label has at most 6 words" }
  const check = (cells, base) => {
    if (!cells) return null
    if (cells.length !== data.rows.length || cells.some((r) => r.length !== data.cols.length)) return { path: base, message: "cells are rows x cols" }
    return null
  }
  const top = check(data.cells, "/cells")
  if (top) return top
  for (let j = 0; j < (data.states ?? []).length; j++) {
    const bad = check(data.states[j].cells, `/states/${j}/cells`)
    if (bad) return bad
  }
  return null
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const W = ctx.width
  const f = ctx.fontPx
  const cells = eff.cells ?? data.rows.map(() => data.cols.map(() => ""))
  const widest = (list) => Math.max(...list.map((t) => (t ? ctx.measure(t, f).w : 0)))
  const headW = Math.max(Math.round(f * 1.6), Math.ceil(widest(data.rows)) + 2 * ctx.pad)
  // the widest content of any state decides the column width, so the grid does not move between states
  const allCells = [data.cells, ...(data.states ?? []).map((s) => s.cells)].filter(Boolean).flat(2)
  const colW = Math.max(Math.round(f * 2.2), Math.ceil(widest([...allCells, ...data.cols])) + 2 * ctx.pad + 4)
  const total = headW + colW * data.cols.length
  if (total > W - 8) return { error: { path: "/cells", message: "the grid is wider than the figure", code: "E-DIAGRAM-LAYOUT" } }
  const rowH = Math.round(f * 2.2)
  const x0 = Math.round((W - total) / 2)
  const y0 = rowH
  data.cols.forEach((c, j) => {
    label(ctx, c, x0 + headW + colW * j + colW / 2, y0 / 2 + 2, { valign: "middle", cls: "dg-head role-muted" })
  })
  data.rows.forEach((r, i) => {
    label(ctx, r, x0 + headW / 2, y0 + rowH * i + rowH / 2, { valign: "middle", cls: "dg-head role-muted" })
  })
  cells.forEach((row, i) => {
    row.forEach((text, j) => {
      const x = x0 + headW + colW * j
      const y = y0 + rowH * i
      shape(ctx, "rect", { x: x + 2, y: y + 2, w: colW - 4, h: rowH - 4, r: 8, cls: text ? "dg-cell" : "dg-cell dg-cell-empty" })
      if (text) label(ctx, text, x + colW / 2, y + rowH / 2, { valign: "middle", cls: "dg-celltext" })
    })
  })
  return finish(ctx, y0 + rowH * data.rows.length + 6, { states: stateCount(data), state: ctx.state })
}

export function describe(data) {
  const n = stateCount(data)
  const out = []
  for (let i = 0; i < n; i++) {
    const e = effectiveState(data, i)
    const rows = data.rows.map((r, a) => `riga «${plain(r)}»: ${listIt((e.cells?.[a] ?? []).map((c, b) => `${plain(data.cols[b])} per ${plain(r)} fa ${c ? plain(c) : "da scoprire"}`))}`)
    out.push(`${n > 1 ? `Passo ${i + 1}. ` : ""}Una griglia con ${data.rows.length} righe e ${data.cols.length} colonne. ${rows.join(". ")}.`)
  }
  return out.join(" ")
}

export const layout = (data, opts) => run(data, opts, { semantic, build })
