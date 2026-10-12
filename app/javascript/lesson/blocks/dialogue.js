// dialogue block: reserved (w2-1, track T3). The stub of WAVE2 2.x: replace render, keep the export.
// Until the registry says `available` a lesson cannot use it (Lessons::Types), so this is never mounted on a stored lesson.
import { el } from "lesson/dom"

export const type = "dialogue"

export function render(_block, _ctx) {
  return el("div", { class: "block block-unavailable", "data-type": type, text: "dialogue: non ancora disponibile" })
}
