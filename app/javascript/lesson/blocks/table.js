// table: an HTML table; under 600 px a narrow table keeps its grid (keepsGrid, D-331) and a wider one stacks its rows. A stacked cell starts
// with its column's name, drawn from the header cell with the same inline markup (a formula, a word of another language: D-310), hidden on a
// wide screen and in a kept grid, and from the voice and the screen reader (the head says it).
import { el } from "lesson/dom"
import { insideControl, plainText, renderInlineRich } from "lesson/text"

// A grid read on a phone: the lesson's box is about 295 px wide at a 390 px viewport. A character is taken as 9 px, a cell's padding and
// border as 26 px; render_host's E-LESSON-OVERFLOW still catches a table this estimate lets through wrongly (D-331).
const KEEP_MAX_PX = 280
const KEEP_MAX_COLUMNS = 5
const CHAR_PX = 9
const CELL_PX = 26

// Whether a table ({ header, rows }) is narrow enough to stay a grid on a phone: at most 5 columns and an estimated width (each column's
// longest cell, header included, as plain text without its markup) of at most 280 px. Pure.
export function keepsGrid(table) {
  const widest = []
  for (const line of [table.header ?? [], ...(table.rows ?? [])]) {
    line.forEach((cell, i) => {
      widest[i] = Math.max(widest[i] ?? 0, [...plainText(cell).trim()].length)
    })
  }
  if (widest.length > KEEP_MAX_COLUMNS) return false
  return widest.reduce((sum, chars) => sum + chars * CHAR_PX + CELL_PX, 0) <= KEEP_MAX_PX
}

// { caption_it?, header, rows } -> <table class="dg-table"> (with "dg-keep" when it keeps its grid on a phone); draw.js uses it for the
// `table` figure (A8) too.
export function tableNode(table, ctx) {
  const node = el("table", { class: keepsGrid(table) ? "dg-table dg-keep" : "dg-table" })
  if (table.caption_it) node.appendChild(renderInlineRich(table.caption_it, el("caption"), ctx))
  const head = el("tr")
  table.header.forEach((h) => head.appendChild(renderInlineRich(h, el("th", { scope: "col" }), ctx)))
  node.appendChild(el("thead", {}, head))
  const body = el("tbody")
  for (const row of table.rows) {
    const tr = el("tr")
    row.forEach((cell, i) => {
      // the row header carries its column's name too when rows stack (an empty corner header has none)
      const td = el(i === 0 ? "th" : "td", i === 0 ? { scope: "row" } : {})
      if (i > 0 || String(table.header[0] ?? "").trim() !== "") {
        const label = renderInlineRich(table.header[i] ?? "", el("span", { class: "cell-label", "aria-hidden": "true" }), insideControl(ctx))
        label.appendChild(document.createTextNode(": "))
        td.appendChild(label)
      }
      tr.appendChild(renderInlineRich(cell, td, ctx))
    })
    body.appendChild(tr)
  }
  node.appendChild(body)
  return node
}

export function render(block, ctx) {
  return el("div", { class: "block block-table" }, tableNode(block, ctx))
}
