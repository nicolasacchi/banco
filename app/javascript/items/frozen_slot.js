import { renderItem } from "items/render"
import { refresh } from "items/translation"

// Draws one stored instance with the student's own templates into a slot, then switches it off: the teacher
// reads what S would see and nothing is posted. The slot carries the presentation as JSON in data-presentation.
// The teacher reads Italian (D-402): the slot is a translation scope that is open, so a bilingual item shows each text with its Italian under it, the
// passage's included (nobody answers here, so the reading rule does not apply: ctx.passageTranslation). A legacy item has no translation node.
export async function drawFrozen(slot, texts) {
  slot.dataset.drawn = "true"
  try {
    const handle = await renderItem(JSON.parse(slot.dataset.presentation), { t: texts, passageTranslation: true })
    slot.setAttribute("data-tr-scope", "item")
    slot.setAttribute("data-translation", "on")
    slot.appendChild(handle.element)
    handle.mounted()
    refresh(slot)
    freeze(slot)
  } catch (error) {
    slot.textContent = texts.error_generic || String(error)
  }
}

export function freeze(slot) {
  // The translation buttons are not answer controls: they stay.
  slot.querySelectorAll("input, textarea, select, button:not(.tr-toggle)").forEach((node) => { node.disabled = true })
  slot.querySelectorAll("math-field").forEach((field) => {
    field.setAttribute("read-only", "")
    field.setAttribute("disabled", "")
  })
  slot.setAttribute("aria-disabled", "true")
}
