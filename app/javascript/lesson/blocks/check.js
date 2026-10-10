// An inline question (A9). The page draws the input from the served fields (no answer in the page); the
// server grades: POST {response, try, client_event_id} -> {verdict, message_it, explain_it?, try, steps?}.
// "Sì." with a check icon, "Non ancora." with a lightbulb and the hint, in ink (no green, no red); retries are
// free; the explanation comes after a right answer or the second wrong one. Components: choice, number,
// fraction, normalized_text (the item templates), matching (rows of chips) and span_select.
import { newId } from "items/outbox"
import { handle } from "items/dom"
import { render as numberT } from "items/number"
import { render as fractionT } from "items/fraction"
import { render as choiceT } from "items/choice"
import { render as textT } from "items/normalized_text"
import { button, el, icon, uid } from "lesson/dom"
import { renderInlineRich, renderRich } from "lesson/text"
import { checkNotes } from "lesson/teacher_notes"

// matching: one row per item, the categories as chips (radios styled as chips: arrows move inside a row)
function matchingInput(spec, ctx) {
  const name = uid("match")
  const rows = spec.left.map((item, i) => {
    const group = el("div", { class: "chips", role: "radiogroup", "aria-labelledby": `${name}-l${i}` })
    spec.right.forEach((cat, j) => {
      const id = `${name}-${i}-${j}`
      const radio = el("input", { type: "radio", name: `${name}-${i}`, id, value: cat.id, class: "chip-input" })
      group.appendChild(el("span", { class: "chip" }, radio, renderInlineRich(cat.text_it, el("label", { for: id, class: "chip-label" }), ctx)))
    })
    return { item, group, row: el("div", { class: "match-row" }, renderInlineRich(item.text_it, el("p", { class: "match-item", id: `${name}-l${i}` }), ctx), group) }
  })
  const answers = () => Object.fromEntries(rows.map((r) => [r.item.id, r.group.querySelector("input:checked")?.value]).filter(([, v]) => v))
  return handle(el("div", { class: "answer matching-chips" }, rows.map((r) => r.row)), {
    raw: () => JSON.stringify(answers()),
    isEmpty: () => Object.keys(answers()).length < rows.length,
    focus: () => rows[0].group.querySelector("input")?.focus()
  })
}

// span_select: the sentence with its spans as buttons that toggle
function spanInput(spec, ctx) {
  const chosen = new Set()
  const box = el("p", { class: "spans", role: "group", "aria-label": ctx.t.spans_label })
  let rest = spec.text_it
  for (const span of spec.spans) {
    const at = rest.indexOf(span.text_it)
    if (at < 0) continue
    if (at > 0) box.appendChild(document.createTextNode(rest.slice(0, at)))
    const b = el("button", { type: "button", class: "span-chip", "aria-pressed": "false", "data-span": span.id })
    renderInlineRich(span.text_it, b, ctx)
    b.addEventListener("click", () => {
      if (chosen.has(span.id)) chosen.delete(span.id)
      else chosen.add(span.id)
      b.setAttribute("aria-pressed", String(chosen.has(span.id)))
    })
    box.appendChild(b)
    rest = rest.slice(at + span.text_it.length)
  }
  if (rest) box.appendChild(document.createTextNode(rest))
  return handle(el("div", { class: "answer" }, box), {
    raw: () => JSON.stringify([...chosen].sort((a, b) => Number(a.slice(1)) - Number(b.slice(1)))),
    isEmpty: () => chosen.size === 0,
    focus: () => box.querySelector("button")?.focus()
  })
}

// A fraction answer typed on one line ("3", "-5/3", "5/2"), as the exercise in the page asks for it: the server still
// reads {n, d} (an integer is n over 1), so the grading and its typical errors do not change.
export function fractionLineValue(text) {
  const clean = String(text).replace(/[\u2212\u2013]/g, "-").replace(/\s+/g, "")
  const at = clean.indexOf("/")
  return at < 0 ? { n: clean, d: "1" } : { n: clean.slice(0, at), d: clean.slice(at + 1) }
}

function fractionLineInput(spec, ctx) {
  const id = uid("fline")
  const field = el("input", {
    id, type: "text", inputmode: "text", autocomplete: "off", autocapitalize: "off", spellcheck: "false",
    class: "answer-input line-input", "aria-label": ctx.items.number_label
  })
  return handle(el("div", { class: "answer answer-line" }, field), {
    raw: () => JSON.stringify(fractionLineValue(field.value)),
    isEmpty: () => field.value.trim() === "",
    focus: () => field.focus()
  })
}

// The helper keys of a typed answer: they put the sign (and the bar of a fraction, the comma of a decimal) at the caret,
// where a phone keyboard may not show them.
function helperKeys(field, keys, ctx) {
  const row = el("span", { class: "helper-keys", role: "group", "aria-label": ctx.t.helper_keys })
  for (const [label, value, name] of keys) {
    row.appendChild(button(label, { class: "helper-key", "aria-label": name }, () => {
      const from = field.selectionStart ?? field.value.length
      const to = field.selectionEnd ?? field.value.length
      field.value = field.value.slice(0, from) + value + field.value.slice(to)
      field.focus()
      field.setSelectionRange(from + value.length, from + value.length)
    }))
  }
  return row
}

const isLine = (spec) => (spec.component === "fraction" && !spec.mixed) || spec.component === "number"

function input(spec, ctx, options = {}) {
  const part = { ...spec, unit: spec.unit, mixed: spec.mixed }
  switch (spec.component) {
    case "choice": return choiceT({ ...part, options: spec.options.map((o) => ({ id: o.id, text: o.text_it })) }, { t: ctx.items })
    case "number": return numberT(part, { t: ctx.items })
    case "fraction": return options.inline && !spec.mixed ? fractionLineInput(spec, ctx) : fractionT(part, { t: ctx.items })
    case "normalized_text": return textT(part, { t: ctx.items })
    case "matching": return matchingInput(spec, ctx)
    case "span_select": return spanInput(spec, ctx)
    default: throw new Error(`no check component ${spec.component}`)
  }
}

// loc: { card, block, step?, ex?, part? } -> the endpoint is built by ctx.checkUrl(loc).
// options: { onDone(reply, tries) } called with the final reply of a right answer or the second wrong one.
export function renderCheck(spec, ctx, loc, options = {}) {
  const form = el("form", { class: "check", novalidate: "" })
  // options.inline (the exercises): a typed answer is one line, "x = [  ] [-] [/] [Controlla]", with the helper keys;
  // options.quietPrompt: the prompt stays for the screen reader only when the line says it ("x =")
  const line = !!options.inline && isLine(spec)
  const prompt = el("div", { class: `check-prompt${line && options.quietPrompt && spec.input_before ? " sr-only" : ""}` })
  prompt.appendChild(renderRich(spec.prompt_it, ctx))
  const handleInput = input(spec, ctx, options)
  const row = el("div", { class: `check-row${line ? " is-line" : ""}` })
  if (spec.input_before) row.appendChild(renderInlineRich(spec.input_before, el("span", { class: "check-before" }), ctx))
  row.appendChild(handleInput.element)
  if (line) {
    const field = handleInput.element.querySelector("input")
    const asFraction = spec.component === "fraction"
    row.appendChild(helperKeys(field, asFraction ? [["\u2212", "-", ctx.t.key_minus], ["/", "/", ctx.t.key_bar]] : [["\u2212", "-", ctx.t.key_minus], [",", ",", ctx.t.key_comma]], ctx))
  }
  if (spec.input_after) row.appendChild(renderInlineRich(spec.input_after, el("span", { class: "check-after" }), ctx))
  if (spec.answer_format_it) form.appendChild(el("p", { class: "hint", text: spec.answer_format_it }))
  const submit = button(ctx.t.check_button, { class: `button small${line ? " check-go" : ""}`, type: "submit" })
  const feedback = el("div", { class: "feedback", "aria-live": "polite", role: "status" })
  if (line) {
    row.appendChild(submit)
    form.append(prompt, row, feedback)
    if (spec.component === "fraction" && !spec.answer_format_it) form.insertBefore(el("p", { class: "hint line-hint", text: ctx.t.fraction_line_hint }), feedback)
  } else form.append(prompt, row, el("p", { class: "check-actions" }, submit), feedback)

  if (ctx.teacher) {
    const notes = checkNotes(ctx.full?.spec(loc), ctx)
    if (notes) form.appendChild(notes)
  }

  let tries = 0
  let pending = null
  let done = false
  const say = (kind, text, explain) => {
    clear(feedback)
    const head = el("p", { class: `verdict verdict-${kind}` }, icon(kind === "right" ? "circle-check" : "wrong-hint", "verdict-ic"), el("strong", { text: kind === "right" ? ctx.t.right : kind === "wrong" ? ctx.t.wrong : ctx.t.invalid }))
    feedback.appendChild(head)
    if (text) feedback.appendChild(el("div", { class: "verdict-text" }, renderRich(text, ctx)))
    if (explain) feedback.appendChild(el("div", { class: "verdict-explain" }, renderRich(explain, ctx)))
  }
  const clear = (node) => {
    while (node.firstChild) node.removeChild(node.firstChild)
  }
  form.addEventListener("submit", async (event) => {
    event.preventDefault()
    if (done) return
    if (handleInput.isEmpty()) {
      say("invalid", ctx.t.check_empty)
      handleInput.focus()
      return
    }
    submit.disabled = true
    const label = submit.textContent
    submit.textContent = ctx.t.checking
    pending ||= newId()
    let reply = null
    try {
      reply = await ctx.postCheck(loc, { response: handleInput.raw(), try: tries + 1, client_event_id: pending })
    } catch (_error) {
      reply = null
    }
    submit.disabled = false
    submit.textContent = label
    if (!reply) {
      say("invalid", ctx.t.check_error)
      return
    }
    pending = null
    if (reply.verdict === "invalid") {
      say("invalid", reply.message_it || ctx.t.check_empty)
      return
    }
    tries = reply.try ?? tries + 1
    if (reply.verdict === "right") {
      say("right", null, reply.explain_it)
      done = true
      lock(form)
      options.onDone?.(reply, tries)
    } else {
      say("wrong", reply.message_it || ctx.t.try_again, reply.explain_it)
      if (reply.explain_it || reply.steps) options.onDone?.(reply, tries)
    }
  })
  return { element: form, focus: () => handleInput.focus() }
}

function lock(form) {
  for (const control of form.querySelectorAll("input, button.span-chip, textarea, select")) control.disabled = true
  form.classList.add("is-done")
  form.querySelector("[type=submit]").disabled = true
}
