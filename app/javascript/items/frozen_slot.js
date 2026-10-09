import { renderItem } from "items/render"

// Draws one stored instance with the student's own templates into a slot, then switches it off: the teacher
// reads what S would see and nothing is posted. The slot carries the presentation as JSON in data-presentation.
export async function drawFrozen(slot, texts) {
  slot.dataset.drawn = "true"
  try {
    const handle = await renderItem(JSON.parse(slot.dataset.presentation), { t: texts })
    slot.appendChild(handle.element)
    handle.mounted()
    freeze(slot)
  } catch (error) {
    slot.textContent = texts.error_generic || String(error)
  }
}

export function freeze(slot) {
  slot.querySelectorAll("input, textarea, select, button").forEach((node) => { node.disabled = true })
  slot.querySelectorAll("math-field").forEach((field) => {
    field.setAttribute("read-only", "")
    field.setAttribute("disabled", "")
  })
  slot.setAttribute("aria-disabled", "true")
}
