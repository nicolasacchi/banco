// callout: a box with a big icon, a small fixed label (Consiglio, Attenzione, Ricorda, Regola) and a short text.
import { el, icon } from "lesson/dom"
import { renderRich } from "lesson/text"

const ICONS = { tip: "tip", warning: "warning", remember: "remember", rule: "rule" }

export function render(block, ctx) {
  const kind = block.kind
  const label = ctx.t.callout[kind]
  return el("aside", { class: `block callout callout-${kind}`, "aria-label": label },
    icon(ICONS[kind] ?? "info", "callout-ic"),
    el("div", { class: "callout-main" },
      el("p", { class: "callout-head" }, el("strong", { text: block.title_it ? `${label}: ${block.title_it}` : label })),
      el("div", { class: "callout-body" }, renderRich(block.text_it, ctx))))
}
