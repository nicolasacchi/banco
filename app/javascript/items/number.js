// number: one text box. The decimal comma is the only separator; the server reads
// the text exactly (E-03). The unit, when the item has one, is a suffix on screen.
import { el, handle, uid } from "items/dom"

export function render(part, ctx) {
  const id = uid("number")
  const input = el("input", {
    id, type: "text", inputmode: part.scientific ? "text" : "decimal", autocomplete: "off", autocapitalize: "off", spellcheck: "false",
    class: "answer-input", "aria-label": part.scientific ? ctx.t.number_scientific_label : ctx.t.number_label
  })
  const row = el("div", { class: "field" }, input, part.unit ? el("span", { class: "unit", text: part.unit }) : null)
  const wrapper = el("div", { class: "answer" }, el("label", { for: id, class: "hint", text: part.scientific ? ctx.t.number_scientific_label : ctx.t.number_label }), row)
  return handle(wrapper, {
    raw: () => input.value.trim(),
    isEmpty: () => input.value.trim() === "",
    focus: () => input.focus()
  })
}
