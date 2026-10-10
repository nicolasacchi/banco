// Turns a Scene (A7 renderer contract) into a figure: SVG for shapes (createElementNS, classes only), an
// HTML layer for labels (real text, KaTeX, selectable, read by screen readers), the controls of the type
// (Avanti through states, the balance's number stepper, tapping a part of a sentence), the text
// alternative and a "Descrizione". The layout is computed at the container's width with the body font
// size and again on resize. If layout() answers { error } the figure shows alt_it and the description.
import * as N from "lesson/num"
import { button, clear, el, icon, svg, uid } from "lesson/dom"
import { describe, layout, moduleFor, stateCount } from "lesson/diagrams/registry"
import { tryValues, equationTex } from "lesson/diagrams/balance"
import { renderInlineRich, renderMath, renderRich } from "lesson/text"

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
  diamond: (m) => [svg("polygon", { points: `${m.x + m.w / 2},${m.y + 1} ${m.x + m.w - 1},${m.y + m.h / 2} ${m.x + m.w / 2},${m.y + m.h - 1} ${m.x + 1},${m.y + m.h / 2}`, class: m.cls })]
}

function shapeNode(s) {
  switch (s.kind) {
    case "line": return [svg("line", { x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2, class: s.cls })]
    case "rect": return [svg("rect", { x: s.x, y: s.y, width: s.w, height: s.h, rx: s.r ?? 0, class: s.cls })]
    case "circle": return [svg("circle", { cx: s.cx, cy: s.cy, r: s.r, class: s.cls })]
    case "path": return [svg("path", { d: s.d, class: s.cls })]
    case "ellipse": return [svg("ellipse", { cx: s.cx, cy: s.cy, rx: s.rx, ry: s.ry, class: s.cls })]
    case "text": {
      const t = svg("text", { x: s.x, y: s.y, "text-anchor": "middle", class: s.cls, style: `font-size:${s.px}px` })
      t.textContent = s.text
      return [t]
    }
    case "group": {
      // a group that can move: `at` places it, `move` { tx, ty, rot, ox, oy } is what draw() animates from the last state
      const outer = svg("g", { class: s.cls ?? "", transform: s.at ? `translate(${s.at[0]},${s.at[1]})` : undefined })
      const inner = svg("g", { class: "dg-move" })
      for (const child of s.children ?? []) for (const node of shapeNode(child)) inner.appendChild(node)
      outer.appendChild(inner)
      outer.__inner = inner
      return [outer]
    }
    case "polygon": return [svg("polygon", { points: s.points.map((p) => p.join(",")).join(" "), class: s.cls })]
    case "marker": return (MARKERS[s.shape] ?? MARKERS.circle)(s)
    case "icon": {
      const g = svg("svg", { x: s.x, y: s.y, width: s.size, height: s.size, viewBox: "0 0 24 24", class: `dg-icon ${s.cls ?? ""}`, "aria-hidden": "true" })
      g.appendChild(svg("use", { href: `/vendor/lucide@1.54.0/banco-sprite.svg#${s.name}` }))
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
  const measure = (text, px, maxW) => {
    const key = `${px}|${maxW ?? ""}|${text}`
    if (cache.has(key)) return cache.get(key)
    clear(probe)
    probe.style.fontSize = `${px}px`
    probe.style.maxWidth = maxW ? `${maxW}px` : "none"
    probe.style.whiteSpace = maxW ? "normal" : "nowrap"
    probe.style.width = maxW ? `${maxW}px` : "auto"
    renderInlineRich(text, probe, ctx)
    const rect = probe.getBoundingClientRect()
    const result = { w: Math.ceil(rect.width), h: Math.ceil(rect.height) }
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
  return { measure, probe, drop: () => probe.remove() }
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
  const id = uid("dg")
  const figure = el("figure", { class: `dg dg-${type} dg-size-${data?.size ?? "m"}${options.hero ? " dg-hero" : ""}`, "data-type": type })
  const stage = el("div", { class: "dg-stage" })
  const labelsLayer = el("div", { class: "dg-labels" })
  const stageSvg = svg("svg", { class: "dg-svg", role: "img", "aria-labelledby": `${id}-alt`, focusable: "false" })
  const alt = el("span", { id: `${id}-alt`, class: "sr-only", text: data?.alt_it ?? "" })
  stage.append(stageSvg, labelsLayer)
  const controls = el("div", { class: "dg-controls" })
  const op = el("p", { class: "dg-op", "aria-live": "polite" })
  const question = el("p", { class: "dg-question", "aria-live": "polite" })
  const caption = data?.caption_it ? el("figcaption", { class: "dg-caption" }) : null
  if (caption) renderInlineRich(data.caption_it, caption, ctx)
  const desc = el("details", { class: "dg-desc" }, el("summary", {}, icon("description"), document.createTextNode(` ${ctx.t.description}`)), el("p", { text: describe(data) }))
  // a balance has its equation, the state's name and a status chip above the drawing
  const top = type === "balance" ? el("div", { class: "dg-top" }) : null
  const pill = el("span", { class: "dg-pill" })
  const eqLine = el("div", { class: "dg-eq", "aria-hidden": "true" })
  const chip = el("span", { class: "dg-status", role: "status" })
  if (top) top.append(pill, eqLine, chip)
  figure.append(alt, ...(top ? [top] : []), stage, op, question, controls, ...(caption ? [caption] : []), desc)

  const mod = moduleFor(type)
  const total = mod ? stateCount(data) : 1
  const state = { moves: new Map(), lastWidth: 0, i: 0, tryValue: data?.try && data?.type === "balance" ? Number(data.try.from) : undefined, width: 0, selected: null }
  figure.dataset.states = String(total)
  if (total > 1 || (type === "sentence" && data.parts)) figure.dataset.nokeys = ""
  const measurer = { current: null }

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
    if (!measurer.current) measurer.current = makeMeasure(stage, ctx)
    const fontPx = ctx.fontPx()
    const scene = layout(data, { width, fontPx, measure: measurer.current.measure, subject: ctx.subject, state: state.i, tryValue: state.tryValue })
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
    stageSvg.setAttribute("viewBox", `0 0 ${scene.width} ${scene.height}`)
    stageSvg.setAttribute("width", String(scene.width))
    stageSvg.setAttribute("height", String(scene.height))
    stage.style.height = `${scene.height}px`
    const moves = new Map()
    const animated = []
    const sameWidth = state.lastWidth === scene.width
    scene.shapes.forEach((s) => {
      for (const node of shapeNode(s)) {
        if (s.key && s.kind !== "group") node.dataset.key = s.key
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
      labelsLayer.appendChild(node)
    }
    for (const h of scene.hits ?? []) {
      const b = el("button", { type: "button", class: "dg-hit", "aria-pressed": state.selected === h.id ? "true" : "false", "aria-label": `${h.name}: ${h.text}${h.question_it ? `. ${ctx.t.tap_for_question}` : ""}` })
      b.style.left = `${h.x}px`
      b.style.top = `${h.y}px`
      b.style.width = `${h.w}px`
      b.style.height = `${h.h}px`
      b.dataset.key = `${h.key}:hit`
      b.addEventListener("click", () => {
        state.selected = h.id
        question.textContent = h.question_it ? `${h.name}: ${h.question_it}` : `${h.name}.`
        for (const other of labelsLayer.querySelectorAll(".dg-hit")) other.setAttribute("aria-pressed", String(other === b))
      })
      labelsLayer.appendChild(b)
    }
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
    stepper()
  }

  // controls: states ("Avanti") and the balance's try stepper
  const readout = el("div", { class: "dg-readout", role: "status" })
  let prev
  let next
  let counter
  const stepper = () => {
    if (total <= 1) return
    counter.textContent = ctx.t.step_of.replace("%{n}", state.i + 1).replace("%{total}", total)
    prev.disabled = state.i === 0
    const nextLabel = data.states[state.i]?.next_label_it
    next.firstChild.textContent = state.i === total - 1 ? ctx.t.restart_steps : nextLabel ?? ctx.t.next_step
    next.dataset.last = String(state.i === total - 1)
  }
  if (total > 1) {
    prev = button(ctx.t.prev_step, { class: "button secondary small dg-prev" }, () => {
      state.i = Math.max(0, state.i - 1)
      draw()
    })
    next = button("", { class: "button small dg-next" }, () => {
      state.i = state.i === total - 1 ? 0 : state.i + 1
      draw()
    })
    next.textContent = ctx.t.next_step
    counter = el("span", { class: "dg-counter", "aria-live": "polite" })
    if (!options.linked) controls.append(prev, next, counter)
  }
  if (type === "balance" && data.try) {
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

  let timer = null
  let observer = null
  const schedule = () => {
    clearTimeout(timer)
    timer = setTimeout(() => {
      const width = Math.floor(stage.clientWidth)
      if (width && Math.abs(width - state.width) > 1) draw()
    }, 60)
  }
  const mounted = () => {
    draw()
    if (typeof ResizeObserver !== "undefined") {
      observer = new ResizeObserver(schedule)
      observer.observe(stage)
    }
  }
  return {
    element: figure,
    total,
    mounted,
    relayout: draw,
    setState: (i) => {
      state.i = Math.max(0, Math.min(total - 1, i))
      draw()
    },
    destroy: () => {
      observer?.disconnect()
      clearTimeout(timer)
    }
  }
}

function tableNode(table, ctx) {
  const t = el("table", { class: "dg-table" })
  const head = el("tr")
  table.header.forEach((h) => head.appendChild(renderInlineRich(h, el("th", { scope: "col" }), ctx)))
  t.appendChild(el("thead", {}, head))
  const body = el("tbody")
  table.rows.forEach((row) => {
    const tr = el("tr")
    row.forEach((cell, i) => {
      const td = renderInlineRich(cell, el(i === 0 ? "th" : "td", i === 0 ? { scope: "row" } : {}), ctx)
      td.setAttribute("data-label", table.header[i].replace(/\$/g, ""))
      tr.appendChild(td)
    })
    body.appendChild(tr)
  })
  t.appendChild(body)
  return t
}

export { renderRich, N }
