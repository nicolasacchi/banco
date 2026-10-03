// normalized_text: a text box, with on-screen buttons for the accented letters of
// the subject (Spanish: á é í ó ú ñ ü ¿ ¡, Italian: à è é ì ò ù). A student whose
// keyboard has no easy accents must not fail an item for that (E-03).
import { el, handle, uid } from "items/dom"

const ACCENTS = { es: ["á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡"], it: ["à", "è", "é", "ì", "ò", "ù"] }

export function render(part, ctx) {
  const id = uid("text")
  const input = el("input", {
    id, type: "text", autocomplete: "off", autocapitalize: "off", spellcheck: "false", class: "answer-input wide",
    lang: part.accents === "es" ? "es" : "it"
  })
  const wrapper = el("div", { class: "answer" },
    el("label", { for: id, class: "hint", text: ctx.t.text_label }), input)
  const letters = ACCENTS[part.accents]
  if (letters) {
    const keys = el("div", { class: "accent-keys", role: "group", "aria-label": ctx.t.accents_label })
    for (const letter of letters) {
      const button = el("button", { type: "button", class: "button secondary small", text: letter })
      button.addEventListener("click", () => insert(input, letter))
      keys.appendChild(button)
    }
    wrapper.appendChild(keys)
  }
  return handle(wrapper, {
    raw: () => input.value.trim(),
    isEmpty: () => input.value.trim() === "",
    focus: () => input.focus()
  })
}

function insert(input, letter) {
  const start = input.selectionStart ?? input.value.length
  const end = input.selectionEnd ?? input.value.length
  input.value = input.value.slice(0, start) + letter + input.value.slice(end)
  input.focus()
  input.setSelectionRange(start + letter.length, start + letter.length)
}
