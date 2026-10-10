// cases: compact rows, one per case (icon and name, the condition as a big tile, one line of result, a small balance beside it).
// When the cases draw balances, one stepper on top ("Prova un numero al posto di x") sets the number in the boxes of all of them
// at once, so the student sees the three behaviours with the same x. The rows stack on a narrow container (CSS container query).
import { button, el, icon } from "lesson/dom"
import { renderInlineRich, renderRich, roleOf } from "lesson/text"
import { figureFor } from "lesson/blocks/diagram"

export function render(block, ctx) {
  const box = el("section", { class: `block cases cases-${block.cases.length}` })
  if (block.title_it) box.appendChild(el("h3", { class: "block-title", text: block.title_it }))
  const apis = []
  const grid = el("div", { class: "cases-grid" })
  for (const c of block.cases) {
    const tone = c.tone ? `case-tone card-tone-${c.tone}` : ""
    const head = el("h4", { class: "case-head" })
    const info = c.tone ? roleOf(ctx.subject, c.tone) : null
    const iconName = c.icon ?? (info?.carrier === "icon" ? info.icon : null)
    if (iconName) head.appendChild(icon(iconName, "case-ic"))
    head.appendChild(document.createTextNode(c.title_it))
    const section = el("section", { class: `case ${tone}` })
    const text = el("div", { class: "case-info" }, head)
    if (c.condition_it) text.appendChild(renderInlineRich(c.condition_it, el("p", { class: "case-condition" }), ctx, { tiles: true }))
    text.appendChild(el("div", { class: "case-text" }, renderRich(c.text_it, ctx)))
    if (c.example_it) text.appendChild(el("div", { class: "case-example" }, renderRich(c.example_it, ctx, { tiles: true })))
    section.appendChild(text)
    if (c.diagram) {
      const shared = c.diagram.type === "balance" && !ctx.safe
      const made = figureFor(c.diagram, ctx, { compact: shared })
      if (shared && made.api) apis.push(made.api)
      section.appendChild(el("div", { class: "case-fig block-diagram" }, made.node))
    }
    grid.appendChild(section)
  }
  const tries = block.cases.map((c) => c.diagram?.try).filter(Boolean)
  if (apis.length > 1 && tries.length) box.appendChild(sharedStepper(tries[0], apis, ctx))
  box.appendChild(grid)
  return box
}

function sharedStepper(range, apis, ctx) {
  const from = Number(range.from)
  const to = Number(range.to)
  let v = from
  const value = el("output", { class: "dg-tryvalue", "aria-live": "polite" })
  const minus = button("−", { class: "button secondary dg-step dg-round", "aria-label": ctx.t.try_less }, () => set(v - 1))
  const plus = button("+", { class: "button secondary dg-step dg-round", "aria-label": ctx.t.try_more }, () => set(v + 1))
  const set = (n) => {
    v = Math.max(from, Math.min(to, n))
    value.textContent = `x = ${v}`
    minus.disabled = v <= from
    plus.disabled = v >= to
    apis.forEach((api) => api.setTry(v))
  }
  value.textContent = `x = ${v}`
  minus.disabled = true
  ctx.mount(() => apis.forEach((api) => api.setTry(v)))
  return el("div", { class: "cases-try", role: "group", "aria-label": ctx.t.cases_try },
    el("span", { class: "dg-trylabel", text: ctx.t.cases_try }), minus, value, plus)
}
