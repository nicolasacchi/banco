// normalized_text: a text box, with on-screen buttons for the accented letters of
// the subject (Spanish: á é í ó ú ñ ü ¿ ¡, Italian: à è é ì ò ù). A student whose
// keyboard has no easy accents must not fail an item for that (E-03).
import { announceChange, el, handle, uid } from "items/dom"
import { insertAtCaret } from "items/helper_keys"
import { langOf } from "items/bilingual"

const ACCENTS = { es: ["á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡"], it: ["à", "è", "é", "ì", "ò", "ù"] }

export function render(part, ctx) {
  const id = uid("text")
  const input = el("input", {
    id, type: "text", autocomplete: "off", autocapitalize: "off", spellcheck: "false", class: "answer-input wide",
    lang: langOf(part) ?? (part.accents === "es" ? "es" : "it")
  })
  const wrapper = el("div", { class: "answer" },
    el("label", { for: id, class: "hint", text: ctx.t.text_label }), input)
  const letters = ACCENTS[part.accents]
  if (letters) {
    const keys = el("div", { class: "accent-keys", role: "group", "aria-label": ctx.t.accents_label })
    for (const letter of letters) {
      const button = el("button", { type: "button", class: "button secondary small", text: letter })
      button.addEventListener("click", () => { insertAtCaret(input, letter); announceChange(wrapper) })
      keys.appendChild(button)
    }
    wrapper.appendChild(keys)
  }
  input.addEventListener("input", () => announceChange(wrapper))
  return handle(wrapper, {
    raw: () => input.value.trim(),
    isEmpty: () => input.value.trim() === "",
    focus: () => input.focus(),
    draft: () => (input.value.trim() === "" ? "" : input.value),
    restore: (draft) => { if (typeof draft === "string") input.value = draft }
  })
}
