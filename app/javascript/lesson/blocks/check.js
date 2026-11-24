// An inline question (A9). The page draws the input from the served fields (no answer in the page); the
// server grades: POST {response, try, client_event_id} -> {verdict, message_it, explain_it?, try, steps?}.
// "Sì." with a check icon, "Non ancora." with a lightbulb and the hint, in ink (no green, no red); retries are
// free; the explanation comes after a right answer or the second wrong one. Components: choice, number,
// fraction, normalized_text (the item templates), matching (rows of chips) and span_select.
import { newId } from "items/outbox"
import { handle } from "items/dom"
import { barKey, helperKeys, minusKey } from "items/helper_keys"
import { render as numberT } from "items/number"
import { render as fractionT } from "items/fraction"
import { render as choiceT } from "items/choice"
import { render as textT } from "items/normalized_text"
import { button, el, icon, uid } from "lesson/dom"
import { beside, inButton, insideControl, materialOf, noTranslation, renderInlineRich, renderRich, scoped } from "lesson/text"
import { checkNotes } from "lesson/teacher_notes"
import { moduleFor as checkModule } from "lesson/checks/registry"
import { howtoNodes } from "lesson/checks/howto"
import { bitsInput } from "lesson/checks/bits_input"
import { listenBox } from "lesson/checks/listen"

// matching: one row per item, the categories as chips (radios styled as chips: arrows move inside a row)
function matchingInput(spec, ctx) {
  const name = uid("match")
  const rows = spec.left.map((item, i) => {
    const group = el("div", { class: "chips", role: "radiogroup", "aria-labelledby": `${name}-l${i}` })
    spec.right.forEach((cat, j) => {
      const id = `${name}-${i}-${j}`
      const radio = el("input", { type: "radio", name: `${name}-${i}`, id, value: cat.id, class: "chip-input" })
      group.appendChild(el("span", { class: "chip" }, radio, renderInlineRich(cat.text_it, el("label", { for: id, class: "chip-label" }), inButton(ctx))))
    })
    return { item, group, row: el("div", { class: "match-row" }, renderInlineRich(item.text_it, el("p", { class: "match-item", id: `${name}-l${i}` }), materialOf(spec, ctx)), group) }
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
  const key = spec.text_en != null ? "text_en" : spec.text_es != null ? "text_es" : "text_it"
  const lang = key === "text_en" ? "en" : key === "text_es" ? "es" : null
  if (lang) box.setAttribute("lang", lang)
  if (lang && ctx.lang) box.setAttribute("data-tr-exempt", "") // the sentence is the exercise: the prompt's translation says what to do with it
  let rest = spec[key]
  for (const span of spec.spans) {
    const at = rest.indexOf(span[key])
    if (at < 0) continue
    if (at > 0) box.appendChild(document.createTextNode(rest.slice(0, at)))
    const b = el("button", { type: "button", class: "span-chip", "aria-pressed": "false", "data-span": span.id })
    if (lang) b.appendChild(document.createTextNode(span[key]))
    else renderInlineRich(span[key], b, inButton(ctx))
    b.addEventListener("click", () => {
      if (chosen.has(span.id)) chosen.delete(span.id)
      else chosen.add(span.id)
      b.setAttribute("aria-pressed", String(chosen.has(span.id)))
    })
    box.appendChild(b)
    rest = rest.slice(at + span[key].length)
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
  // the helper keys of the one line: the sign and the bar of a fraction, where a phone keyboard may not show them (the number's own
  // keys are drawn by items/number)
  const keys = helperKeys([minusKey(() => field, ctx.items), barKey(() => field, ctx.items)], ctx.items)
  return handle(el("div", { class: "answer answer-line" }, el("div", { class: "field" }, field, keys)), {
    raw: () => JSON.stringify(fractionLineValue(field.value)),
    isEmpty: () => field.value.trim() === "",
    focus: () => field.focus()
  })
}

const isLine = (spec) => (spec.component === "fraction" && !spec.mixed) || spec.component === "number"

function input(spec, ctx, options = {}) {
  const part = { ...spec, unit: spec.unit, mixed: spec.mixed }
  switch (spec.component) {
    // the options are drawn with the lesson's inline markup, as the prompt is (a word of another language, a formula in its colours: D-310)
    case "choice": return choiceT({ ...part, options: spec.options.map((o) => ({ id: o.id, text: o.text_it })) }, { t: ctx.items, inline: (text, node) => renderInlineRich(text, node, insideControl(materialOf(spec, ctx))) })
    case "number": return numberT(part, { t: ctx.items })
    case "fraction": return options.inline && !spec.mixed ? fractionLineInput(spec, ctx) : fractionT(part, { t: ctx.items })
    case "normalized_text": return spec.input === "bits" && spec.input_width ? bitsInput(spec, ctx) : textT(part, { t: ctx.items })
    case "matching": return matchingInput(spec, ctx)
    case "span_select": return spanInput(spec, ctx)
    default: {
      // select, tiles, ordering...: lesson/checks/*, loaded before the page is drawn (lesson/preload.js); render() gives the input handle
      const mod = checkModule(spec.component)
      if (!mod) throw new Error(`no check component ${spec.component}`)
      return mod.render(spec, ctx, {})
    }
  }
}

// loc: { card, block, step?, ex?, part? } -> the endpoint is built by ctx.checkUrl(loc).
// options: { onDone(reply, tries) } called with the final reply of a right answer or the second wrong one.
export function renderCheck(spec, ctx, loc, options = {}) {
  const form = el("form", { class: "check", novalidate: "" })
  // options.inline (the exercises): a typed answer is one line, "x = [  ] [-] [/] [Controlla]", with the helper keys.
  // The prompt is always drawn: it is the request ("Calcola il perimetro"), the text around the box only labels the box.
  const line = !!options.inline && isLine(spec)
  const prompt = el("div", { class: "check-prompt" })
  prompt.appendChild(renderRich(spec.prompt_it, ctx))
  // the check's own sentence (D-402): the form material it is about, target-only (no translation, no «translation missing»), under the instruction and above the options
  const sentence = spec.sentence_it ? el("div", { class: "check-sentence" }, renderRich(spec.sentence_it, noTranslation(ctx))) : null
  const handleInput = input(spec, ctx, options)
  // text before and after the box: the three stay together, as the sentence they make, and the box's hint ("Scrivi il numero...") goes on
  // its own line above them, still the box's label (D-310: on a phone it sat between the formula and the box). The accent keyboard goes
  // below the sentence, never between the box and its `input_after` (D-402: the sentence was split in two at 390 px).
  const around = !line && Boolean(spec.input_before || spec.input_after)
  const row = el("div", { class: `check-row${line ? " is-line" : ""}${around ? " is-around" : ""}` })
  const hint = around ? handleInput.element.querySelector(":scope > label.hint") : null
  const keys = around ? handleInput.element.querySelector(":scope > .accent-keys") : null
  // the words around the box are a fragment of the sentence the box completes, never translated alone (D-402): the prompt's translation says what to write
  const fragment = noTranslation(ctx)
  if (spec.input_before) row.appendChild(renderInlineRich(spec.input_before, el("span", { class: "check-before" }), fragment, { inline: true }))
  row.appendChild(handleInput.element)
  if (spec.input_after) row.appendChild(renderInlineRich(spec.input_after, el("span", { class: "check-after" }), fragment, { inline: true }))
  if (spec.answer_format_it) form.appendChild(beside(el("p", { class: "hint", text: spec.answer_format_it }), spec.answer_format_it, ctx))
  const submit = button(ctx.t.check_button, { class: `button small${line ? " check-go" : ""}`, type: "submit" })
  const feedback = el("div", { class: "feedback", "aria-live": "polite", role: "status" })
  if (line) {
    row.appendChild(submit)
    form.append(prompt, ...(sentence ? [sentence] : []), row, feedback)
    if (spec.component === "fraction" && !spec.answer_format_it) form.insertBefore(el("p", { class: "hint line-hint", text: ctx.t.fraction_line_hint }), feedback)
  } else form.append(prompt, ...(sentence ? [sentence] : []), ...(hint ? [hint] : []), row, ...(keys ? [keys] : []), el("p", { class: "check-actions" }, submit), feedback)

  // the fixed how-to line of a new component on its first use in the lesson, and its closed "Come si risponde" (A9)
  const [howto, help] = howtoNodes(spec, ctx, loc)
  if (howto) (sentence ?? prompt).after(howto)
  if (help) form.appendChild(help)
  // `listen`: the question is heard; its text stays behind "Mostra il testo" and an answer after looking is sent as text_shown
  const listen = ctx.safe ? null : listenBox(spec, ctx)
  if (listen) (howto ?? sentence ?? prompt).after(listen.element)

  if (ctx.teacher) {
    const notes = checkNotes(ctx.full?.spec(loc), ctx)
    if (notes) form.appendChild(notes)
  }

  // «Per me va bene così» (D-396): after a wrong try, under the feedback, and only on the student's page (ctx.contest). It sends the answer he gave last
  // to the teacher; the check then shows «Mandato al docente» and is finished, as one answered right is.
  const contestBox = ctx.contest ? el("div", { class: "check-contest", hidden: "" }) : null
  if (contestBox) feedback.after(contestBox)
  const offerContest = () => {
    if (!contestBox || done) return
    const note = el("p", { class: "contest-note", text: ctx.t.checks.contest_note })
    const send = button(ctx.t.checks.contest_button, { class: "button text small contest-button" }, async () => {
      send.disabled = true
      let reply = null
      try {
        reply = await ctx.contest(loc)
      } catch (_error) {
        reply = null
      }
      if (reply?.status !== "contested") {
        send.disabled = false
        contestBox.appendChild(el("p", { class: "contest-error", role: "alert", text: ctx.t.checks.contest_error }))
        return
      }
      done = true
      lock(form)
      if (reply.explain_it && !feedback.querySelector(".verdict-explain")) feedback.appendChild(el("div", { class: "verdict-explain" }, renderRich(reply.explain_it, replyCtx(reply))))
      contestBox.replaceChildren(
        el("p", { class: "verdict verdict-sent", role: "status" }, icon("circle-check", "verdict-ic"), el("strong", { text: ctx.t.checks.contested })),
        el("p", { class: "contest-note", text: ctx.t.checks.contested_note })
      )
      options.onDone?.(reply, tries)
    })
    contestBox.replaceChildren(note, send)
    contestBox.hidden = false
  }

  let tries = 0
  // the event id of an answer whose reply was lost: the same answer sent again keeps it (the server answers for the row it has), another answer has its own
  let pending = null
  let done = false
  // what the reply says is drawn with the reply's own table of translations in front of the block's (D-402)
  const replyCtx = (reply) => (ctx.lang && reply?.tr ? scoped(ctx, reply) : ctx)
  const say = (kind, text, explain, reply) => {
    const cx = replyCtx(reply)
    clear(feedback)
    const head = el("p", { class: `verdict verdict-${kind}` }, icon(kind === "right" ? "circle-check" : "wrong-hint", "verdict-ic"), el("strong", { text: kind === "right" ? ctx.t.right : kind === "wrong" ? ctx.t.wrong : ctx.t.invalid }))
    feedback.appendChild(head)
    if (text) feedback.appendChild(el("div", { class: "verdict-text" }, renderRich(text, cx)))
    if (explain) feedback.appendChild(el("div", { class: "verdict-explain" }, renderRich(explain, cx)))
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
    const response = handleInput.raw()
    if (pending?.response !== response) pending = { id: newId(), response }
    let reply = null
    try {
      reply = await ctx.postCheck(loc, { response, try: tries + 1, client_event_id: pending.id, ...(listen?.shown() ? { text_shown: true } : {}) })
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
      say("invalid", reply.message_it || ctx.t.check_empty, undefined, reply)
      return
    }
    tries = reply.try ?? tries + 1
    if (reply.verdict === "right") {
      say("right", reply.message_it, reply.explain_it, reply)
      done = true
      if (contestBox) contestBox.hidden = true
      lock(form)
      options.onDone?.(reply, tries)
    } else {
      say("wrong", reply.message_it || ctx.t.try_again, reply.explain_it, reply)
      offerContest()
      if (reply.explain_it || reply.steps) options.onDone?.(reply, tries)
    }
  })
  return { element: form, focus: () => handleInput.focus() }
}

function lock(form) {
  for (const control of form.querySelectorAll("input, button.span-chip, button.tile, button.bit-switch, button.order-move, button.dg-target, button.tiles-clear, button.tiles-listen, textarea, select")) control.disabled = true
  form.classList.add("is-done")
  form.querySelector("[type=submit]").disabled = true
}
