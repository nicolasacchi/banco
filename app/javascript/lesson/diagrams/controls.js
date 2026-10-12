// The native controls of a figure (WAVE2 1.2, A1, A2): what a type's controls(data) declares, built by draw.js. The values live in one
// object { id: value } that layout() reads back as ctx.controls: a toggle is true once flipped, a stepper is a number (its `initial`
// until it is pressed). A control the scene gives a box to (scene.controls[id] = { x, y, w, h, label_it, on }) is a button laid over the
// drawing at that box (the bits of a register); the others sit in the strip under it.
//
// Optional fields of a declared control, beyond the contract's { id, kind, range?, values?, label_it }:
//   initial  the value before the first press (a stepper's range may start below it)
//   less_it, more_it  the words on a stepper's two buttons (default "−" and "+")
import { button, el } from "lesson/dom"
import { renderInlineRich } from "lesson/text"
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

// Chips (T4b): a group of buttons with aria-pressed; `multi` lets several be on at once. The values are lists in state.controls[id]
// ({ id: [value, ...] }); a type reads them from ctx.controls and draws from them.
export function buildChips(list, host, { state, ctx, redraw }) {
  for (const control of list) {
    if (control.kind !== "chips") continue
    const group = el("div", { class: "dg-chips", role: "group", "aria-label": control.label_it })
    const heading = el("span", { class: "dg-chips-label", text: control.label_it })
    const chips = control.values.map((v) => {
      const chip = button("", { class: "dg-chipbtn", "aria-pressed": "false" }, () => {
        const now = new Set(state.controls[control.id] ?? [])
        if (!control.multi) now.clear()
        if (now.has(v.value)) now.delete(v.value)
        else now.add(v.value)
        state.controls[control.id] = [...now]
        for (const other of chips) other.setAttribute("aria-pressed", String(now.has(other.dataset.value)))
        redraw()
      })
      chip.dataset.value = v.value
      renderInlineRich(v.label_it, chip, ctx)
      return chip
    })
    group.append(heading, ...chips)
    if (control.hint_it) group.append(el("span", { class: "dg-chips-hint", text: control.hint_it }))
    host.appendChild(group)
  }
}

// ---- the chart family's controls (T6) ---------------------------------------------------------------------------------------------------
// [{ id, kind, range?, step?, values?, value?, label_it }] with ranges and steps as text. A slider always comes with its - and + buttons (A2); a
// stepper is the - and + buttons with the value (or its name from `values`) between; a toggle is one pressed button; chips are a group, one pressed.
// The values live in one object the figure hands to layout() as ctx.controls; every change calls onChange(values) and the figure redraws.
const num = (x) => Number(String(x).replace(",", "."))

// A control is a group: its label on a line of its own, then a row of buttons and the value (so that it fits a phone, where a label, two
// round buttons and a long value would not fit on one line).
function valueGroup(c, ...row) {
  return el("div", { class: `dg-ctl dg-ctl-${c.kind}`, role: "group", "aria-label": c.label_it }, el("span", { class: "dg-ctl-label", text: c.label_it }), el("div", { class: "dg-ctl-row" }, ...row))
}

function valueButtons(c, values, set, t) {
  const step = num(c.step)
  const minus = button("−", { class: "button secondary dg-ctl-btn", "aria-label": `${c.label_it}: ${t.chart_less ?? "meno"}` }, () => set(values[c.id] - step))
  const plus = button("+", { class: "button secondary dg-ctl-btn", "aria-label": `${c.label_it}: ${t.chart_more ?? "più"}` }, () => set(values[c.id] + step))
  return { minus, plus }
}

function valueSlider(c, values, change, t) {
  const lo = num(c.range[0])
  const hi = num(c.range[1])
  const step = num(c.step)
  const input = el("input", { type: "range", min: lo, max: hi, step, value: values[c.id], class: "dg-range", "aria-label": c.label_it })
  const out = el("output", { class: "dg-rangevalue", "aria-live": "off" })
  const set = (v) => {
    values[c.id] = Math.max(lo, Math.min(hi, v))
    change()
  }
  const { minus, plus } = valueButtons(c, values, set, t)
  input.addEventListener("input", () => set(num(input.value)))
  return { node: valueGroup(c, minus, input, plus, out), sync: () => {
    input.value = String(values[c.id])
    out.textContent = String(values[c.id])
    minus.disabled = values[c.id] <= lo
    plus.disabled = values[c.id] >= hi
  } }
}

function valueStepper(c, values, change, t) {
  const lo = num(c.range[0])
  const hi = num(c.range[1])
  const step = num(c.step)
  const out = el("output", { class: "dg-ctl-value", "aria-live": "off" })
  const set = (v) => {
    values[c.id] = Math.max(lo, Math.min(hi, v))
    change()
  }
  const { minus, plus } = valueButtons(c, values, set, t)
  return { node: valueGroup(c, minus, out, plus), sync: () => {
    const v = values[c.id]
    out.textContent = c.values ? c.values[Math.round((v - lo) / step)] ?? String(v) : String(v)
    minus.disabled = v <= lo
    plus.disabled = v >= hi
  } }
}

function valueToggle(c, values, change) {
  const b = button(c.label_it, { class: "button secondary dg-toggle", "aria-pressed": String(Boolean(values[c.id])) }, () => {
    values[c.id] = !values[c.id]
    change()
  })
  return { node: b, sync: () => b.setAttribute("aria-pressed", String(Boolean(values[c.id]))) }
}

function valueChips(c, values, change) {
  const buttons = c.values.map((v) => button(String(v), { class: "button secondary dg-chip-button", "aria-pressed": "false" }, () => {
    values[c.id] = v
    change()
  }))
  const node = el("div", { class: "dg-chips", role: "group", "aria-label": c.label_it }, ...buttons)
  return { node, sync: () => buttons.forEach((b, i) => b.setAttribute("aria-pressed", String(c.values[i] === values[c.id]))) }
}

const VALUE_KINDS = { slider: valueSlider, stepper: valueStepper, toggle: valueToggle, chips: valueChips }

// Returns { nodes, values, sync } for the declared controls; nodes is a list of elements to put in the figure's control box.
export function buildValueControls(declared, onChange, t = {}) {
  const values = {}
  for (const c of declared) values[c.id] = c.value ?? (c.range ? num(c.range[0]) : c.kind === "toggle" ? false : c.values?.[0])
  const made = []
  const sync = () => made.forEach((m) => m.sync())
  const change = () => {
    sync()
    onChange(values)
  }
  for (const c of declared) {
    const make = VALUE_KINDS[c.kind]
    if (make) made.push(make(c, values, change, t))
  }
  sync()
  return { nodes: made.map((m) => m.node), values, sync }
}
