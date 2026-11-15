// number: one text box. The decimal comma is the only separator; the server reads
// the text exactly (E-03). The unit, when the item has one, is a suffix on screen. The keys «−» and «,» sit after the box:
// the phone's decimal pad has no minus.
import { el, handle, uid } from "items/dom"
import { commaKey, helperKeys, minusKey } from "items/helper_keys"

// The help line of the box: a whole-number check (`integer`, set by Lessons::StudentBody when the key and every accepted value are whole) says
// nothing about decimals, since no decimal is ever the answer (D-335).
const labelOf = (part, t) => (part.scientific ? t.number_scientific_label : part.integer ? t.number_integer_label : t.number_label)

export function render(part, ctx) {
  const id = uid("number")
  const input = el("input", {
    id, type: "text", inputmode: part.scientific ? "text" : "decimal", autocomplete: "off", autocapitalize: "off", spellcheck: "false",
    class: "answer-input", "aria-label": labelOf(part, ctx.t)
  })
  const field = () => input
  const keys = helperKeys([minusKey(field, ctx.t), commaKey(field, ctx.t)], ctx.t)
  const row = el("div", { class: "field" }, input, keys, part.unit ? el("span", { class: "unit", text: part.unit }) : null)
  const wrapper = el("div", { class: "answer" }, el("label", { for: id, class: "hint", text: labelOf(part, ctx.t) }), row)
  return handle(wrapper, {
    raw: () => input.value.trim(),
    isEmpty: () => input.value.trim() === "",
    focus: () => input.focus()
  })
}
