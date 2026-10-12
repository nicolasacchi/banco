// oral (WAVE2 2.10): rehearse an answer for the oral exam. A question; an outline of the answer to put in order (graded by the check endpoint as an
// ordering); the connectives and terms to say. When the outline is right, or after the second try, the model answer appears ("Risposta modello",
// withheld by the server until then, L6). Then "Ora dilla tu, ad alta voce": on the card, our fixed line says it is optional and that nothing
// listens and nothing is recorded, with a short self-check that is not stored. No microphone, no recording, nothing sent.
// The outline uses the ordering component of lesson/checks when it is available (the frozen signature render(check, ctx, hooks), WAVE2 2.11);
// until then a small list with "su" and "giù" buttons stands in, with the same answer: the shown ids in the order S built.
import { newId } from "items/outbox"
import { button, el, icon, uid } from "lesson/dom"
import { isAvailable, load } from "lesson/checks/registry"
import { renderInlineRich, renderRich } from "lesson/text"

// The stand-in outline: rows with Sposta su / Sposta giù. Returns { element, order(), focus() }.
export function outlineList(outline, ctx) {
  const order = outline.map((o) => o.id)
  const byId = new Map(outline.map((o) => [o.id, o]))
  const list = el("ol", { class: "oral-outline", "aria-label": ctx.t.docs.oral_outline_label })
  const live = el("p", { class: "sr-only", "aria-live": "polite" })
  const draw = (focusId, focusDir) => {
    list.replaceChildren(...order.map((id, i) => {
      const item = byId.get(id)
      const name = item.text_it.replace(/[$\\{}]|\[\[[a-z-]+:|\]\]/g, "")
      const up = button("", { class: "oral-move", "aria-label": `${ctx.t.docs.oral_up}: ${name}`, "data-dir": "up" }, () => move(i, -1))
      const down = button("", { class: "oral-move", "aria-label": `${ctx.t.docs.oral_down}: ${name}`, "data-dir": "down" }, () => move(i, 1))
      up.appendChild(icon("prev", "oral-arrow oral-arrow-up"))
      down.appendChild(icon("prev", "oral-arrow oral-arrow-down"))
      up.disabled = i === 0
      down.disabled = i === order.length - 1
      const row = el("li", { class: "oral-tile", "data-id": id }, el("span", { class: "oral-pos", "aria-hidden": "true", text: String(i + 1) }),
        renderInlineRich(item.text_it, el("span", { class: "oral-tile-text" }), ctx), el("span", { class: "oral-moves" }, up, down))
      return row
    }))
    if (focusId) list.querySelector(`[data-id="${focusId}"] [data-dir="${focusDir}"]:not(:disabled)`)?.focus() ?? list.querySelector(`[data-id="${focusId}"] .oral-move:not(:disabled)`)?.focus()
  }
  const move = (i, step) => {
    const j = i + step
    if (j < 0 || j >= order.length) return
    ;[order[i], order[j]] = [order[j], order[i]]
    live.textContent = ctx.t.docs.oral_moved.replace("%{n}", j + 1).replace("%{total}", order.length)
    draw(order[j], step < 0 ? "up" : "down")
  }
  draw()
  return { element: el("div", { class: "answer oral-answer" }, list, live), order: () => order.slice(), focus: () => list.querySelector(".oral-move:not(:disabled)")?.focus() }
}

function pills(title, items, cls) {
  if (!items?.length) return null
  const row = el("p", { class: `oral-pills ${cls}` }, el("strong", { text: `${title}: ` }))
  items.forEach((t, i) => row.append(el("span", { class: "oral-pill", text: t }), i < items.length - 1 ? document.createTextNode(" ") : ""))
  return row
}

function selfCheck(ctx) {
  const box = el("div", { class: "oral-say" },
    el("h4", { class: "oral-say-title", text: ctx.t.docs.oral_say }),
    el("p", { class: "oral-private" }, icon("info", "oral-ic"), document.createTextNode(` ${ctx.t.docs.oral_private}`)))
  const list = el("ul", { class: "oral-self" })
  ctx.t.docs.oral_self.forEach((line) => {
    const id = uid("self")
    list.appendChild(el("li", {}, el("input", { type: "checkbox", id }), el("label", { for: id, text: ` ${line}` })))
  })
  box.append(el("p", { class: "oral-self-title", text: ctx.t.docs.oral_self_title }), list)
  return box
}

export function render(block, ctx, loc = {}) {
  const root = el("section", { class: "block oral", "aria-label": ctx.t.docs.oral_title })
  root.appendChild(el("p", { class: "oral-tag" }, icon("circle-help", "oral-ic"), el("strong", { text: ctx.t.docs.oral_title })))
  root.appendChild(renderInlineRich(block.question_it, el("p", { class: "oral-question" }), ctx))
  if (ctx.safe || ctx.openAll) {
    const list = el("ul", { class: "oral-outline-plain" })
    for (const o of block.outline) list.appendChild(renderInlineRich(o.text_it, el("li"), ctx))
    root.append(el("p", { class: "hint", text: ctx.t.docs.oral_outline_label }), list)
    if (ctx.safe) return root
  }
  const model = el("div", { class: "oral-model", "aria-live": "polite" })
  const showModel = (text) => {
    if (!text || model.childElementCount) return
    model.append(el("h4", { class: "oral-model-title", text: ctx.t.docs.oral_model }), el("div", { class: "oral-model-text" }, renderRich(text, ctx)), selfCheck(ctx))
  }
  // the teacher's view and print show the model answer, from the full body (the student's page never has it before the check says so)
  if (ctx.openAll && !ctx.safe) showModel(ctx.full?.spec(loc)?.model_it)
  const feedback = el("div", { class: "feedback", "aria-live": "polite", role: "status" })
  const pillRows = [pills(ctx.t.docs.oral_connectives, block.connectives, "oral-connectives"), pills(ctx.t.docs.oral_terms, block.terms, "oral-terms")]
  if (!ctx.safe && !ctx.openAll) {
    root.appendChild(el("p", { class: "hint", text: ctx.t.docs.oral_help }))
    const form = el("form", { class: "check oral-form", novalidate: "" })
    const fallback = outlineList(block.outline, ctx)
    let input = { element: fallback.element, order: fallback.order, focus: fallback.focus }
    const slot = el("div", { class: "oral-slot" }, input.element)
    // T1's ordering component, when it has landed: the same answer, its own tiles
    if (isAvailable("ordering")) {
      load("ordering").then((mod) => {
        let answer = null
        const node = mod.render({ component: "ordering", elements: block.outline, prompt_it: block.question_it }, ctx, { answer: (value) => { answer = value } })
        slot.replaceChildren(node?.element ?? node)
        input = { element: slot, order: () => answer ?? node?.order?.() ?? fallback.order(), focus: () => node?.focus?.() }
      }).catch(() => {})
    }
    const submit = button(ctx.t.check_button, { class: "button small", type: "submit" })
    form.append(slot, el("p", { class: "check-actions" }, submit), feedback)
    let tries = 0
    let pending = null
    let done = false
    const say = (kind, text) => {
      feedback.replaceChildren(el("p", { class: `verdict verdict-${kind}` }, icon(kind === "right" ? "circle-check" : "wrong-hint", "verdict-ic"), el("strong", { text: kind === "right" ? ctx.t.right : kind === "wrong" ? ctx.t.wrong : ctx.t.invalid })))
      if (text) feedback.appendChild(el("div", { class: "verdict-text" }, renderRich(text, ctx)))
    }
    form.addEventListener("submit", async (event) => {
      event.preventDefault()
      if (done) return
      submit.disabled = true
      pending ||= newId()
      let reply = null
      try {
        reply = await ctx.postCheck(loc, { response: input.order(), try: tries + 1, client_event_id: pending })
      } catch (_error) {
        reply = null
      }
      submit.disabled = false
      if (!reply) return say("invalid", ctx.t.check_error)
      pending = null
      if (reply.verdict === "invalid") return say("invalid", reply.message_it || ctx.t.check_empty)
      tries = reply.try ?? tries + 1
      if (reply.verdict === "right") {
        say("right")
        done = true
        submit.disabled = true
        for (const b of form.querySelectorAll(".oral-move")) b.disabled = true
      } else say("wrong", reply.message_it || ctx.t.try_again)
      showModel(reply.model_it)
    })
    root.appendChild(form)
  }
  pillRows.forEach((row) => row && root.appendChild(row))
  root.appendChild(model)
  return root
}
