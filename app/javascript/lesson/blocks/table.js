// table: an HTML table; rows stack under 600 px. A stacked cell starts with its column's name, drawn from the header cell with the same inline
// markup (a formula, a word of another language: D-310), hidden on a wide screen and from the voice and the screen reader (the head says it).
import { el } from "lesson/dom"
import { insideControl, renderInlineRich } from "lesson/text"

// { caption_it?, header, rows } -> <table class="dg-table">; draw.js uses it for the `table` figure (A8) too.
export function tableNode(table, ctx) {
  const node = el("table", { class: "dg-table" })
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
