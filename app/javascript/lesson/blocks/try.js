// try: the exercises of the lesson, one at a time with one compact pager (arrows and number chips) or all in a list (scroll
// view, print). Each is done "sul quaderno"; when it has a check (or up to three, parts a, b, c) it is answered
// in the page with feedback from its errors; "Mostra la soluzione" fetches the solution (tagged steps or text)
// and the final from the server, never in the page.
import { button, el, icon } from "lesson/dom"
import { renderCheck } from "lesson/blocks/check"
import { figureFor } from "lesson/blocks/diagram"
import { tagInfo } from "lesson/blocks/procedure"
import { questionControl } from "lesson/question"
import { renderInlineRich, renderRich } from "lesson/text"
import { exerciseNotes } from "lesson/teacher_notes"

function solutionNode(reply, ctx) {
  const box = el("div", { class: "solution" })
  box.appendChild(el("h4", { class: "solution-title", text: ctx.t.solution_title }))
  if (Array.isArray(reply.solution_steps)) {
    const list = el("ol", { class: "example-steps solution-steps" })
    reply.solution_steps.forEach((step, i) => {
      const info = step.tag ? tagInfo(ctx.subject, step.tag) : null
      list.appendChild(el("li", { class: "example-step" },
        el("p", { class: "step-tag" }, info ? icon(info.icon, "step-ic") : null, el("strong", { text: info ? info.label_it : `${ctx.t.step} ${i + 1}` })),
        el("div", { class: "step-do" }, renderRich(step.do_it, ctx, { tiles: true })),
        step.why_it ? el("div", { class: "step-why" }, el("span", { class: "why-label", text: `${ctx.t.why}: ` }), renderInlineRich(step.why_it, el("span"), ctx)) : null))
    })
    box.appendChild(list)
  } else if (reply.solution_it) box.appendChild(el("div", { class: "solution-text" }, renderRich(reply.solution_it, ctx)))
  if (reply.final_it) box.appendChild(el("p", { class: "solution-final" }, el("strong", { text: `${ctx.t.final}: ` }), renderInlineRich(reply.final_it, el("span"), ctx)))
  return box
}

export function render(block, ctx, loc) {
  const root = el("section", { class: "block try", "data-pager": ctx.pager ? "" : null })
  const total = block.exercises.length
  if (block.intro_it) root.appendChild(el("div", { class: "try-intro" }, renderRich(block.intro_it, ctx)))
  const counter = el("p", { class: "try-counter sr-only", "aria-live": "polite" })
  let current = 0
  const items = []
  const list = el("ol", { class: "exercises" })
  block.exercises.forEach((ex, index) => {
    const li = el("li", { class: "exercise", id: `exercise-${loc.card}-${ex.n}`, "data-n": ex.n })
    // the chips already say which exercise this is: the heading stays for the screen reader and the focus
    li.appendChild(el("h3", { class: "exercise-head sr-only" }, el("span", { text: `${ctx.t.exercise} ${ex.n}` }), el("span", { class: "exercise-sub", text: ` · ${ctx.t.on_notebook}` })))
    li.appendChild(el("div", { class: "exercise-text" }, renderRich(ex.text_it, ctx, { tiles: true })))
    if (ex.diagram) li.appendChild(el("div", { class: "block-diagram" }, figureFor(ex.diagram, ctx).node))
    const checks = ctx.safe ? [] : ex.checks ?? (ex.check ? [ex.check] : [])
    checks.forEach((spec, k) => {
      const part = checks.length > 1 ? k + 1 : undefined
      const wrap = el("div", { class: "exercise-check" })
      if (checks.length > 1) wrap.appendChild(el("p", { class: "part-label", text: `${String.fromCharCode(97 + k)})` }))
      wrap.appendChild(renderCheck(spec, ctx, { ...loc, ex: ex.n, part }, { inline: true, quietPrompt: checks.length === 1 }).element)
      li.appendChild(wrap)
    })
    const out = el("div", { class: "exercise-solution", "aria-live": "polite" })
    const show = button(ctx.t.show_solution, { class: "button secondary small", "aria-expanded": "false" }, async () => {
      if (out.dataset.loaded) {
        const hide = !out.hidden
        out.hidden = hide
        show.setAttribute("aria-expanded", String(!hide))
        return
      }
      out.textContent = ctx.t.loading_solution
      const reply = await ctx.fetchSolution(ex.n)
      if (!reply) {
        out.textContent = ctx.t.solution_error
        return
      }
      out.replaceChildren(solutionNode(reply, ctx))
      out.dataset.loaded = "1"
      show.setAttribute("aria-expanded", "true")
    })
    li.append(el("p", { class: "exercise-actions" }, show), out)
    if (ctx.teacher) {
      const notes = exerciseNotes(ctx.full?.exercise(loc.card, loc.block, ex.n), ctx)
      if (notes) li.appendChild(notes)
    }
    const q = questionControl(ctx, { section: "try", exercise: ex.n, card: loc.card })
    if (q) li.appendChild(q)
    items.push(li)
    list.appendChild(li)
  })
  const dots = el("div", { class: "try-dots", role: "group", "aria-label": ctx.t.exercises })
  const arrow = (name, label, cls, handler) => button(el("span", { class: "try-arrow-in" }, icon(name), el("span", { class: "sr-only", text: label })), { class: `try-arrow ${cls}` }, handler)
  const dotButtons = block.exercises.map((ex, i) => {
    const b = button(String(ex.n), { class: "try-dot", "aria-label": `${ctx.t.exercise} ${ex.n}` }, () => go(i))
    dots.appendChild(b)
    return b
  })
  const prev = arrow("prev", ctx.t.prev_exercise, "try-prev", () => go(current - 1))
  const next = arrow("next", ctx.t.next_exercise, "try-next", () => go(current + 1))
  // one compact pager: previous, the numbers, next, all on one row
  const pager = el("nav", { class: "try-nav", "aria-label": ctx.t.exercises }, prev, dots, next, counter)
  function go(i, focus = true) {
    current = Math.max(0, Math.min(total - 1, i))
    items.forEach((li, k) => li.classList.toggle("is-current", k === current))
    dotButtons.forEach((b, k) => b.setAttribute("aria-current", k === current ? "true" : "false"))
    counter.textContent = ctx.t.exercise_of.replace("%{n}", current + 1).replace("%{total}", total)
    prev.disabled = current === 0
    next.disabled = current === total - 1
    if (focus) items[current].querySelector("h3")?.focus?.()
  }
  items.forEach((li) => li.querySelector("h3").setAttribute("tabindex", "-1"))
  root.append(pager, list)
  go(0, false)
  return root
}
