// The prompt of an item: the stem, the instance's own stem, a table, a quote and a
// figure. Agent text goes through the restricted markup; a figure is only ever an
// <img> from /assets/items/<sha256>.svg (X-02).
import { el } from "items/dom"
import { renderInline, renderMarkup } from "items/markup"

export function renderPrompt(part, ctx) {
  const box = el("div", { class: "prompt" })
  if (part.passage_it) {
    const passage = el("div", { class: "passage" })
    passage.appendChild(renderMarkup(part.passage_it))
    box.appendChild(el("h2", { class: "passage-title", text: ctx.t.passage }))
    box.appendChild(passage)
  }
  if (part.stem_it) box.appendChild(renderMarkup(part.stem_it))
  if (part.instance_stem_it) {
    const stem = el("div", { class: "instance-stem" })
    stem.appendChild(renderMarkup(part.instance_stem_it))
    box.appendChild(stem)
  }
  if (part.quote) box.appendChild(quote(part.quote))
  if (part.table) box.appendChild(table(part.table))
  if (part.figure) box.appendChild(figure(part.figure))
  return box
}

function quote(data) {
  const block = el("blockquote", { class: "quote" })
  block.appendChild(renderMarkup(data.text))
  block.appendChild(renderInline(data.ref, el("cite")))
  return block
}

function table(data) {
  const node = el("table", { class: "data" })
  if (data.caption_it) node.appendChild(renderInline(data.caption_it, el("caption")))
  const head = el("tr")
  for (const cell of data.header || []) head.appendChild(renderInline(String(cell), el("th", { scope: "col" })))
  node.appendChild(el("thead", {}, head))
  const body = el("tbody")
  for (const row of data.rows || []) {
    const tr = el("tr")
    for (const cell of row) tr.appendChild(renderInline(String(cell), el("td")))
    body.appendChild(tr)
  }
  node.appendChild(body)
  return el("div", { class: "table-wrap" }, node)
}

function figure(data) {
  if (!data.src) return el("p", { class: "figure-alt" }, data.alt_it || "")
  return el("figure", {}, el("img", { src: data.src, alt: data.alt_it || "", class: "figure" }))
}
