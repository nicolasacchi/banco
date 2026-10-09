// callout: a box with an icon and a fixed label (Consiglio, Attenzione, Ricorda, Regola).
import { el, icon } from "lesson/dom"
import { renderRich } from "lesson/text"

const ICONS = { tip: "tip", warning: "warning", remember: "remember", rule: "rule" }

export function render(block, ctx) {
  const kind = block.kind
  const title = block.title_it || ctx.t.callout[kind]
  return el("aside", { class: `block callout callout-${kind}`, "aria-label": ctx.t.callout[kind] },
    el("p", { class: "callout-head" }, icon(ICONS[kind] ?? "info", "callout-ic"), el("strong", { text: block.title_it ? `${ctx.t.callout[kind]}: ${title}` : title })),
    el("div", { class: "callout-body" }, renderRich(block.text_it, ctx)))
}
