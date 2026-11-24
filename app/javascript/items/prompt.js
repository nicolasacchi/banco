// The prompt of an item: the stem, the instance's own stem, a table, a quote and a
// figure. Agent text goes through the restricted markup; a figure is only ever an
// <img> from /assets/items/<sha256>.svg (X-02).
import { el } from "items/dom"
import { renderInline, renderMarkup } from "items/markup"
import { softBreaks } from "items/soft_breaks"
import { bare, block, cell, langOf, passageBox, sides, trNode } from "items/bilingual"

// A bilingual item (part.lang, D-402) draws the target text with its Italian translation after it, hidden until the exercise's «Traduzione» (or the
// unit's own button) opens it; a legacy item draws its `_it` text exactly as before. The passage is a reading text, the instance's own (`display.passage_*`)
// or else the item's, and the server puts it in the part either way: its Italian is never drawn here (the server does not send it with the part, and
// ctx.passageTranslation is only set where nobody answers: the teacher's frozen slot); the page adds it with reveal() once the exercise is over.
export function renderPrompt(part, ctx) {
  const lang = langOf(part)
  const box = el("div", { class: "prompt", "data-comment-anchor": "prompt" })
  if (lang) {
    const text = part[`passage_${lang}`]
    if (text) {
      box.appendChild(el("h2", { class: "passage-title", text: ctx.t.passage }))
      const passage = passageBox(text, lang)
      passage.setAttribute("data-comment-anchor", "passage")
      if (ctx.passageTranslation && part.passage_it) passage.appendChild(trNode(part.passage_it))
      box.appendChild(passage)
    }
    const stem = sides(part, "stem", lang)
    if (stem) box.appendChild(block(renderMarkup(stem.text), stem.text, stem.italian, ctx))
    const instance = sides(part, "instance_stem", lang)
    if (instance) {
      const holder = el("div", { class: "instance-stem", lang })
      holder.appendChild(block(renderMarkup(instance.text), instance.text, instance.italian, ctx))
      box.appendChild(holder)
    }
  } else {
    if (part.passage_it) {
      const passage = el("div", { class: "passage", "data-comment-anchor": "passage" })
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
  }
  if (part.quote) box.appendChild(quote(part.quote, lang))
  if (part.table) box.appendChild(table(part.table, lang))
  if (part.figure) box.appendChild(figure(part.figure, lang))
  return box
}

// The quote is target text with its Italian under it; the citation (`ref`) is a neutral reference and stays as it is.
function quote(data, lang) {
  const block = el("blockquote", { class: "quote", "data-comment-anchor": "quote" })
  if (lang) block.setAttribute("lang", lang)
  block.appendChild(renderMarkup(data.text))
  const { italian } = bare(data, "text", lang)
  if (italian) block.appendChild(trNode(italian))
  block.appendChild(renderInline(data.ref, el("cite")))
  return block
}

// A table: the target header and cells, and in a bilingual item the Italian of each one under it (`header_it`, `rows_it`, the same shape); no button in
// a cell. The caption is a pair like the stem (`caption_<lang>` + `caption_it`).
function table(data, lang) {
  const node = el("table", { class: "data" })
  if (lang) node.setAttribute("lang", lang)
  const caption = sides(data, "caption", lang)
  if (caption?.text) node.appendChild(cell(renderInline(caption.text, el("caption")), caption.italian))
  const italianHeader = lang ? data.header_it || [] : []
  const italianRows = lang ? data.rows_it || [] : []
  const head = el("tr")
  ;(data.header || []).forEach((text, i) => head.appendChild(cell(softBreaks(renderInline(String(text), el("th", { scope: "col" }))), italianHeader[i])))
  node.appendChild(el("thead", {}, head))
  const body = el("tbody")
  ;(data.rows || []).forEach((row, r) => {
    const tr = el("tr")
    row.forEach((text, i) => tr.appendChild(cell(softBreaks(renderInline(String(text), el("td"))), italianRows[r]?.[i])))
    body.appendChild(tr)
  })
  node.appendChild(body)
  return el("div", { class: "table-wrap", "data-comment-anchor": "table" }, node)
}

// The figure is an <img>: its alt is the target text, and the Italian of the description is a line under it.
function figure(data, lang) {
  const alt = sides(data, "alt", lang)
  const text = alt?.text || ""
  const italian = alt?.italian
  if (!data.src) {
    const p = el("p", { class: "figure-alt", "data-comment-anchor": "figure" }, text)
    if (alt?.lang) p.setAttribute("lang", alt.lang)
    return cell(p, italian)
  }
  const img = el("img", { src: data.src, alt: text, class: "figure" })
  const node = el("figure", { "data-comment-anchor": "figure" }, img)
  if (alt?.lang) img.setAttribute("lang", alt.lang)
  return cell(node, italian, { tag: "figcaption" })
}

// The steps of an item (`steps_<lang>` + `steps_it`, or the legacy `steps_it`): what to do, as a calm numbered list under a small title.
export function renderSteps(steps, ctx, italian = null) {
  const list = el("ol", { class: "do-steps" })
  steps.forEach((text, i) => list.appendChild(cell(renderInline(String(text), el("li")), italian?.[i])))
  return el("div", { class: "steps-box" }, el("p", { class: "hint steps-title", text: ctx.t.steps_title }), list)
}
