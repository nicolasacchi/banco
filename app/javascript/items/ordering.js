// ordering: rows with Su and Giù buttons; Alt with the arrow keys moves the row
// that has the focus (E-03: keyboard first, no drag). The rows arrive in a server
// shuffle that is never the key or its reverse, with ids in shown order (X-01).
// The raw answer is JSON text: the shown ids in the order the student chose.
import { el, handle } from "items/dom"
import { renderInline } from "items/markup"

export function render(part, ctx) {
  const list = el("ol", { class: "ordering", "aria-label": ctx.t.ordering_label })
  const live = el("p", { class: "sr-only", role: "status", "aria-live": "polite" })
  const rows = (part.elements || []).map((element) => {
    const text = renderInline(element.text, el("span", { class: "row-text" }))
    const up = el("button", { type: "button", class: "button secondary small", text: ctx.t.ordering_up })
    const down = el("button", { type: "button", class: "button secondary small", text: ctx.t.ordering_down })
    const row = el("li", { class: "order-row", tabindex: "0", "data-id": element.id }, text, up, down)
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
    live.textContent = `${row.querySelector(".row-text").textContent}: ${Array.from(list.children).indexOf(row) + 1}`
  }

  const wrapper = el("div", { class: "answer" }, el("p", { class: "hint", text: ctx.t.ordering_label }), list, live)
  return handle(wrapper, {
    raw: () => JSON.stringify(Array.from(list.children).map((row) => row.getAttribute("data-id"))),
    isEmpty: () => false,
    focus: () => rows[0]?.focus()
  })
}
