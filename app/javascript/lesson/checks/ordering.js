// check component ordering (WAVE2 2.11, T1): put the items in order. Every item is in the list from the start, in the served (shuffled) order,
// under fresh ids (e1..eN); each has "Su" and "Giù" buttons (native, 24 px at least); Controlla sends the ids in the order the list has now and
// the server grades the sequence. Nothing is drag-only: the buttons are the interaction, the keys Alt+ArrowUp/ArrowDown on an item do the same.
import { handle } from "items/dom"
import { el, svg } from "lesson/dom"
import { renderInlineRich } from "lesson/text"
import { createOrdering } from "lesson/checks/sequence_model"

export const type = "ordering"

const fill = (template, values) => String(template).replace(/%\{(\w+)\}/g, (_, k) => values[k] ?? "")

// a chevron drawn here (no sprite name): up or down
function chevron(up) {
  const s = svg("svg", { class: "ic order-chevron", viewBox: "0 0 24 24", "aria-hidden": "true", focusable: "false" })
  s.appendChild(svg("path", { d: up ? "m6 15 6-6 6 6" : "m6 9 6 6 6-6", fill: "none", stroke: "currentColor", "stroke-width": 3, "stroke-linecap": "round", "stroke-linejoin": "round" }))
  return s
}

export function buildOrdering(spec, ctx, options = {}) {
  const texts = ctx.t.checks
  const model = createOrdering(spec.items.map((i) => i.id))
  const byId = new Map(spec.items.map((i) => [i.id, i]))
  const list = el("ol", { class: "order-list", "aria-label": options.label ?? texts.order_list })
  const live = el("p", { class: "sr-only", role: "status", "aria-live": "polite" })
  const root = el("div", { class: "answer ordering", "data-component": "ordering" }, list, live)
  const result = { element: root, ids: () => model.order(), focus: () => list.querySelector("button:not(:disabled)")?.focus(), onChange: options.onChange }

  function move(id, delta, keep) {
    model.move(id, delta)
    draw(keep ?? id, delta)
    live.textContent = fill(texts.order_moved, { n: model.order().indexOf(id) + 1, total: spec.items.length })
    options.onChange?.()
  }

  function draw(focusId = null, direction = 0) {
    list.replaceChildren()
    const order = model.order()
    order.forEach((id, i) => {
      const item = byId.get(id)
      const label = (key) => fill(texts[key], { text: item.text_it })
      const up = el("button", { type: "button", class: "order-move order-up", "data-id": id, "aria-label": label("order_up"), disabled: i === 0 ? "" : null }, chevron(true))
      const down = el("button", { type: "button", class: "order-move order-down", "data-id": id, "aria-label": label("order_down"), disabled: i === order.length - 1 ? "" : null }, chevron(false))
      up.addEventListener("click", () => move(id, -1))
      down.addEventListener("click", () => move(id, 1))
      const text = renderInlineRich(item.text_it, el("span", { class: "order-text" }), ctx)
      const li = el("li", { class: "order-item", "data-id": id }, el("span", { class: "order-pos", "aria-hidden": "true", text: String(i + 1) }), text, el("span", { class: "order-moves" }, up, down))
      li.addEventListener("keydown", (event) => {
        if (!event.altKey || (event.key !== "ArrowUp" && event.key !== "ArrowDown")) return
        event.preventDefault()
        move(id, event.key === "ArrowUp" ? -1 : 1)
      })
      list.appendChild(li)
    })
    if (focusId) {
      const i = model.order().indexOf(focusId)
      const li = list.children[i]
      // keep the focus on the same button; at an end that button is disabled, so the other one takes it
      const preferred = li?.querySelector(direction < 0 ? ".order-up" : ".order-down")
      ;(preferred && !preferred.disabled ? preferred : li?.querySelector("button:not(:disabled)"))?.focus()
    }
  }
  draw()
  return result
}

export function render(spec, ctx, _hooks) {
  const input = buildOrdering(spec, ctx)
  return handle(input.element, { raw: () => JSON.stringify(input.ids()), isEmpty: () => false, focus: input.focus })
}
