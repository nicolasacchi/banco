// The flip card of the page (D-259, WAVE2 2.10): one mechanism for `mistake` and `reveal`. A front, a back that is not in the way until it
// is asked for, and the control that turns it. Two shapes:
//   control "card"   the whole front is the button (aria-expanded): a mistake, a plain reveal. The hint "Tocca per girare" says so on every card.
//   control "button" a separate button after the front (aria-expanded): the front holds its own controls (the options of a crossroads).
// The back is in the document but `display: none` until opened, so a screen reader and "Ascolta" meet it only once shown (L10). Everything is
// open in print, in the teacher's view and in safe mode (ctx.openAll). No flip animation under reduced motion (CSS). Classes are
// `${prefix}-toggle`, `${prefix}-back`, `${prefix}-hint`, `${prefix}-hint-text`, `${prefix}-hand`, so each block keeps its own look.
import { el, icon, uid } from "lesson/dom"

// front, back: nodes. hint: { text, label } for the card control; button: { text } for the button control.
export function flip({ prefix, front, back, ctx, control = "card", hint = {}, button = {}, onChange, className = "" }) {
  const id = uid(prefix)
  const card = el("article", { class: `block ${prefix} flip${className ? ` ${className}` : ""}`, "data-open": "false" })
  const backBox = el("div", { class: `${prefix}-back flip-back`, id }, back)
  let toggle
  if (control === "button") {
    toggle = el("button", { type: "button", class: `${prefix}-toggle flip-go button secondary small`, "aria-expanded": "false", "aria-controls": id }, icon("show", `${prefix}-hand`), el("span", { text: button.text }))
  } else {
    const hintNode = el("span", { class: `${prefix}-hint`, title: hint.label }, icon("show", `${prefix}-hand`),
      el("span", { class: `${prefix}-hint-text`, "aria-hidden": "true", text: hint.text }), el("span", { class: "sr-only", text: hint.label }))
    toggle = el("button", { type: "button", class: `${prefix}-toggle`, "aria-expanded": "false", "aria-controls": id }, front, hintNode)
  }
  const set = (open) => {
    toggle.setAttribute("aria-expanded", String(open))
    card.dataset.open = String(open)
    onChange?.(open)
  }
  toggle.addEventListener("click", () => set(toggle.getAttribute("aria-expanded") !== "true"))
  if (control === "button") card.append(front, toggle, backBox)
  else card.append(toggle, backBox)
  if (ctx.openAll) set(true)
  return { element: card, toggle, set, isOpen: () => card.dataset.open === "true" }
}
