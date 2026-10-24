// Turns a Scene (A7 renderer contract) into a figure: SVG for shapes (createElementNS, classes only), an
// HTML layer for labels (real text, KaTeX, selectable, read by screen readers), the controls of the type
// (Avanti through states, the balance's number stepper, tapping a part of a sentence), the text
// alternative and a "Descrizione". The layout is computed at the container's width with the body font
// size and again on resize. If layout() answers { error } the figure shows alt_it and the description.
import * as N from "lesson/num"
import { button, clear, el, icon, spriteHref, svg, uid } from "lesson/dom"
import { FAMILY, HOME_PALETTE, STATUS, describe, layout, load, moduleFor, stateCount } from "lesson/diagrams/registry"
import { tryValues, equationTex } from "lesson/diagrams/balance"
import { buildChips, buildStrip, buildValueControls, declared, overlay } from "lesson/diagrams/controls"
import { renderInlineRich, renderMath, renderRich } from "lesson/text"
import { tableNode } from "lesson/blocks/table"
import { defaultSegments } from "lesson/diagrams/contract"
import { nearest, targetLabel } from "lesson/checks/select_model"
import { controlNode, decorateTarget, defsNode, legendNode, padHit, patternRef, wireTargets } from "lesson/diagrams/scene_extras"

const MARKERS = {
  // shapes of the palette (A6), drawn in a w x h box at x, y
  box: (m) => [svg("rect", { x: m.x + 1, y: m.y + 1, width: m.w - 2, height: m.h - 2, rx: 6, class: m.cls })],
  weight: (m) => [
    svg("path", { d: `M${m.x + m.w * 0.2},${m.y + m.h - 2} L${m.x + m.w * 0.32},${m.y + m.h * 0.38} H${m.x + m.w * 0.68} L${m.x + m.w * 0.8},${m.y + m.h - 2} Z`, class: m.cls }),
    svg("circle", { cx: m.x + m.w / 2, cy: m.y + m.h * 0.24, r: m.w * 0.17, class: `${m.cls} dg-knob` })
  ],
  circle: (m) => [svg("circle", { cx: m.x + m.w / 2, cy: m.y + m.h / 2, r: Math.min(m.w, m.h) / 2 - 1, class: m.cls })],
  square: (m) => [svg("rect", { x: m.x + 2, y: m.y + 2, width: m.w - 4, height: m.h - 4, class: m.cls })],
  triangle: (m) => [svg("polygon", { points: `${m.x + m.w / 2},${m.y + 1} ${m.x + m.w - 1},${m.y + m.h - 1} ${m.x + 1},${m.y + m.h - 1}`, class: m.cls })],
  diamond: (m) => [svg("polygon", { points: `${m.x + m.w / 2},${m.y + 1} ${m.x + m.w - 1},${m.y + m.h / 2} ${m.x + m.w / 2},${m.y + m.h - 1} ${m.x + 1},${m.y + m.h / 2}`, class: m.cls })],
  // ring and star: the shapes of palette v2 roles (an open circle; a five-pointed star)
  ring: (m) => [svg("circle", { cx: m.x + m.w / 2, cy: m.y + m.h / 2, r: Math.min(m.w, m.h) / 2 - 2, class: m.cls, fill: "none", "stroke-width": 3 })],
  star: (m) => [svg("polygon", { points: [0, 1, 2, 3, 4].map((i) => { const a = (-90 + i * 144) * Math.PI / 180; return `${m.x + m.w / 2 + Math.cos(a) * (m.w / 2 - 1)},${m.y + m.h / 2 + Math.sin(a) * (m.h / 2 - 1)}` }).join(" "), class: m.cls })],
  // pentagon: the sugar of a nucleotide (palette v2)
  pentagon: (m) => [svg("polygon", { points: [[0.5, 0.04], [0.96, 0.38], [0.79, 0.94], [0.21, 0.94], [0.04, 0.38]].map(([fx, fy]) => `${m.x + m.w * fx},${m.y + m.h * fy}`).join(" "), class: m.cls })]
}

// The fixed patterns of a Scene (WAVE2 1.2, shapes[].pattern) of the chart family (T6): hatch, dots, cross, grid. A shape with a pattern is drawn over
// its base fill, in the text colour. (The map family's path patterns are made by scene_extras.patternRef.)
const PATTERNS = {
  hatch: (id) => svg("pattern", { id, width: 8, height: 8, patternUnits: "userSpaceOnUse", patternTransform: "rotate(45)" }, ),
  dots: (id) => svg("pattern", { id, width: 7, height: 7, patternUnits: "userSpaceOnUse" }),
  cross: (id) => svg("pattern", { id, width: 9, height: 9, patternUnits: "userSpaceOnUse" }),
  grid: (id) => svg("pattern", { id, width: 8, height: 8, patternUnits: "userSpaceOnUse" })
}
const PATTERN_PARTS = {
  hatch: () => [svg("line", { x1: 0, y1: 0, x2: 0, y2: 8, class: "dg-patink", "stroke-width": 2.5 })],
  dots: () => [svg("circle", { cx: 3.5, cy: 3.5, r: 1.4, class: "dg-patfill" })],
  cross: () => [svg("line", { x1: 0, y1: 0, x2: 9, y2: 9, class: "dg-patink", "stroke-width": 1.6 }), svg("line", { x1: 9, y1: 0, x2: 0, y2: 9, class: "dg-patink", "stroke-width": 1.6 })],
  grid: () => [svg("path", { d: "M0,0 H8 M0,0 V8", class: "dg-patink", "stroke-width": 1.4 })]
}
export function patternDefs(prefix) {
  const defs = svg("defs")
  for (const name of Object.keys(PATTERNS)) {
    const p = PATTERNS[name](`${prefix}-${name}`)
    for (const part of PATTERN_PARTS[name]()) p.appendChild(part)
    defs.appendChild(p)
  }
  return defs
}

// env: { defs, scale, id } for the patterns of this scene (scene_extras.patternRef); scale is the scale of the group a shape is in.
function shapeNode(s, env = null) {
  const nodes = shapeNodeBase(s, env)
  // the chart family's patterns (T6): a fixed set of <pattern> defs per figure (patternDefs), filled in over the shape's own class
  if (s.pattern && s.pattern !== "solid" && s.kind !== "path" && env?.patId) for (const n of nodes) n.style.fill = `url(#${env.patId}-${s.pattern})`
  if (s.target && nodes[0] && !env?.selectHandled) decorateTarget(nodes[0], s)
  // a select check names its targets on the shape wherever it sits: a map draws its zones inside a scaled group, not at the top (D-319)
  else if (s.target && nodes[0]) nodes[0].dataset.target = s.target
  if (s.hitFor && nodes[0]) padHit(nodes[0], s.hitFor)
  return nodes
}

function shapeNodeBase(s, env) {
  switch (s.kind) {
    case "line": return [svg("line", { x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2, class: s.cls })]
    case "rect": return [svg("rect", { x: s.x, y: s.y, width: s.w, height: s.h, rx: s.r ?? 0, class: s.cls })]
    case "circle": return [svg("circle", { cx: s.cx, cy: s.cy, r: s.r, class: s.cls })]
    case "path": {
      const nodes = [svg("path", { d: s.d, class: s.cls, "fill-rule": s.fillRule })]
      // a pattern as well as a colour (A4): a second path over the first, filled with the role's pattern
      if (s.pattern && s.pattern !== "solid" && env) nodes.push(svg("path", { d: s.d, class: "dg-pat", fill: patternRef(env, s.pattern, s.role ?? "muted"), "fill-rule": s.fillRule, "pointer-events": "none" }))
      return nodes
    }
    case "ellipse": return [svg("ellipse", { cx: s.cx, cy: s.cy, rx: s.rx, ry: s.ry, class: s.cls })]
    case "text": {
      const t = svg("text", { x: s.x, y: s.y, "text-anchor": "middle", class: s.cls, style: `font-size:${s.px}px` })
      t.textContent = s.text
      return [t]
    }
    case "group": {
      // a group that can move: `at` places it, `move` { tx, ty, rot, ox, oy } is what draw() animates from the last state
      // `scale` scales the group's own units (a map's viewBox) to the stage: paths keep their coordinates, strokes stay in screen pixels (CSS)
      const outer = svg("g", { class: s.cls ?? "", transform: s.at ? `translate(${s.at[0]},${s.at[1]})${s.scale ? ` scale(${s.scale})` : ""}` : undefined })
      const inner = svg("g", { class: "dg-move" })
      const inside = env ? { ...env, scale: (env.scale || 1) * (s.scale ?? 1) } : null
      for (const child of s.children ?? []) for (const node of shapeNode(child, inside)) inner.appendChild(node)
      outer.appendChild(inner)
      outer.__inner = inner
      return [outer]
    }
    case "polygon": return [svg("polygon", { points: s.points.map((p) => p.map((v) => Math.round(v * 10) / 10).join(",")).join(" "), class: s.cls })]
    case "marker": return (MARKERS[s.shape] ?? MARKERS.circle)(s)
    case "icon": {
      const g = svg("svg", { x: s.x, y: s.y, width: s.size, height: s.size, viewBox: "0 0 24 24", class: `dg-icon ${s.cls ?? ""}`, "aria-hidden": "true" })
      g.appendChild(svg("use", { href: spriteHref(s.name) }))
      return [g]
    }
    default: return []
  }
}

const moveCss = (m) => `translate(${(m.tx ?? 0).toFixed(2)}px, ${(m.ty ?? 0).toFixed(2)}px) rotate(${(m.rot ?? 0).toFixed(2)}deg)`

export function makeMeasure(host, ctx) {
  const probe = el("span", { class: "dg-measure", "aria-hidden": "true" })
  host.appendChild(probe)
  const cache = new Map()
  const self = { degenerate: false }
  const measure = (text, px, maxW, cls = "") => {
    const key = `${px}|${maxW ?? ""}|${cls}|${text}`
    if (cache.has(key)) return cache.get(key)
    clear(probe)
    // the label's own classes (bold compass, plate words) change the width: the probe wears them
    probe.className = cls ? `dg-measure dg-label ${cls}` : "dg-measure"
    probe.style.fontSize = `${px}px`
    probe.style.maxWidth = maxW ? `${maxW}px` : "none"
    probe.style.whiteSpace = maxW ? "normal" : "nowrap"
    probe.style.width = maxW ? `${maxW}px` : "auto"
    renderInlineRich(text, probe, ctx)
    const rect = probe.getBoundingClientRect()
    const result = { w: Math.ceil(rect.width), h: Math.ceil(rect.height) }
    // a hidden host (a card not shown, display: none) measures every text as 0 x 0: never cached, and the figure draws again when it shows
    if (rect.width === 0 && rect.height === 0 && String(text).trim() !== "") {
      self.degenerate = true
      return result
    }
    // with a width given the box is that wide; the text may be narrower: shrink to the widest line
    if (maxW) {
      probe.style.width = "auto"
      probe.style.whiteSpace = "normal"
      probe.style.display = "inline-block"
      result.w = Math.min(maxW, Math.ceil(probe.getBoundingClientRect().width))
      probe.style.display = ""
    }
    cache.set(key, result)
    return result
  }
  return Object.assign(self, { measure, probe, drop: () => probe.remove() })
}

// FLIP: the elements of the new scene that had the same key in the old one start where they were.
function animate(oldBoxes, root, reduced) {
  if (reduced || oldBoxes.size === 0) return
  const moved = []
  for (const node of root.querySelectorAll("[data-key]")) {
    const before = oldBoxes.get(node.dataset.key)
    if (!before) continue
    const now = node.getBoundingClientRect()
    const dx = before.left - now.left
    const dy = before.top - now.top
    if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) continue
    node.style.transition = "none"
    node.style.transform = `translate(${dx}px, ${dy}px)`
    moved.push(node)
  }
  if (moved.length === 0) return
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      for (const node of moved) {
        node.style.transition = "transform 250ms ease"
        node.style.transform = ""
      }
    })
  })
}

// The figure. data: the diagram (already merged states, A2). options: ctx (subject, fontPx(), reduced(), t),
// hero: a larger cover drawing.
export function mountDiagram(data, ctx, options = {}) {
  const type = data?.type
  // ctx.mode of the component contract (WAVE2 1.2): "select" draws the figure of a select check with tap targets (options.select)
  const mode = options.mode ?? "student"
  const id = uid("dg")
  const figure = el("figure", { class: `dg dg-${type} dg-size-${data?.size ?? "m"}${options.hero ? " dg-hero" : ""}${options.compact ? " dg-compact" : ""}`, "data-type": type })
  // a type with a home palette draws in its subject's colours whatever the lesson's subject (WAVE2 1.3)
  if (HOME_PALETTE[type]) figure.dataset.palette = HOME_PALETTE[type]
  const stage = el("div", { class: "dg-stage" })
  const labelsLayer = el("div", { class: "dg-labels" })
  const stageSvg = svg("svg", { class: "dg-svg", role: "img", "aria-labelledby": `${id}-alt`, focusable: "false" })
  const alt = el("span", { id: `${id}-alt`, class: "sr-only", text: data?.alt_it ?? "" })
  // the buttons of a figure's controls (the bits of a register) live in a layer that a redraw does not clear, so they keep the focus
  const switchLayer = el("div", { class: "dg-switches" })
  stage.append(stageSvg, labelsLayer, switchLayer)
  const controls = el("div", { class: "dg-controls" })
  const op = el("p", { class: "dg-op", "aria-live": "polite" })
  const question = el("p", { class: "dg-question", "aria-live": "polite" })
  const caption = data?.caption_it ? el("figcaption", { class: "dg-caption" }) : null
  if (caption) renderInlineRich(data.caption_it, caption, ctx)
  const descText = el("p", { text: describe(data, { subject: ctx.subject, state: 0, mode: options.mode ?? "student", set: options.set ?? null }) })
  const desc = el("details", { class: "dg-desc" }, el("summary", {}, icon("description"), document.createTextNode(` ${ctx.t.description}`)), descText)
  // the numbers under a chart ("Vedi i numeri", WAVE2 P2): opened by the student, always printed
  const valuesBox = el("details", { class: "dg-values", hidden: "" }) // hidden until a scene has numbers: an empty <details> would print the browser's English "Details"
  const renderValues = (scene) => {
    if (!scene.values) {
      valuesBox.hidden = true
      return
    }
    valuesBox.hidden = false
    const t = tableNode({ header: scene.values.header, rows: scene.values.rows }, ctx)
    valuesBox.replaceChildren(el("summary", {}, document.createTextNode(ctx.t.chart_see_numbers ?? "Vedi i numeri")), t, ...(scene.source ? [el("p", { class: "dg-source", text: (ctx.t.chart_source ?? "Fonte: %{source}").replace("%{source}", scene.source) })] : []))
  }
  // a balance has its equation, the state's name and a status chip above the drawing
  const top = type === "balance" ? el("div", { class: "dg-top" }) : null
  const pill = el("span", { class: "dg-pill" })
  const eqLine = el("div", { class: "dg-eq", "aria-hidden": "true" })
  const chip = el("span", { class: "dg-status", role: "status" })
  if (top) top.append(pill, eqLine, chip)
  // op, question and controls sit in one side box: below the drawing, or beside it on a wide balance (CSS)
  const side = el("div", { class: "dg-side" }, op, question, controls)
  // the legend list under a figure that has one, and the print views of a figure that prints more than its current state (wave 2)
  const legendHost = el("div", { class: "dg-legendhost" })
  const printHost = el("div", { class: "dg-print", "aria-hidden": "true" })
  // what a control just did, said once and politely (A6): spoken only (sr-only)
  const live = el("p", { class: "sr-only dg-live", "aria-live": "polite", role: "status" })
  side.appendChild(live)
  figure.append(alt, ...(top ? [top] : []), stage, side, valuesBox, legendHost, ...(caption ? [caption] : []), desc, printHost)

  let mod = moduleFor(type)
  // the states of the figure: fixed, except for an example's linked figure, which the server completes after a blank (replaceData below)
  let total = mod || STATUS[type] ? stateCount(data) : 1
  const state = { moves: new Map(), lastWidth: 0, i: 0, tryValue: data?.try && data?.type === "balance" ? Number(data.try.from) : undefined, width: 0, selected: null, controls: {}, announce: false, printWidth: 0 }
  // two kinds of controls: the toggles and plain steppers of controls.js (bits laid over the drawing, a strip under it), and the sliders and
  // steppers over a list of `values` of syncControls below. The first are `wanted`, built once the module is known.
  // the chart family (T6) declares its sliders and its stepper over names in its own dialect (ranges as text, `value`): controls.js builds
  // those whole, with the values as declared, and the other kinds below stay out of their way
  const own = FAMILY[type] === "chart"
  let made = null
  const isStrip = (c) => c.kind === "toggle" || (c.kind === "stepper" && !c.values)
  let wanted = []
  let strip = null
  const rove = { id: null }
  const press = (control, value) => {
    state.controls[control.id] = value
    state.announce = true
    draw()
  }
  let stripBuilt = false
  const setupStrip = () => {
    if (stripBuilt || !mod) return // once, as soon as the module is known (a lazy type loads after the mount)
    stripBuilt = true
    if (own) {
      const list = declared(mod, data)
      made = list.length ? buildValueControls(list, () => { state.announce = true; draw() }, ctx.t) : null
      if (made) {
        state.controls = made.values
        controls.append(...made.nodes)
      }
      return
    }
    wanted = declared(mod, data).filter(isStrip)
    strip = wanted.length ? buildStrip(wanted, controls, state.controls, ctx, press) : null
    // a select check's figure has no chips, as it has no value controls (syncControls): its served data may lack the options that turn them off
    // (the select projection of `cell` drops `labels`), and a chip there would light, filter or grey candidates (L3)
    if (mode !== "select") buildChips(declared(mod, data), controls, { state, ctx, redraw: () => { state.announce = true; draw() } })
  }
  const resetControls = () => {
    for (const c of wanted) delete state.controls[c.id]
  }
  setupStrip()
  figure.dataset.states = String(total)
  if (total > 1 || (type === "sentence" && data.parts)) figure.dataset.nokeys = ""
  const measurer = { current: null }
  // What the voice reads for this figure (WAVE2 4.3, L10): the type's speechSegments, else its description, of the state shown now. The walker of
  // lesson/speech.js calls this instead of reading the drawing's labels.
  figure.speechSegments = () => {
    const spoken = { subject: ctx.subject, state: state.i, mode, set: options.set ?? null, controls: state.controls, revealed: [] }
    try {
      if (typeof mod?.speechSegments === "function") return mod.speechSegments(data, spoken)
      return defaultSegments(describe, data, spoken)
    } catch (_error) {
      return []
    }
  }

  const showError = (error) => {
    clear(stageSvg)
    clear(labelsLayer)
    stageSvg.setAttribute("height", "0")
    figure.classList.add("dg-failed")
    if (!figure.querySelector(".dg-fallback")) {
      figure.insertBefore(el("p", { class: "dg-fallback", text: data?.alt_it ?? "" }), stage)
    }
    desc.open = true
    figure.dataset.error = `${error.code ?? ""} ${error.path ?? ""} ${error.message ?? ""}`.trim()
  }

  const draw = () => {
    const width = Math.floor(stage.clientWidth || figure.clientWidth || options.width || 320)
    if (width < 10) return
    state.width = width
    // the ready state of the figure (the system tests wait on it): how many times it was drawn and at which width; `settling` while a resize is waiting to be drawn
    figure.dataset.drawn = String(Number(figure.dataset.drawn ?? 0) + 1)
    figure.dataset.drawnWidth = String(width)
    if (!measurer.current) measurer.current = makeMeasure(stage, ctx)
    const fontPx = ctx.fontPx()
    measurer.current.degenerate = false
    syncControls()
    const scene = layout(data, { width, fontPx, measure: measurer.current.measure, subject: ctx.subject, state: state.i, tryValue: state.tryValue, mode, set: options.set ?? null, controls: state.controls, revealed: [] })
    if (scene.error) return showError(scene.error)
    figure.classList.remove("dg-failed")
    figure.querySelector(".dg-fallback")?.remove()
    delete figure.dataset.error
    const old = new Map()
    for (const node of figure.querySelectorAll("[data-key]")) old.set(node.dataset.key, node.getBoundingClientRect())

    if (scene.table) {
      clear(stageSvg)
      stageSvg.setAttribute("height", "0")
      clear(labelsLayer)
      labelsLayer.classList.add("dg-tablewrap")
      labelsLayer.appendChild(tableNode(scene.table, ctx))
      return
    }
    labelsLayer.classList.remove("dg-tablewrap")
    clear(stageSvg)
    clear(labelsLayer)
    if (scene.shapes.some((sh) => sh.pattern)) stageSvg.appendChild(patternDefs(`${id}-p`))
    stageSvg.setAttribute("viewBox", `0 0 ${scene.width} ${scene.height}`)
    stageSvg.setAttribute("width", String(scene.width))
    stageSvg.setAttribute("height", String(scene.height))
    stage.style.height = `${scene.height}px`
    const moves = new Map()
    const animated = []
    const sameWidth = state.lastWidth === scene.width
    const env = { defs: new Map(), scale: 1, id: figure.id || id, patId: `${id}-p`, selectHandled: mode === "select" && !!options.select }
    scene.shapes.forEach((s) => {
      for (const node of shapeNode(s, env)) {
        if (s.key && s.kind !== "group") node.dataset.key = s.key
        if (s.target && mode === "select") node.dataset.target = s.target
        stageSvg.appendChild(node)
        if (s.kind === "group" && s.move && node.__inner) {
          const inner = node.__inner
          if (s.move.ox !== undefined) inner.style.transformOrigin = `${s.move.ox}px ${s.move.oy}px`
          const before = state.moves.get(s.key)
          moves.set(s.key, s.move)
          if (before && sameWidth && !ctx.reduced() && moveCss(before) !== moveCss(s.move)) {
            inner.style.transform = moveCss(before)
            animated.push([inner, s.move])
          } else inner.style.transform = moveCss(s.move)
        }
      }
    })
    if (env.defs.size) stageSvg.insertBefore(defsNode(env), stageSvg.firstChild)
    state.moves = moves
    state.lastWidth = scene.width
    if (animated.length) {
      stageSvg.getBoundingClientRect() // the start position is laid out before the move
      requestAnimationFrame(() => animated.forEach(([node, move]) => { node.style.transform = moveCss(move) }))
    }
    for (const l of scene.labels) {
      const node = el("div", { class: `dg-label ${l.cls} dg-a-${l.anchor}${l.wrap ? " dg-wrap" : ""}` })
      node.style.left = `${l.x}px`
      node.style.top = `${l.y}px`
      node.style.width = `${l.w + (l.wrap ? 0 : 2)}px`
      node.style.fontSize = `${l.px}px`
      renderInlineRich(l.text_it, node, ctx)
      if (l.key) node.dataset.key = l.key
      if (l.lang) node.setAttribute("lang", l.lang)
      labelsLayer.appendChild(node)
    }
    // wave 2: the legend list, the select targets, the description of the visible state, the live sentence of a control
    clear(legendHost)
    if (scene.legend?.length) legendHost.appendChild(legendNode(scene.legend))
    if (scene.targets?.length && !(mode === "select" && options.select)) { // a select check's own buttons (selectTargets) stand in for these
      wireTargets(stageSvg, {
        selected: state.picked,
        onPick: (key, refresh) => {
          state.picked = state.picked === key ? null : key
          refresh(state.picked)
          figure.dispatchEvent(new CustomEvent("dg:target", { bubbles: true, detail: { key: state.picked } }))
        }
      })
    }
    descText.textContent = describe(data, { subject: ctx.subject, state: state.i, mode, set: options.set ?? null, controls: state.controls, revealed: [] })
    if (state.announce && scene.live) live.textContent = scene.live
    state.announce = false
    if (mod?.printViews && state.printWidth !== width) paintPrint(width, fontPx)
    const hitButtons = new Map()
    for (const h of scene.hits ?? []) {
      const b = el("button", { type: "button", class: "dg-hit", "aria-pressed": state.selected === h.id ? "true" : "false", "aria-label": `${h.name}: ${h.text}${h.hint_it ? `. ${h.hint_it}` : h.question_it ? `. ${ctx.t.tap_for_question}` : ""}` })
      b.style.left = `${h.x}px`
      b.style.top = `${h.y}px`
      b.style.width = `${h.w}px`
      b.style.height = `${h.h}px`
      b.dataset.key = `${h.key}:hit`
      b.addEventListener("click", () => {
        state.selected = h.id
        question.textContent = h.note_it ? `${h.name}: ${h.note_it}` : h.question_it ? `${h.name}: ${h.question_it}` : `${h.name}.`
        for (const other of labelsLayer.querySelectorAll(".dg-hit")) other.setAttribute("aria-pressed", String(other === b))
      })
      labelsLayer.appendChild(b)
      hitButtons.set(h.key, b)
    }
    // a shape that stands for a hit (shapes[].hitFor is the hit's key: every shape of a cell's part, and its invisible pads) reads it when tapped,
    // as the hit's own button does: the button is the keyboard's and the screen reader's way in, the shapes are the finger's
    if (hitButtons.size) {
      for (const node of stageSvg.querySelectorAll("[data-hit-for]")) {
        const b = hitButtons.get(node.dataset.hitFor)
        if (b) node.addEventListener("click", () => b.click())
      }
    }
    if (mode === "select" && options.select) selectTargets()
    if (strip) {
      overlay(scene, wanted, switchLayer, state.controls, press, rove)
      strip.refresh()
    }
    renderValues(scene)
    op.textContent = ""
    const eff = total > 1 ? (data.states[state.i] ?? {}) : {}
    if (eff.op_it) renderInlineRich(eff.op_it, op, ctx)
    if (top) {
      eqLine.replaceChildren(renderMath(equationTex(data, state.i), el("span", { class: "dg-eqtex" }), ctx, true))
      pill.textContent = total > 1 ? ctx.t.balance_of.replace("%{n}", state.i + 1).replace("%{total}", total) : ctx.t.balance_one
      const tilt = scene.tilt
      chip.className = `dg-status ${tilt === 0 ? "is-level" : "is-tilt"}`
      chip.replaceChildren(icon(tilt === 0 ? "check" : "scale"), document.createTextNode(` ${tilt === 0 ? ctx.t.balance_even : tilt > 0 ? ctx.t.balance_left : ctx.t.balance_right}`))
    }
    if (type === "balance" && state.tryValue !== undefined) {
      const v = tryValues(data, state.tryValue, state.i)
      readout.replaceChildren(
        el("span", { class: "dg-rd dg-rd-left" }, el("small", { text: ctx.t.first_member }), el("strong", { text: v.left })),
        el("span", { class: "dg-rd dg-rd-right" }, el("small", { text: ctx.t.second_member }), el("strong", { text: v.right })),
        el("span", { class: `dg-verdict${v.tilt === 0 ? " is-level" : ""}`, text: v.tilt === 0 ? ctx.t.try_level : v.tilt > 0 ? ctx.t.try_left : ctx.t.try_right }))
    }
    animate(old, figure, ctx.reduced())
    if (old.size && !ctx.reduced()) for (const node of figure.querySelectorAll("[data-key]")) if (!old.has(node.dataset.key)) node.classList.add("dg-enter")
    stepper()
  }

  // The tap targets of a select check (WAVE2 2.11): one HTML button over each shape the layout marked with a target id (tN), in reading order.
  // One tab stop (roving): the arrows go to the nearest target in that direction, Space or Enter toggles. Every target is the same neutral
  // outline (L3); a chosen one is a solid outline with a check mark, never a colour alone. The name read is "zona n di N" plus the type's
  // neutral description, never a label.
  const selectTargets = () => {
    const sel = options.select
    const texts = ctx.t.checks
    // the box of each target in the stage's own pixels: getBoundingClientRect follows the transforms of a group (a map's zones sit in a
    // scaled one), getBBox would give the shape's local units (D-319)
    const origin = stage.getBoundingClientRect()
    const found = [...stageSvg.querySelectorAll("[data-target]")].map((node) => {
      const r = node.getBoundingClientRect()
      return { id: node.dataset.target, node, box: { x: r.left - origin.left, y: r.top - origin.top, width: r.width, height: r.height } }
    })
    found.sort((a, b) => Number(a.id.slice(1)) - Number(b.id.slice(1)))
    if (found.length === 0) {
      sel.onNoTargets?.()
      return
    }
    const layer = el("div", { class: "dg-targets", role: "group", "aria-label": texts.select_group })
    const buttons = found.map(({ id: tid, node, box }) => {
      const w = Math.max(box.width, 28)
      const h = Math.max(box.height, 28)
      const b = el("button", {
        type: "button", class: "dg-target", "data-target": tid, "data-n": tid.slice(1), "aria-pressed": "false", tabindex: "-1",
        "aria-label": targetLabel(texts.select_zone, tid.slice(1), sel.total ?? found.length, sel.info?.get(tid)?.neutral_it)
      }, icon("check", "dg-target-ic"))
      // an irregular shape (a zone of a map) is tapped on the shape itself: its box would cover its neighbours, so the button is only the
      // keyboard's and the screen reader's way in and lets the finger through (the shape's own click toggles, below)
      if (node.parentNode !== stageSvg) b.classList.add("dg-target-shape")
      b.style.left = `${box.x + box.width / 2 - w / 2}px`
      b.style.top = `${box.y + box.height / 2 - h / 2}px`
      b.style.width = `${w}px`
      b.style.height = `${h}px`
      return b
    })
    const sync = () => {
      for (const b of buttons) {
        const on = sel.isOn(b.dataset.target)
        b.setAttribute("aria-pressed", String(on))
        b.classList.toggle("is-on", on)
      }
      for (const { id: tid, node } of found) node.classList.toggle("is-selected", sel.isOn(tid))
    }
    const boxes = found.map(({ box }) => ({ x: box.x, y: box.y, w: box.width, h: box.height }))
    let current = Math.max(0, buttons.findIndex((b) => sel.isOn(b.dataset.target)))
    const focusAt = (i) => {
      buttons[current].tabIndex = -1
      current = i
      buttons[current].tabIndex = 0
      buttons[current].focus()
    }
    buttons[current].tabIndex = 0
    buttons.forEach((b, i) => {
      b.addEventListener("click", () => {
        current = i
        sel.toggle(b.dataset.target)
        sync()
      })
      b.addEventListener("keydown", (event) => {
        if (event.altKey || event.ctrlKey || event.metaKey) return
        const dir = { ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down" }[event.key]
        if (dir) {
          event.preventDefault()
          focusAt(nearest(boxes, i, dir))
        } else if (event.key === "Home" || event.key === "End") {
          event.preventDefault()
          focusAt(event.key === "Home" ? 0 : buttons.length - 1)
        }
      })
      layer.appendChild(b)
    })
    // the finger or the mouse on the shape (or on its invisible pad) is a click on its button
    const buttonOf = new Map(buttons.map((b) => [b.dataset.target, b]))
    for (const { id: tid, node } of found) if (node.parentNode !== stageSvg) node.addEventListener("click", () => buttonOf.get(tid).click())
    for (const pad of stageSvg.querySelectorAll("[data-hit-for]")) pad.addEventListener("click", () => buttonOf.get(pad.dataset.hitFor)?.click())
    sync()
    labelsLayer.appendChild(layer)
  }

  // controls: states ("Avanti") and the balance's try stepper
  const readout = el("div", { class: "dg-readout", role: "status" })
  let prev
  let next
  let counter
  const stepper = () => {
    if (total <= 1 || !counter) return // a linked figure that got its states after the mount has no stepper (the example's steps drive it)
    counter.textContent = ctx.t.step_of.replace("%{n}", state.i + 1).replace("%{total}", total)
    prev.disabled = state.i === 0
    const nextLabel = data.states[state.i]?.next_label_it
    next.firstChild.textContent = state.i === total - 1 ? ctx.t.restart_steps : nextLabel ?? ctx.t.next_step
    next.dataset.last = String(state.i === total - 1)
  }
  if (total > 1) {
    prev = button(ctx.t.prev_step, { class: "button secondary small dg-prev" }, () => {
      state.i = Math.max(0, state.i - 1)
      resetControls()
      draw()
    })
    next = button("", { class: "button secondary small dg-next" }, () => {
      state.i = state.i === total - 1 ? 0 : state.i + 1
      resetControls()
      draw()
    })
    next.textContent = ctx.t.next_step
    counter = el("span", { class: "dg-counter", "aria-live": "polite" })
    if (!options.linked) controls.append(prev, next, counter)
  }
  // a compact balance (a row of the cases) is driven by the shared stepper through setTry: no stepper, no readout of its own
  if (type === "balance" && data.try && !options.compact) {
    const from = Number(data.try.from)
    const to = Number(data.try.to)
    const value = el("output", { class: "dg-tryvalue", "aria-live": "polite" })
    const set = (v) => {
      state.tryValue = Math.max(from, Math.min(to, v))
      value.textContent = `x = ${state.tryValue}`
      minus.disabled = state.tryValue <= from
      plus.disabled = state.tryValue >= to
      draw()
    }
    const minus = button("−", { class: "button secondary dg-step dg-round", "aria-label": ctx.t.try_less }, () => set(state.tryValue - 1))
    const plus = button("+", { class: "button secondary dg-step dg-round", "aria-label": ctx.t.try_more }, () => set(state.tryValue + 1))
    const group = el("div", { class: "dg-try", role: "group", "aria-label": ctx.t.try_label }, el("span", { class: "dg-trylabel", text: ctx.t.try_label }), minus, value, plus)
    controls.appendChild(group)
    controls.appendChild(readout)
    value.textContent = `x = ${state.tryValue}`
    minus.disabled = true
  }

  // controls() of a wave 2 type (a stepper, a slider with its - and + buttons): rebuilt when the state brings other ones
  const ctrlHost = el("div", { class: "dg-ctrls" })
  let ctrlKey = null
  let ctrlIds = []
  const syncControls = () => {
    const list = mode === "select" || own ? [] : (mod?.controls?.(data, { state: state.i, mode }) ?? []).filter((c) => !isStrip(c) && c.kind !== "chips")
    const key = JSON.stringify(list.map((c) => [c.id, c.range, c.values, c.stops]))
    if (key === ctrlKey) return
    ctrlKey = key
    clear(ctrlHost)
    for (const id of ctrlIds) if (!list.some((c) => c.id === id)) delete state.controls[id]
    ctrlIds = list.map((c) => c.id)
    const next = state.controls
    for (const c of list) {
      const options = c.values ?? []
      let v = state.controls[c.id] ?? c.initial ?? (options.length ? options[0] : c.range[0])
      v = options.length ? options.reduce((best, x) => (Math.abs(x - v) < Math.abs(best - v) ? x : best), options[0]) : Math.max(c.range[0], Math.min(c.range[1], v))
      next[c.id] = v
      ctrlHost.appendChild(controlNode(c, v, (nv) => {
        state.controls[c.id] = nv
        state.announce = true
        draw()
      }))
    }
    if (list.length && !ctrlHost.parentNode) controls.appendChild(ctrlHost)
    if (!list.length) ctrlHost.remove()
  }

  // the print views (P1): all the states of a figure that prints them, a slider's first, middle and last year
  const paintPrint = (width, fontPx) => {
    state.printWidth = width
    clear(printHost)
    for (const view of mod.printViews(data) ?? []) {
      const scene = layout(data, { width, fontPx, measure: measurer.current.measure, subject: ctx.subject, state: view.state, mode: "print", controls: view.controls })
      if (scene.error) continue
      const env = { defs: new Map(), scale: 1, id: `${id}-print${printHost.children.length}` }
      const pane = svg("svg", { class: "dg-svg", viewBox: `0 0 ${scene.width} ${scene.height}`, width: scene.width, height: scene.height, role: "img", "aria-label": data.alt_it })
      for (const s of scene.shapes) for (const node of shapeNode(s, env)) pane.appendChild(node)
      if (env.defs.size) pane.insertBefore(defsNode(env), pane.firstChild)
      const texts = el("div", { class: "dg-labels" })
      for (const l of scene.labels) {
        const node = el("div", { class: `dg-label ${l.cls} dg-a-${l.anchor}${l.wrap ? " dg-wrap" : ""}` })
        node.style.left = `${l.x}px`
        node.style.top = `${l.y}px`
        node.style.width = `${l.w + (l.wrap ? 0 : 2)}px`
        node.style.fontSize = `${l.px}px`
        renderInlineRich(l.text_it, node, ctx)
        texts.appendChild(node)
      }
      const cap = view.caption_it ?? data.states?.[view.state]?.op_it
      const cell = el("figure", { class: "dg-printview" }, el("div", { class: "dg-stage", style: `height:${scene.height}px` }, pane, texts))
      if (cap) cell.appendChild(el("figcaption", { class: "dg-caption", text: cap }))
      if (scene.legend?.length) cell.appendChild(legendNode(scene.legend))
      printHost.appendChild(cell)
    }
    if (printHost.children.length > 0) figure.dataset.printviews = String(printHost.children.length)
    else delete figure.dataset.printviews
  }
  // print shows the numbers (P2): a closed <details> hides its content from the printer
  const beforePrint = () => { if (!valuesBox.hidden) valuesBox.dataset.wasOpen = String(valuesBox.open), valuesBox.open = true }
  const afterPrint = () => { if (valuesBox.dataset.wasOpen !== undefined) { valuesBox.open = valuesBox.dataset.wasOpen === "true"; delete valuesBox.dataset.wasOpen } }
  window.addEventListener("beforeprint", beforePrint)
  window.addEventListener("afterprint", afterPrint)

  let timer = null
  let observer = null
  const schedule = () => {
    clearTimeout(timer)
    figure.dataset.settling = "1"
    timer = setTimeout(() => {
      const width = Math.floor(stage.clientWidth)
      if (width && (Math.abs(width - state.width) > 1 || measurer.current?.degenerate)) draw()
      delete figure.dataset.settling
    }, 60)
  }
  const mounted = () => {
    const start = () => {
      draw()
      if (typeof ResizeObserver !== "undefined") {
        observer = new ResizeObserver(schedule)
        observer.observe(stage)
      }
    }
    if (mod && !mod.prepare) return start() // the core types: drawn at once, as before
    // a wave 2 type loads its module on demand and, if it says so, its assets (a map's base) before the first layout
    const ready = Promise.resolve(mod ?? load(type)).then((m) => {
      mod = m
      setupStrip()
      return m?.prepare?.(data, { mode })
    })
    ready.then(start, (error) => showError({ code: "E-DIAGRAM-LAYOUT", path: "", message: `could not load the ${type} figure: ${error?.message ?? error}` }))
  }
  return {
    element: figure,
    get total() { return total },
    mounted,
    relayout: draw,
    setState: (i) => {
      state.i = Math.max(0, Math.min(total - 1, i))
      resetControls()
      draw()
    },
    // an example's linked figure after a blank: the server sends the figure again with the states of the steps now open (cut at the next
    // blank as the page's first one was), and the example moves to them with setState
    replaceData: (next) => {
      if (!next || next.type !== type) return
      data = next
      total = mod || STATUS[type] ? stateCount(data) : 1
      figure.dataset.states = String(total)
      state.i = Math.min(state.i, total - 1)
      state.printWidth = 0 // the print views follow the completed states
      draw()
    },
    // the number in the boxes of a balance, set from outside (the shared stepper of the cases)
    setTry: (v) => {
      if (type !== "balance") return
      state.tryValue = v
      draw()
    },
    destroy: () => {
      window.removeEventListener("beforeprint", beforePrint)
      window.removeEventListener("afterprint", afterPrint)
      observer?.disconnect()
      clearTimeout(timer)
    }
  }
}

export { renderRich, N }
