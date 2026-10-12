// The native controls of a figure (WAVE2 1.2, A1, A2): what a type's controls(data) declares, built by draw.js. The values live in one
// object { id: value } that layout() reads back as ctx.controls: a toggle is true once flipped, a stepper is a number (its `initial`
// until it is pressed). A control the scene gives a box to (scene.controls[id] = { x, y, w, h, label_it, on }) is a button laid over the
// drawing at that box (the bits of a register); the others sit in the strip under it.
//
// Optional fields of a declared control, beyond the contract's { id, kind, range?, values?, label_it }:
//   initial  the value before the first press (a stepper's range may start below it)
//   less_it, more_it  the words on a stepper's two buttons (default "−" and "+")
import { button, el } from "lesson/dom"
import { checkControls } from "lesson/diagrams/contract"

// The controls a module declares for a figure; [] for a module without or with an illegal list.
export function declared(mod, data) {
  try {
    const list = typeof mod?.controls === "function" ? mod.controls(data) : []
    return checkControls(list).length === 0 ? list : []
  } catch (_error) {
    return []
  }
}

const rangeOf = (c) => c.range ?? [0, 1]
export const valueOf = (c, store) => store[c.id] ?? c.initial ?? (c.kind === "toggle" ? false : rangeOf(c)[0])

// The strip under the figure: the steppers (and the toggles that have no box in the scene). Built once; `refresh` disables what is at its limit.
export function buildStrip(list, host, store, ctx, press) {
  const nodes = []
  for (const c of list) {
    if (c.kind === "stepper") {
      const [lo, hi] = rangeOf(c)
      const less = button(c.less_it ?? "−", { class: "button secondary dg-step dg-round", "aria-label": c.less_it ?? ctx.t.control_less, "data-control": c.id })
      const more = button(c.more_it ?? "+", { class: "button secondary dg-step dg-round", "aria-label": c.more_it ?? ctx.t.control_more, "data-control": c.id })
      if (c.less_it) less.classList.remove("dg-round")
      if (c.more_it) more.classList.remove("dg-round")
      less.addEventListener("click", () => press(c, Math.max(lo, valueOf(c, store) - 1)))
      more.addEventListener("click", () => press(c, Math.min(hi, valueOf(c, store) + 1)))
      const group = el("div", { class: "dg-stepper", role: "group", "aria-label": c.label_it }, el("span", { class: "dg-steplabel", text: c.label_it }), less, more)
      host.appendChild(group)
      nodes.push({ c, less, more, group })
    }
  }
  return {
    refresh() {
      for (const { c, less, more } of nodes) {
        const [lo, hi] = rangeOf(c)
        const v = valueOf(c, store)
        less.disabled = v <= lo
        more.disabled = v >= hi
      }
    }
  }
}

// The buttons laid over the drawing, in a layer of their own that outlives each redraw: a button is made once per control and only moved and
// relabelled afterwards, so a keyboard user keeps the focus. `box` comes from the scene. They are one group with one tab stop (A1): the button
// `rove.id` holds it (the first when none does), the arrow keys, Home and End move between the buttons, Space and Enter flip one.
export function overlay(scene, list, layer, store, press, rove = { id: null }) {
  const made = []
  const wanted = new Set()
  for (const c of list) {
    const box = scene.controls?.[c.id]
    if (!box || (c.kind !== "toggle" && c.kind !== "tap")) continue
    wanted.add(c.id)
    let b = [...layer.children].find((node) => node.dataset.control === c.id)
    if (!b) {
      b = el("button", { type: "button", class: "dg-switch", role: "switch", "data-control": c.id, tabindex: "-1" })
      b.addEventListener("click", () => press(c, !valueOf(c, store)))
      b.addEventListener("focus", () => {
        rove.id = c.id
        for (const other of layer.children) other.tabIndex = other === b ? 0 : -1
      })
      layer.appendChild(b)
      layer.setAttribute("role", "group")
      layer.setAttribute("aria-label", c.label_it)
    }
    b.setAttribute("aria-checked", String(Boolean(box.on)))
    b.setAttribute("aria-label", box.label_it ?? c.label_it)
    b.style.left = `${box.x}px`
    b.style.top = `${box.y}px`
    b.style.width = `${box.w}px`
    b.style.height = `${box.h}px`
    made.push(b)
  }
  for (const node of [...layer.children]) if (!wanted.has(node.dataset.control)) node.remove()
  const keep = made.find((b) => b.dataset.control === rove.id) ?? made[0]
  for (const b of made) b.tabIndex = b === keep ? 0 : -1
  if (!layer.dataset.keys) {
    layer.dataset.keys = "1"
    layer.addEventListener("keydown", (event) => {
      const items = [...layer.children]
      const i = items.indexOf(event.target)
      if (i < 0) return
      const to = { ArrowRight: i + 1, ArrowDown: i + 1, ArrowLeft: i - 1, ArrowUp: i - 1, Home: 0, End: items.length - 1 }[event.key]
      if (to === undefined || to < 0 || to >= items.length) return
      event.preventDefault()
      items[to].focus()
    })
  }
  return made
}
