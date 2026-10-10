// table: an HTML table; rows stack under 600 px (the cell's data-label is shown by the CSS).
import { el } from "lesson/dom"
import { renderInlineRich } from "lesson/text"

export function render(block, ctx) {
  const table = el("table", { class: "dg-table" })
  if (block.caption_it) table.appendChild(renderInlineRich(block.caption_it, el("caption"), ctx))
  const head = el("tr")
  block.header.forEach((h) => head.appendChild(renderInlineRich(h, el("th", { scope: "col" }), ctx)))
  table.appendChild(el("thead", {}, head))
  const body = el("tbody")
  for (const row of block.rows) {
    const tr = el("tr")
    row.forEach((cell, i) => {
      const td = renderInlineRich(cell, el(i === 0 ? "th" : "td", i === 0 ? { scope: "row" } : {}), ctx)
      td.setAttribute("data-label", block.header[i].replace(/\$/g, ""))
      tr.appendChild(td)
    })
    body.appendChild(tr)
  }
  table.appendChild(body)
  return el("div", { class: "block block-table" }, table)
}
