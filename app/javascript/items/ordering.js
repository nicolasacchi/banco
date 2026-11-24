// ordering: rows with Su and Giù buttons; Alt with the arrow keys moves the row
// that has the focus (E-03: keyboard first, no drag). The rows arrive in a server
// shuffle that is never the key or its reverse, with ids in shown order (X-01).
// The raw answer is JSON text: the shown ids in the order the student chose.
import { announceChange, el, handle } from "items/dom"
import { renderInline } from "items/markup"
import { bare, langOf, trNode } from "items/bilingual"

// An element shorter than this many words is a fragment (a word, a chunk), not a sentence: it has no translation line (D-402, design §3.1).
const FRAGMENT_WORDS = 3

export function render(part, ctx) {
  const lang = langOf(part)
  const list = el("ol", { class: "ordering", "aria-label": ctx.t.ordering_label })
  const live = el("p", { class: "sr-only", role: "status", "aria-live": "polite" })
  const rows = (part.elements || []).map((element, index) => {
    const text = renderInline(element.text, el("span", { class: "row-text" }))
    const up = el("button", { type: "button", class: "button secondary small", text: ctx.t.ordering_up })
    const down = el("button", { type: "button", class: "button secondary small", text: ctx.t.ordering_down })
    const moves = el("span", { class: "row-moves" }, up, down)
    const { italian } = bare(element, "text", lang)
    const sentence = italian && String(element.text).trim().split(/\s+/).length >= FRAGMENT_WORDS
    if (lang) text.setAttribute("lang", lang)
    const row = el("li", { class: "order-row", tabindex: "0", "data-id": element.id, "data-comment-anchor": `row:${index + 1}` }, text, moves, sentence ? trNode(italian, { tag: "span" }) : null)
    up.addEventListener("click", () => move(row, -1, up))
    down.addEventListener("click", () => move(row, 1, down))
    row.addEventListener("keydown", (event) => {
      if (!event.altKey || (event.key !== "ArrowUp" && event.key !== "ArrowDown")) return
      event.preventDefault()
      move(row, event.key === "ArrowUp" ? -1 : 1, row)
    })
    return row
  })
  rows.forEach((row) => list.appendChild(row))

  function move(row, delta, focusTarget) {
    const siblings = Array.from(list.children)
    const target = siblings[siblings.indexOf(row) + delta]
    if (!target) return
    if (delta < 0) list.insertBefore(row, target)
    else list.insertBefore(target, row)
    focusTarget.focus()
    announceChange(wrapper)
    live.textContent = `${row.querySelector(".row-text").textContent}: ${Array.from(list.children).indexOf(row) + 1}`
  }

  const wrapper = el("div", { class: "answer" }, el("p", { class: "hint", text: ctx.t.ordering_label }), list, live)
  const ids = () => Array.from(list.children).map((row) => row.getAttribute("data-id"))
  // The shown order is where the student starts: until a step moves, nothing is typed ("" is the draft).
  const initial = ids()
  const sameOrder = (a, b) => a.length === b.length && a.every((id, i) => id === b[i])
  const place = (order) => order.forEach((id) => list.appendChild(rows.find((row) => row.getAttribute("data-id") === id)))
  return handle(wrapper, {
    raw: () => JSON.stringify(ids()),
    isEmpty: () => false,
    focus: () => rows[0]?.focus(),
    draft: () => (sameOrder(ids(), initial) ? "" : JSON.stringify(ids())),
    // "" puts the shown order back; a list that is not exactly the ids of this item is ignored.
    restore: (draft) => {
      if (draft === "") return place(initial)
      let order
      try { order = JSON.parse(draft) } catch { return }
      if (!Array.isArray(order) || !sameOrder([...order].map(String).sort(), [...initial].sort())) return
      place(order.map(String))
    }
  })
}
