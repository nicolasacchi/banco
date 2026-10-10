// mistake: a card to turn. The wrong version with a close icon and "Sbagliato", a button "Tocca per la
// versione giusta" (aria-expanded), then the check icon and "Giusto" and the why. Grouped under group_it.
// All open in print, in teacher mode and in safe mode; no flip animation under reduced motion (CSS).
import { button, el, icon, uid } from "lesson/dom"
import { renderInlineRich, renderRich } from "lesson/text"

export function render(block, ctx) {
  const id = uid("mistake")
  const card = el("article", { class: "block mistake", "data-open": "false" })
  const front = el("div", { class: "mistake-front" },
    el("p", { class: "mistake-tag mistake-wrong" }, icon("close", "mistake-ic"), el("strong", { text: ctx.t.wrong_side })),
    renderInlineRich(block.wrong_it, el("p", { class: "mistake-text" }), ctx))
  const back = el("div", { class: "mistake-back", id },
    el("p", { class: "mistake-tag mistake-right" }, icon("check", "mistake-ic"), el("strong", { text: ctx.t.right_side })),
    renderInlineRich(block.right_it, el("p", { class: "mistake-text" }), ctx),
    el("div", { class: "mistake-why" }, renderRich(block.why_it, ctx)))
  const toggle = button(ctx.t.mistake_turn, { class: "button secondary small mistake-toggle", "aria-expanded": "false", "aria-controls": id }, () => {
    const open = toggle.getAttribute("aria-expanded") !== "true"
    toggle.setAttribute("aria-expanded", String(open))
    card.dataset.open = String(open)
    toggle.firstChild.textContent = open ? ctx.t.mistake_hide : ctx.t.mistake_turn
  })
  card.append(front, toggle, back)
  if (ctx.openAll) {
    card.dataset.open = "true"
    toggle.setAttribute("aria-expanded", "true")
  }
  return card
}
