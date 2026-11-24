// choice: a radio group. Arrow keys move inside the group (native); the keys 1 to
// 5 pick an option; "Non lo so" is outside the options (E-03). The options and
// their ids arrive already shuffled and re-keyed by the server (X-01). An option is drawn with the markup of the item's own text
// (items/markup); a lesson check hands ctx.inline, its own inline renderer, so that its options read like its prompt (D-310).
import { announceChange, el, handle, uid } from "items/dom"
import { renderInline } from "items/markup"
import { bare, langOf, trNode } from "items/bilingual"

export function render(part, ctx) {
  const name = uid("choice")
  const inline = ctx.inline ?? renderInline
  const lang = langOf(part)
  const radios = (part.options || []).map((option, index) => {
    const id = `${name}-${index}`
    const radio = el("input", { type: "radio", name, id, value: option.id })
    const text = inline(option.text, el("span", { class: "option-text" }))
    // A bilingual option (D-402): the target text and, under it in the same label, its Italian, shown when the exercise's translation is open. No button here.
    const { italian } = bare(option, "text", lang)
    const body = italian ? el("span", { class: "option-body", lang }, text, trNode(italian, { tag: "span" })) : text
    return { radio, row: el("label", { for: id, class: "option", "data-comment-anchor": `option:${index + 1}` }, radio, el("span", { class: "option-key", "aria-hidden": "true", text: String(index + 1) }), body) }
  })
  const group = el("fieldset", { class: "answer options" }, el("legend", { class: "hint", text: ctx.t.choice_label }), radios.map((r) => r.row))
  group.addEventListener("keydown", (event) => {
    if (event.altKey || event.ctrlKey || event.metaKey) return
    const index = Number(event.key) - 1
    if (Number.isInteger(index) && index >= 0 && index < radios.length) {
      radios[index].radio.checked = true
      radios[index].radio.focus()
      event.preventDefault()
      announceChange(group)
    }
  })
  radios.forEach(({ radio }) => radio.addEventListener("change", () => announceChange(group)))
  const chosen = () => radios.find((r) => r.radio.checked)?.radio.value || ""
  return handle(group, {
    raw: chosen,
    isEmpty: () => chosen() === "",
    focus: () => (radios.find((r) => r.radio.checked) || radios[0])?.radio.focus(),
    draft: chosen,
    // "" clears the choice; an id that is not an option of this item is ignored.
    restore: (draft) => {
      if (typeof draft !== "string") return
      const found = radios.find((r) => r.radio.value === draft)
      if (found) found.radio.checked = true
      else if (draft === "") radios.forEach((r) => { r.radio.checked = false })
    }
  })
}
