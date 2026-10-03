// choice: a radio group. Arrow keys move inside the group (native); the keys 1 to
// 5 pick an option; "Non lo so" is outside the options (E-03). The options and
// their ids arrive already shuffled and re-keyed by the server (X-01).
import { el, handle, uid } from "items/dom"
import { renderInline } from "items/markup"

export function render(part, ctx) {
  const name = uid("choice")
  const radios = (part.options || []).map((option, index) => {
    const id = `${name}-${index}`
    const radio = el("input", { type: "radio", name, id, value: option.id })
    const text = renderInline(option.text, el("span", { class: "option-text" }))
    return { radio, row: el("label", { for: id, class: "option" }, radio, el("span", { class: "option-key", "aria-hidden": "true", text: String(index + 1) }), text) }
  })
  const group = el("fieldset", { class: "answer options" }, el("legend", { class: "hint", text: ctx.t.choice_label }), radios.map((r) => r.row))
  group.addEventListener("keydown", (event) => {
    if (event.altKey || event.ctrlKey || event.metaKey) return
    const index = Number(event.key) - 1
    if (Number.isInteger(index) && index >= 0 && index < radios.length) {
      radios[index].radio.checked = true
      radios[index].radio.focus()
      event.preventDefault()
    }
  })
  const chosen = () => radios.find((r) => r.radio.checked)?.radio.value || ""
  return handle(group, {
    raw: chosen,
    isEmpty: () => chosen() === "",
    focus: () => (radios.find((r) => r.radio.checked) || radios[0])?.radio.focus()
  })
}
