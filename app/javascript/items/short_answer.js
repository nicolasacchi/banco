// short_answer: a textarea. The text is a submission for the teacher to read; the
// server records it and the answer is shown corrected only after the teacher has
// confirmed the grade (B-06).
import { el, handle, uid } from "items/dom"

export function render(_part, ctx) {
  const id = uid("long")
  const area = el("textarea", { id, rows: "8", class: "answer-input wide", lang: "it", spellcheck: "true" })
  const wrapper = el("div", { class: "answer" }, el("label", { for: id, class: "hint", text: ctx.t.long_text_label }), area)
  return handle(wrapper, {
    raw: () => area.value.trim(),
    isEmpty: () => area.value.trim() === "",
    focus: () => area.focus()
  })
}
