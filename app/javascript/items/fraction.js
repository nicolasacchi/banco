// fraction: two labelled integer boxes (numerator over denominator), plus a whole
// part box when the item asks for a mixed number. Integer boxes keep the editor
// out of fraction items (E-03). The raw answer is JSON text: {"n","d"} and an
// optional "w" (decision D-030).
import { el, handle, uid } from "items/dom"

function box(label, id) {
  return el("input", {
    id, type: "text", inputmode: "numeric", autocomplete: "off", spellcheck: "false", class: "answer-input small",
    "aria-label": label
  })
}

export function render(part, ctx) {
  const ids = { w: uid("whole"), n: uid("num"), d: uid("den") }
  const whole = part.mixed ? box(ctx.t.fraction_whole, ids.w) : null
  const numerator = box(ctx.t.fraction_numerator, ids.n)
  const denominator = box(ctx.t.fraction_denominator, ids.d)

  const stack = el("div", { class: "fraction" },
    el("label", { for: ids.n, class: "hint", text: ctx.t.fraction_numerator }), numerator,
    el("div", { class: "frac-line", "aria-hidden": "true" }),
    el("label", { for: ids.d, class: "hint", text: ctx.t.fraction_denominator }), denominator)
  const row = el("div", { class: "field" },
    whole ? el("div", { class: "whole" }, el("label", { for: ids.w, class: "hint", text: ctx.t.fraction_whole }), whole) : null,
    stack)
  const wrapper = el("div", { class: "answer" }, row)

  const boxes = () => ({ n: numerator.value.trim(), d: denominator.value.trim(), w: whole ? whole.value.trim() : "" })
  return handle(wrapper, {
    raw: () => {
      const b = boxes()
      const out = { n: b.n, d: b.d }
      if (whole && b.w !== "") out.w = b.w
      return JSON.stringify(out)
    },
    isEmpty: () => {
      const b = boxes()
      return b.n === "" && b.d === "" && b.w === ""
    },
    focus: () => (whole || numerator).focus()
  })
}
