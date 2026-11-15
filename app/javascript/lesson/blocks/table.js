// table: an HTML table; under 600 px a narrow or compact table keeps its grid (keepsGrid, D-331, D-335) and a wider one stacks its rows. A stacked cell starts
// with its column's name, drawn from the header cell with the same inline markup (a formula, a word of another language: D-310), hidden on a
// wide screen and in a kept grid, and from the voice and the screen reader (the head says it).
import { el } from "lesson/dom"
import { insideControl, plainText, renderInlineRich } from "lesson/text"

// A grid read on a phone: the lesson's box is about 295 px wide at a 390 px viewport (312 px measured in Chrome at 390 px, D-335). A cell's
// padding and border are 26 px (measured 26.6). A character is taken as 9 px: measured in the lesson font at 390 px (19 px type), a line of
// text is 8.1 to 9.2 px a character (a 40-character sentence 342.9 px, «hablasteis» 85.2 px, «quoziente» 82.4 px), so 9 is no estimate to
// lower (only the digits and the signs «+» «−» are wider, 11.5 px, and they are what the compact rule below holds); render_host's
// E-LESSON-OVERFLOW still catches a table this estimate lets through wrongly (D-331).
const KEEP_MAX_PX = 280
const KEEP_MAX_COLUMNS = 5
const CHAR_PX = 9
const CELL_PX = 26

// A compact table (a table of signs, of values, of T and t): every body cell but the first column's is at most 3 characters of plain text.
// Its width is the header's and the first column's, which wrap, so it keeps its grid up to 7 columns whatever the estimate (D-335).
const COMPACT_CELL_CHARS = 3
const COMPACT_MAX_COLUMNS = 7

const length = (cell) => [...plainText(cell).trim()].length

// Whether a table ({ header, rows }) stays a grid on a phone. Pure. Either it is compact (see above: at least one row, every cell after
// the first column of a row at most 3 characters, at most 7 columns), or it is narrow (D-331): at most 5 columns and an estimated width
// (each column's longest cell, header included, as plain text without its markup) of at most 280 px.
export function keepsGrid(table) {
  const header = table.header ?? []
  const rows = table.rows ?? []
  const widest = []
  for (const line of [header, ...rows]) {
    line.forEach((cell, i) => {
      widest[i] = Math.max(widest[i] ?? 0, length(cell))
    })
  }
  if (widest.length <= COMPACT_MAX_COLUMNS && rows.length > 0 && rows.every((row) => row.slice(1).every((cell) => length(cell) <= COMPACT_CELL_CHARS))) return true
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

// A table that keeps its grid sits in a box that scrolls sideways when the grid is wider than the card (D-335): the page never does.
export function render(block, ctx) {
  const node = tableNode(block, ctx)
  return el("div", { class: node.classList.contains("dg-keep") ? "block block-table dg-scroll" : "block block-table" }, node)
}
