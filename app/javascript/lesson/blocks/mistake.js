// mistake: a card to turn. The wrong version with a close icon and "Sbagliato" and "Tocca per girare" on it; touched, it shows
// the right version with a check icon and the why. The whole card is the button (aria-expanded). Grouped under group_it.
// All open in print, in teacher mode and in safe mode; no flip animation under reduced motion (CSS).
import { el, icon, uid } from "lesson/dom"
import { renderInlineRich, renderRich } from "lesson/text"

export function render(block, ctx, options = {}) {
  const id = uid("mistake")
  const card = el("article", { class: "block mistake", "data-open": "false" })
  // the cross and "Sbagliato" tell what this side is; the group (Segni, Dividere, ...) is the heading above the cards (cards.js)
  const front = el("div", { class: "mistake-front" },
    el("p", { class: "mistake-tag mistake-wrong" }, icon("close", "mistake-ic"), el("strong", { text: ctx.t.wrong_side }),
      options.group ? el("span", { class: "sr-only", text: ` (${options.group})` }) : null),
    renderInlineRich(block.wrong_it, el("p", { class: "mistake-text" }), ctx, { display: true, tiles: true }))
  const back = el("div", { class: "mistake-back", id },
    el("p", { class: "mistake-tag mistake-right" }, icon("check", "mistake-ic"), el("strong", { text: ctx.t.right_side })),
    renderInlineRich(block.right_it, el("p", { class: "mistake-text" }), ctx, { display: true, tiles: true }),
    el("div", { class: "mistake-why" }, renderRich(block.why_it, ctx)))
  // the flip is said on every card, in words: the right side is behind it
  const hint = el("span", { class: "mistake-hint", title: ctx.t.mistake_turn }, icon("show", "mistake-hand"), el("span", { class: "mistake-hint-text", "aria-hidden": "true", text: ctx.t.mistake_flip }), el("span", { class: "sr-only", text: ctx.t.mistake_turn }))
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
