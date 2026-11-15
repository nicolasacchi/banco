// The helper keys of a typed answer: buttons that put a sign (the minus, the comma of a decimal, the bar of a fraction) at the
// caret of a box, because a phone keyboard may not show them (an iPhone "decimal" or "numeric" pad has no minus). One module for
// the item templates (number, fraction) and the lesson's inline checks, so a box has one row of keys, never two.
import { el } from "items/dom"

export const MINUS = "\u2212"

// Put `value` at the caret of `field` (over the selection), keep the focus in the box and the caret after it.
export function insertAtCaret(field, value) {
  const start = field.selectionStart ?? field.value.length
  const end = field.selectionEnd ?? field.value.length
  field.value = field.value.slice(0, start) + value + field.value.slice(end)
  field.focus()
  field.setSelectionRange(start + value.length, start + value.length)
}

// keys: [{ label, value, name, field }]: the glyph on the key, the text it inserts ("-" for the minus: the server reads the
// ASCII sign), its spoken name, and the box it writes into (a function, for a key whose box is the one last used).
// A key is type=button (it never submits the form), a pointer press does not take the focus from the box (the phone keyboard
// stays up), and being a button it is reached by Tab and pressed by Space or Enter.
export function helperKeys(keys, t) {
  const row = el("span", { class: "helper-keys", role: "group", "aria-label": t.helper_keys })
  for (const key of keys) {
    const button = el("button", { type: "button", class: "helper-key", "aria-label": key.name, text: key.label })
    button.addEventListener("mousedown", (event) => event.preventDefault())
    button.addEventListener("click", () => insertAtCaret(key.field(), key.value))
    row.appendChild(button)
  }
  return row
}

export const minusKey = (field, t) => ({ label: MINUS, value: "-", name: t.key_minus, field })
export const commaKey = (field, t) => ({ label: ",", value: ",", name: t.key_comma, field })
export const barKey = (field, t) => ({ label: "/", value: "/", name: t.key_bar, field })
