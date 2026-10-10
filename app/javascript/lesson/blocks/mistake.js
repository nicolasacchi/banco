// mistake: a card to turn. The wrong version with a close icon and "Sbagliato" and a hint to touch it; touched, it shows
// the right version with a check icon and the why. The whole card is the button (aria-expanded). Grouped under group_it.
// All open in print, in teacher mode and in safe mode; no flip animation under reduced motion (CSS).
import { el, icon, uid } from "lesson/dom"
import { renderInlineRich, renderRich } from "lesson/text"

export function render(block, ctx) {
  const id = uid("mistake")
  const card = el("article", { class: "block mistake", "data-open": "false" })
  const front = el("div", { class: "mistake-front" },
    el("p", { class: "mistake-tag mistake-wrong" }, icon("close", "mistake-ic"), el("strong", { text: ctx.t.wrong_side })),
    renderInlineRich(block.wrong_it, el("p", { class: "mistake-text" }), ctx, { display: true, tiles: true }))
  const back = el("div", { class: "mistake-back", id },
    el("p", { class: "mistake-tag mistake-right" }, icon("check", "mistake-ic"), el("strong", { text: ctx.t.right_side })),
    renderInlineRich(block.right_it, el("p", { class: "mistake-text" }), ctx, { display: true, tiles: true }),
    el("div", { class: "mistake-why" }, renderRich(block.why_it, ctx)))
  const hint = el("span", { class: "mistake-hint" }, icon("show", "mistake-hand"), document.createTextNode(ctx.t.mistake_turn))
  const toggle = el("button", { type: "button", class: "mistake-toggle", "aria-expanded": "false", "aria-controls": id }, front, hint)
  const set = (open) => {
    toggle.setAttribute("aria-expanded", String(open))
    card.dataset.open = String(open)
  }
  toggle.addEventListener("click", () => set(toggle.getAttribute("aria-expanded") !== "true"))
  card.append(toggle, back)
  if (ctx.openAll) set(true)
  return card
}
