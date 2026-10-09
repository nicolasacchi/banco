import { el } from "lesson/dom"
import { renderRich } from "lesson/text"

export function render(block, ctx) {
  return el("div", { class: "block block-text" }, renderRich(block.text_it, ctx))
}
