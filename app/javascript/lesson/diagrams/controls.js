// The controls a diagram type declares with controls(data) (WAVE2 1.2): [{ id, kind, range?, step?, values?, value?, label_it }].
// draw.js builds native controls from them. A slider is always drawn with its - and + buttons beside it (A2); a stepper is the - and +
// buttons with the value between; a toggle is one pressed/not-pressed button; chips are a group of buttons, one pressed.
// The values live in one object the figure hands to layout() as ctx.controls; every change calls onChange(values) and the figure redraws.
import { button, el } from "lesson/dom"

const num = (x) => Number(String(x).replace(",", "."))

// A control is a group: its label on a line of its own, then a row of buttons and the value (so that it fits a phone, where a label, two
// round buttons and a long value would not fit on one line).
function group(c, ...row) {
  return el("div", { class: `dg-ctl dg-ctl-${c.kind}`, role: "group", "aria-label": c.label_it }, el("span", { class: "dg-ctl-label", text: c.label_it }), el("div", { class: "dg-ctl-row" }, ...row))
}

function buttons(c, values, set, t) {
  const step = num(c.step)
  const minus = button("−", { class: "button secondary dg-ctl-btn", "aria-label": `${c.label_it}: ${t.chart_less ?? "meno"}` }, () => set(values[c.id] - step))
  const plus = button("+", { class: "button secondary dg-ctl-btn", "aria-label": `${c.label_it}: ${t.chart_more ?? "più"}` }, () => set(values[c.id] + step))
  return { minus, plus }
}

function slider(c, values, change, t) {
  const lo = num(c.range[0])
  const hi = num(c.range[1])
  const step = num(c.step)
  const input = el("input", { type: "range", min: lo, max: hi, step, value: values[c.id], class: "dg-range", "aria-label": c.label_it })
  const out = el("output", { class: "dg-rangevalue", "aria-live": "off" })
  const set = (v) => {
    values[c.id] = Math.max(lo, Math.min(hi, v))
    change()
  }
  const { minus, plus } = buttons(c, values, set, t)
  input.addEventListener("input", () => set(num(input.value)))
  return { node: group(c, minus, input, plus, out), sync: () => {
    input.value = String(values[c.id])
    out.textContent = String(values[c.id])
    minus.disabled = values[c.id] <= lo
    plus.disabled = values[c.id] >= hi
  } }
}

function stepper(c, values, change, t) {
  const lo = num(c.range[0])
  const hi = num(c.range[1])
  const step = num(c.step)
  const out = el("output", { class: "dg-ctl-value", "aria-live": "off" })
  const set = (v) => {
    values[c.id] = Math.max(lo, Math.min(hi, v))
    change()
  }
  const { minus, plus } = buttons(c, values, set, t)
  return { node: group(c, minus, out, plus), sync: () => {
    const v = values[c.id]
    out.textContent = c.values ? c.values[Math.round((v - lo) / step)] ?? String(v) : String(v)
    minus.disabled = v <= lo
    plus.disabled = v >= hi
  } }
}

function toggle(c, values, change) {
  const b = button(c.label_it, { class: "button secondary dg-toggle", "aria-pressed": String(Boolean(values[c.id])) }, () => {
    values[c.id] = !values[c.id]
    change()
  })
  return { node: b, sync: () => b.setAttribute("aria-pressed", String(Boolean(values[c.id]))) }
}

function chips(c, values, change) {
  const buttons = c.values.map((v) => button(String(v), { class: "button secondary dg-chip-button", "aria-pressed": "false" }, () => {
    values[c.id] = v
    change()
  }))
  const node = el("div", { class: "dg-chips", role: "group", "aria-label": c.label_it }, ...buttons)
  return { node, sync: () => buttons.forEach((b, i) => b.setAttribute("aria-pressed", String(c.values[i] === values[c.id]))) }
}

const KINDS = { slider, stepper, toggle, chips }

// Returns { nodes, values, sync } for the declared controls; nodes is a list of elements to put in the figure's control box.
export function buildControls(declared, onChange, t = {}) {
  const values = {}
  for (const c of declared) values[c.id] = c.value ?? (c.range ? num(c.range[0]) : c.kind === "toggle" ? false : c.values?.[0])
  const made = []
  const sync = () => made.forEach((m) => m.sync())
  const change = () => {
    sync()
    onChange(values)
  }
  for (const c of declared) {
    const make = KINDS[c.kind]
    if (make) made.push(make(c, values, change, t))
  }
  sync()
  return { nodes: made.map((m) => m.node), values, sync }
}
