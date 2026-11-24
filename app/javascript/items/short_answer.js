// short_answer: a textarea. The text is a submission for the teacher to read; the
// server records it and the answer is shown corrected only after the teacher has
// confirmed the grade (B-06).
import { announceChange, el, handle, uid } from "items/dom"
import { langOf } from "items/bilingual"

export function render(part, ctx) {
  const id = uid("long")
  const area = el("textarea", { id, rows: "8", class: "answer-input wide", lang: langOf(part, "it"), spellcheck: "true" })
  const wrapper = el("div", { class: "answer" }, el("label", { for: id, class: "hint", text: ctx.t.long_text_label }), area)
  area.addEventListener("input", () => announceChange(wrapper))
  return handle(wrapper, {
    raw: () => area.value.trim(),
    isEmpty: () => area.value.trim() === "",
    focus: () => area.focus(),
    draft: () => (area.value.trim() === "" ? "" : area.value),
    restore: (draft) => { if (typeof draft === "string") area.value = draft }
  })
}
