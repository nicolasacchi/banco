// more: nested blocks behind "Vuoi saperne di più?" (closed; open in print, in teacher mode and in safe mode).
import { el, icon } from "lesson/dom"

export function render(block, ctx, renderBlock) {
  const details = el("details", { class: "block more" }, el("summary", {}, icon("telescope", "more-ic"), el("span", { text: ` ${ctx.t.more}: ${block.title_it}` })))
  const body = el("div", { class: "more-body" })
  for (const inner of block.blocks) body.appendChild(renderBlock(inner))
  details.appendChild(body)
  if (ctx.openMore) details.open = true
  return details
}
