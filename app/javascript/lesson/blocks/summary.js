// summary: the points of the summary card, each with a check icon.
import { el, icon } from "lesson/dom"
import { renderInlineRich } from "lesson/text"

export function render(block, ctx) {
  const list = el("ul", { class: "block summary-points" })
  for (const point of block.points_it) list.appendChild(el("li", {}, icon("check", "point-ic"), renderInlineRich(point, el("span", { class: "point-text" }), ctx)))
  return list
}
