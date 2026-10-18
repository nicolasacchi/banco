// more: nested blocks behind "Vuoi saperne di più?" (closed; open in print, in teacher mode and in safe mode).
import { el, icon } from "lesson/dom"
import { insideControl, renderInlineRich } from "lesson/text"

export function render(block, ctx, renderBlock) {
  // the title holds the same inline markup as the text (a formula: D-310); the summary is the control, so nothing inside it is one
  const title = el("span", { text: ` ${ctx.t.more}: ` }, renderInlineRich(block.title_it, el("span"), insideControl(ctx)))
  const details = el("details", { class: "block more" }, el("summary", {}, icon("telescope", "more-ic"), title))
  const body = el("div", { class: "more-body" })
  for (const inner of block.blocks) body.appendChild(renderBlock(inner))
  details.appendChild(body)
  if (ctx.openMore) details.open = true
  return details
}
