// reveal (WAVE2 2.10): think first, then turn. Ungraded: nothing is stored, nothing is checked.
//   prompt_it + answer_it   a flip card ("Pensaci, poi gira"): the question on the front, the answer behind it.
//   situation_it + options  the crossroads: S picks a road, sees what comes of it, then turns to what really happened and the real road is
//                           marked (with a word and an icon, not by colour alone). Our line says the other roads are guesses.
// The back is not in the way until it is asked for, so a screen reader and "Ascolta" meet it only once shown (L10). Open in print, in
// the teacher's view and in safe mode. The turning is lesson/blocks/flip, the same as a mistake's.
import { el, icon, uid } from "lesson/dom"
import { flip } from "lesson/blocks/flip"
import { renderInlineRich, renderRich } from "lesson/text"

// "-27" is "27 a.C.", "14" is "14 d.C."
export function yearLabel(year) {
  const n = Number(year)
  if (!Number.isFinite(n)) return String(year)
  return n < 0 ? `${-n} a.C.` : `${n} d.C.`
}

function plain(block, ctx) {
  const front = el("div", { class: "reveal-front" },
    el("p", { class: "reveal-tag" }, icon("circle-help", "reveal-ic"), el("strong", { text: ctx.t.docs.reveal_think })),
    renderInlineRich(block.prompt_it, el("p", { class: "reveal-text" }), ctx))
  const back = [
    el("p", { class: "reveal-tag reveal-tag-answer" }, icon("check", "reveal-ic"), el("strong", { text: ctx.t.docs.reveal_answer })),
    el("div", { class: "reveal-text" }, renderRich(block.answer_it, ctx))
  ]
  return flip({ prefix: "reveal", front, back, ctx, hint: { text: ctx.t.docs.flip_hint, label: ctx.t.docs.reveal_turn } }).element
}

function crossroads(block, ctx) {
  const open = !!ctx.openAll
  const head = el("p", { class: "reveal-tag" }, icon("circle-help", "reveal-ic"), el("strong", { text: ctx.t.docs.cross_title }))
  const who = [block.year !== undefined ? yearLabel(block.year) : null, block.who_it].filter(Boolean)
  const whoLine = who.length ? el("p", { class: "reveal-who", text: who.join(" · ") }) : null
  const situation = renderInlineRich(block.situation_it, el("p", { class: "reveal-text" }), ctx)
  const list = el("ul", { class: "reveal-options", role: "group", "aria-label": ctx.t.docs.cross_choose })
  const outcome = el("div", { class: "reveal-then", "aria-live": "polite" })
  const buttons = new Map()
  let chosen = null
  const show = (option) => {
    chosen = option.id
    for (const [id, b] of buttons) b.setAttribute("aria-pressed", String(id === chosen))
    outcome.replaceChildren(el("p", { class: "reveal-tag" }, icon("next", "reveal-ic"), el("strong", { text: ctx.t.docs.cross_then })),
      renderInlineRich(option.then_it, el("p", { class: "reveal-text" }), ctx))
    go.toggle.disabled = false
    need.hidden = true
  }
  for (const option of block.options) {
    const b = el("button", { type: "button", class: "reveal-option", "aria-pressed": "false", "data-id": option.id })
    renderInlineRich(option.text_it, b, ctx)
    b.append(el("span", { class: "reveal-real-mark", hidden: "" }, icon("check", "reveal-ic"), el("strong", { text: ` ${ctx.t.docs.cross_real_tag}` })))
    b.addEventListener("click", () => show(option))
    buttons.set(option.id, b)
    const li = el("li", { class: "reveal-option-row" }, b)
    if (open) li.appendChild(renderInlineRich(option.then_it, el("p", { class: "reveal-then-print reveal-text" }), ctx))
    list.appendChild(li)
  }
  const real = block.options.find((o) => o.real)
  const back = [
    el("p", { class: "reveal-tag reveal-tag-answer" }, icon("check", "reveal-ic"), el("strong", { text: ctx.t.docs.cross_real_title })),
    el("div", { class: "reveal-text" }, renderRich(block.real_it, ctx)),
    el("p", { class: "reveal-others", text: ctx.t.docs.cross_others })
  ]
  const need = el("p", { class: "reveal-need", id: uid("need"), text: ctx.t.docs.cross_pick_first })
  const front = el("div", { class: "reveal-front" }, head, whoLine, situation, list, outcome)
  const go = flip({
    prefix: "reveal", front, back, ctx, control: "button", button: { text: ctx.t.docs.cross_real_button }, className: "reveal-cross",
    onChange: (isOpen) => {
      const mark = real && buttons.get(real.id)?.querySelector(".reveal-real-mark")
      if (mark) mark.hidden = !isOpen
      if (real) buttons.get(real.id)?.setAttribute("data-real", String(isOpen))
    }
  })
  if (!open) {
    go.toggle.disabled = true
    go.toggle.setAttribute("aria-describedby", need.id)
    go.element.insertBefore(need, go.toggle.nextSibling)
  }
  return go.element
}

export function render(block, ctx) {
  return block.options ? crossroads(block, ctx) : plain(block, ctx)
}
