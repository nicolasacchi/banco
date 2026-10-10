// example: a worked example with step reveal ("Mostra il passo successivo", "Mostra tutti i passi"). Each step
// has its tag's verb and icon, what to do, and why. A step with a blank is a check (a faded example): the
// page has the step's reason and the question, not its result nor the steps after it; the server sends them
// after a right answer or the second try (A2, A9). With a `diagram` whose states match the steps one to one,
// revealing step i shows state i.
import { button, el, icon } from "lesson/dom"
import { renderCheck } from "lesson/blocks/check"
import { figureFor } from "lesson/blocks/diagram"
import { tagInfo } from "lesson/blocks/procedure"
import { renderInlineRich, renderRich } from "lesson/text"

export function render(block, ctx, loc) {
  const root = el("section", { class: "block example" })
  root.appendChild(el("div", { class: "example-problem" }, el("p", { class: "example-label" }, icon("pencil-ruler", "ex-ic"), el("strong", { text: ctx.t.problem })), renderRich(block.problem_it, ctx)))
  const list = el("ol", { class: "example-steps", "aria-live": "polite" })
  const steps = block.steps.map((s) => ({ ...s }))
  let figure = null
  if (block.diagram) {
    const made = figureFor(block.diagram, ctx, { linked: true })
    figure = made.api
    root.appendChild(el("div", { class: "block-diagram" }, made.node))
  }
  const result = el("div", { class: "example-result", hidden: "" })
  let shown = ctx.showAll ? steps.length : 0
  let resultText = block.result_it ?? null
  const rows = []
  const next = button(ctx.t.next_step_example, { class: "button small" }, () => reveal(shown + 1))
  const all = button(ctx.t.all_steps, { class: "button secondary small" }, () => reveal(steps.length))
  const note = el("p", { class: "hint example-note", role: "status" })
  const controls = el("p", { class: "example-controls" }, next, all)

  const stepNode = (step, i) => {
    const info = step.tag ? tagInfo(ctx.subject, step.tag) : null
    const li = el("li", { class: "example-step", hidden: "" })
    li.appendChild(el("p", { class: "step-tag" }, info ? icon(info.icon, "step-ic") : null, el("strong", { text: info ? info.label_it : `${ctx.t.step} ${i + 1}` })))
    const body = el("div", { class: "step-body" })
    if (step.do_it) body.appendChild(el("div", { class: "step-do" }, renderRich(step.do_it, ctx)))
    li.appendChild(body)
    if (step.why_it) li.appendChild(el("div", { class: "step-why" }, el("span", { class: "why-label", text: `${ctx.t.why}: ` }), renderInlineRich(step.why_it, el("span"), ctx)))
    if (step.blank) {
      const gate = renderCheck(step.blank, ctx, { ...loc, step: i + 1 }, {
        onDone: (reply) => resolve(i, reply)
      })
      body.appendChild(el("div", { class: "step-blank" }, el("p", { class: "blank-label" }, icon("circle-help", "blank-ic"), el("strong", { text: ctx.t.your_turn })), gate.element))
    }
    return li
  }
  steps.forEach((s, i) => {
    const li = stepNode(s, i)
    rows.push(li)
    list.appendChild(li)
  })

  // the server's answer to a blank: the blank step's do_it and the steps after it
  const resolve = (index, reply) => {
    if (!Array.isArray(reply.steps)) return
    const tail = reply.steps
    steps.splice(index, steps.length - index, ...tail.map((s) => ({ ...s })))
    for (const row of rows.splice(index)) row.remove()
    steps.slice(index).forEach((s, k) => {
      const li = stepNode(s, index + k)
      li.hidden = false
      if (k === 0) li.appendChild(el("p", { class: "verdict verdict-right" }, icon("circle-check", "verdict-ic"), el("strong", { text: ctx.t.right })))
      rows.push(li)
      list.appendChild(li)
    })
    if (reply.result_it) resultText = reply.result_it
    // the revealed steps after the blank stay hidden until asked, except the blank step itself
    for (let k = index + 1; k < rows.length; k++) rows[k].hidden = true
    shown = index + 1
    update()
  }

  function reveal(upTo) {
    const gate = steps.findIndex((s) => s.blank && !s.do_it)
    shown = gate >= 0 ? Math.min(upTo, gate + 1) : Math.min(upTo, steps.length)
    update()
  }
  function update() {
    rows.forEach((row, i) => {
      row.hidden = i >= shown
      row.classList.toggle("is-current", i === shown - 1)
    })
    const gate = steps.findIndex((s) => s.blank && !s.do_it)
    const waiting = gate >= 0 && shown > gate
    const complete = shown >= steps.length && gate < 0
    next.disabled = waiting || complete
    all.disabled = waiting || complete
    note.textContent = waiting ? ctx.t.answer_first : ""
    if (resultText && complete) {
      result.hidden = false
      result.replaceChildren(el("p", { class: "example-label" }, icon("circle-check", "ex-ic"), el("strong", { text: ctx.t.result })), renderRich(resultText, ctx))
    } else result.hidden = true
    if (figure?.setState && shown > 0) figure.setState(Math.min(shown, figure.total ?? shown) - 1)
  }
  root.append(list, controls, note, result)
  update()
  return root
}
