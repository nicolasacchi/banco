// The Scene additions of the component contract v2 that draw.js needs (WAVE2 1.2), kept apart so that draw.js stays the core:
// shapes[].pattern (a fixed set of fills drawn in the role's colour: colour is never alone, A4), shapes[].target (a focusable hit area:
// one tab stop per figure, arrows move between targets, Enter or Space picks), controls() widgets (a stepper over values; a slider with its
// - and + buttons, A2), the legend list under a figure, and the print views of a figure (all states, a slider's first, middle and last).
// Pure DOM building, no layout: the types stay in lesson/diagrams/FAMILY/TYPE.js.
import { button, clear, el, svg, uid } from "lesson/dom"

export const PATTERNS = {
  hatch: (s) => [svg("path", { d: "M-2 10L10-2M-2 2L2-2M6 10L10 6", stroke: "currentColor", "stroke-width": s, fill: "none" })],
  dots: (s) => [svg("circle", { cx: 4, cy: 4, r: s * 0.9, fill: "currentColor" })],
  cross: (s) => [svg("path", { d: "M-2 10L10-2M-2-2L10 10", stroke: "currentColor", "stroke-width": s * 0.8, fill: "none" })],
  grid: (s) => [svg("path", { d: "M0 0H8M0 0V8", stroke: "currentColor", "stroke-width": s * 0.8, fill: "none" })]
}

// env.defs: one <pattern> per pattern, role and scale; env.scale: the scale of the group the shape is in (a pattern is in screen units).
export function patternRef(env, name, role) {
  const k = env.scale || 1
  const key = `${name}|${role}|${k.toFixed(3)}`
  if (!env.defs.has(key)) {
    const id = `${env.id}-p${env.defs.size}`
    const p = svg("pattern", { id, patternUnits: "userSpaceOnUse", width: 8, height: 8, patternTransform: `scale(${(1 / k).toFixed(4)})`, class: `dg-patdef role-${role}` })
    for (const node of PATTERNS[name]?.(1.6) ?? []) p.appendChild(node)
    env.defs.set(key, { id, node: p })
  }
  return `url(#${env.defs.get(key).id})`
}

export function defsNode(env) {
  const defs = svg("defs")
  for (const { node } of env.defs.values()) defs.appendChild(node)
  return defs
}

// A shape that is a select target: focusable, labelled "zona 3 di 12, a nord-ovest", one tab stop per figure (roving).
export function decorateTarget(node, shape) {
  node.setAttribute("class", `${node.getAttribute("class") ?? ""} dg-target`.trim())
  node.dataset.target = shape.target
  node.setAttribute("role", "button")
  node.setAttribute("tabindex", "-1")
  node.setAttribute("aria-pressed", "false")
  node.setAttribute("aria-label", shape.targetLabel ?? shape.target)
  node.setAttribute("focusable", "true")
}

// An invisible padded hit shape of a small target (at least 24 x 24 px): a click on it is a click on the target.
export function padHit(node, key) {
  node.setAttribute("class", `${node.getAttribute("class") ?? ""} dg-hitpad`.trim())
  node.dataset.hitFor = key
  node.setAttribute("aria-hidden", "true")
}

// Arrows move to the nearest target in that direction (reading order when none lies that way); Enter and Space pick; one tab stop.
// Returns refresh(selectedKey), which shows the pick without wiring again.
export function wireTargets(root, { selected, onPick }) {
  const nodes = [...root.querySelectorAll("[data-target]")]
  if (nodes.length === 0) return () => {}
  const keyOf = (n) => n.dataset.target
  const centre = (n) => {
    const r = n.getBoundingClientRect()
    return [r.left + r.width / 2, r.top + r.height / 2]
  }
  const refresh = (key) => {
    nodes.forEach((n) => {
      n.setAttribute("aria-pressed", keyOf(n) === key ? "true" : "false")
      n.classList.toggle("is-selected", keyOf(n) === key)
    })
  }
  for (const pad of root.querySelectorAll("[data-hit-for]")) {
    pad.addEventListener("click", () => nodes.find((n) => keyOf(n) === pad.dataset.hitFor)?.dispatchEvent(new MouseEvent("click", { bubbles: true })))
  }
  const stop = nodes.find((n) => keyOf(n) === selected) ?? nodes[0]
  nodes.forEach((n) => n.setAttribute("tabindex", n === stop ? "0" : "-1"))
  refresh(selected)
  const focusOn = (n) => {
    nodes.forEach((m) => m.setAttribute("tabindex", m === n ? "0" : "-1"))
    n.focus()
  }
  nodes.forEach((n, i) => {
    n.addEventListener("click", () => onPick(keyOf(n), refresh))
    n.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault()
        onPick(keyOf(n), refresh)
        return
      }
      const dir = { ArrowRight: [1, 0], ArrowLeft: [-1, 0], ArrowDown: [0, 1], ArrowUp: [0, -1] }[event.key]
      if (!dir) return
      event.preventDefault()
      const [cx, cy] = centre(n)
      let best = null
      let bestScore = Infinity
      for (const m of nodes) {
        if (m === n) continue
        const [mx, my] = centre(m)
        const along = (mx - cx) * dir[0] + (my - cy) * dir[1]
        const across = Math.abs((mx - cx) * dir[1] - (my - cy) * dir[0])
        if (along <= 0 || across > along * 1.5) continue // inside a cone of about 55 degrees
        const score = along + across * 2
        if (score < bestScore) {
          best = m
          bestScore = score
        }
      }
      focusOn(best ?? nodes[Math.max(0, Math.min(nodes.length - 1, i + (dir[0] + dir[1] > 0 ? 1 : -1)))])
    })
  })
  return refresh
}

// ---- the text of a control value --------------------------------------------------------------------------------------------------

export function formatValue(format, value) {
  switch (format) {
    case "year": return value < 0 ? `${-value} a.C.` : `${value} d.C.`
    case "lat": return value === 0 ? "0°" : `${Math.abs(value)}° ${value > 0 ? "N" : "S"}`
    case "alt": return `${value} m`
    default: return String(value)
  }
}

// controls() widgets. spec: { id, kind: stepper | slider, label_it, values? | range+step+stops?, format, initial, less_it?, more_it? };
// current: the value now; onChange(value). Returns the group node. A slider always has its - and + buttons; a stepper is the buttons
// and the value (A2: targets of 24 px at least, from the CSS).
export function controlNode(spec, current, onChange) {
  const id = uid("ctl")
  const group = el("div", { class: `dg-ctl dg-ctl-${spec.kind}`, role: "group", "aria-label": spec.label_it })
  const out = el("output", { class: "dg-ctlvalue", for: id, "aria-live": "off" })
  const show = (v) => {
    out.textContent = formatValue(spec.format, v)
  }
  const stops = spec.kind === "slider" ? spec.stops ?? [] : spec.values
  const less = spec.less_it ?? "Meno"
  const more = spec.more_it ?? "Più"
  let value = current
  const set = (v, fromInput = false) => {
    value = v
    show(v)
    if (input && !fromInput) input.value = String(v)
    minus.disabled = v <= low
    plus.disabled = v >= high
    onChange(v)
  }
  const low = stops.length ? stops[0] : spec.range[0]
  const high = stops.length ? stops[stops.length - 1] : spec.range[1]
  const stepTo = (dir) => {
    if (!stops.length) return Math.max(spec.range[0], Math.min(spec.range[1], value + dir * spec.step))
    if (dir > 0) return stops.find((x) => x > value) ?? stops[stops.length - 1]
    return [...stops].reverse().find((x) => x < value) ?? stops[0]
  }
  const minus = button("−", { class: "button secondary dg-ctlbtn", "aria-label": less }, () => set(stepTo(-1)))
  const plus = button("+", { class: "button secondary dg-ctlbtn", "aria-label": more }, () => set(stepTo(1)))
  let input = null
  group.appendChild(el("span", { class: "dg-ctllabel", text: spec.label_it }))
  group.appendChild(minus)
  if (spec.kind === "slider") {
    input = el("input", { id, type: "range", class: "dg-range", min: spec.range[0], max: spec.range[1], step: spec.step ?? 1, value: String(current), "aria-label": spec.label_it })
    input.addEventListener("input", () => set(Number(input.value), true))
    group.appendChild(input)
  }
  group.appendChild(plus)
  group.appendChild(out)
  show(current)
  minus.disabled = current <= low
  plus.disabled = current >= high
  return group
}

// ---- the legend list ---------------------------------------------------------------------------------------------------------------

function swatch(sw = {}) {
  const box = svg("svg", { class: "dg-swatch", width: 24, height: 24, viewBox: "0 0 24 24", "aria-hidden": "true", focusable: "false" })
  const role = sw.role ?? "muted"
  switch (sw.kind) {
    case "area": {
      box.appendChild(svg("rect", { x: 2, y: 4, width: 20, height: 16, rx: 3, class: `mk-${role} dg-swatch-fill` }))
      if (sw.pattern && sw.pattern !== "solid") {
        const env = { defs: new Map(), scale: 1, id: uid("sw") }
        const ref = patternRef(env, sw.pattern, role)
        box.appendChild(defsNode(env))
        box.appendChild(svg("rect", { x: 2, y: 4, width: 20, height: 16, rx: 3, fill: ref, class: "dg-swatch-pat" }))
      }
      break
    }
    case "line": box.appendChild(svg("path", { d: "M2 18C8 6 14 20 22 6", class: "dg-river dg-line-on", fill: "none" })); break
    case "route": box.appendChild(svg("path", { d: "M2 18L12 8L22 16", class: `dg-route st-${role}`, fill: "none" })); break
    case "point": box.appendChild(svg("polygon", { points: "12,5 19,12 12,19 5,12", class: "dg-point mk-muted" })); break
    case "place": box.appendChild(svg("circle", { cx: 12, cy: 12, r: 6, class: "dg-place" })); break
    case "beam": case "beam-move": box.appendChild(svg("polygon", { points: "2,6 22,9 22,15 2,18", class: `dg-beam${sw.kind === "beam-move" ? " dg-beam-move" : ""}` })); break
    default: break
  }
  return box
}

export function legendNode(items) {
  const ul = el("ul", { class: "dg-legend" })
  for (const it of items) {
    const li = el("li", { class: it.swatch?.kind === "note" ? "dg-legend-note" : "" })
    if (it.n !== undefined) li.appendChild(el("span", { class: "dg-legend-n", text: String(it.n) }))
    if (it.swatch && it.swatch.kind !== "note") li.appendChild(swatch(it.swatch))
    li.appendChild(el("span", { class: "dg-legend-text", text: it.text_it }))
    ul.appendChild(li)
  }
  return ul
}

export { clear }
