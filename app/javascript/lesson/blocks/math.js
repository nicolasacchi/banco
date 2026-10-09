// math: one display formula, or a chain of transformations (2 to 4 lines) with the note between the lines.
import { el, icon } from "lesson/dom"
import { renderInlineRich, renderMath } from "lesson/text"

export function render(block, ctx) {
  if (block.tex) return el("div", { class: "block block-math" }, renderMath(block.tex, el("div", { class: "mathline" }), ctx, true))
  const chain = el("ol", { class: "block block-math chain" })
  block.lines.forEach((line, i) => {
    chain.appendChild(el("li", { class: "chain-line" }, renderMath(line.tex, el("div", { class: "mathline" }), ctx, true)))
    if (line.note_it && i < block.lines.length - 1) {
      chain.appendChild(el("li", { class: "chain-note", "aria-hidden": "false" }, icon("expand", "chain-arrow"), renderInlineRich(line.note_it, el("span", { class: "chain-text" }), ctx)))
    }
  })
  return chain
}
