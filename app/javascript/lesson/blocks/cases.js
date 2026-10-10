// cases: 2 to 4 columns side by side from 2 x 45ch, stacked below (CSS container query). Each case has an
// icon, a tone, a condition, text, an example and a diagram.
import { el, icon } from "lesson/dom"
import { renderInlineRich, renderRich, roleOf } from "lesson/text"
import { embed } from "lesson/blocks/diagram"

export function render(block, ctx) {
  const box = el("section", { class: `block cases cases-${block.cases.length}` })
  if (block.title_it) box.appendChild(el("h3", { class: "block-title", text: block.title_it }))
  const grid = el("div", { class: "cases-grid" })
  for (const c of block.cases) {
    const tone = c.tone ? `case-tone card-tone-${c.tone}` : ""
    const head = el("h4", { class: "case-head" })
    const info = c.tone ? roleOf(ctx.subject, c.tone) : null
    const iconName = c.icon ?? (info?.carrier === "icon" ? info.icon : null)
    if (iconName) head.appendChild(icon(iconName, "case-ic"))
    head.appendChild(document.createTextNode(c.title_it))
    const section = el("section", { class: `case ${tone}` }, head)
    if (c.condition_it) section.appendChild(renderInlineRich(c.condition_it, el("p", { class: "case-condition" }), ctx, { tiles: true }))
    section.appendChild(el("div", { class: "case-text" }, renderRich(c.text_it, ctx)))
    if (c.example_it) section.appendChild(el("div", { class: "case-example" }, renderRich(c.example_it, ctx, { tiles: true })))
    if (c.diagram) section.appendChild(embed(c.diagram, ctx))
    grid.appendChild(section)
  }
  box.appendChild(grid)
  return box
}
