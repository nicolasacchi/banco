// image block: draft (w2-2, track T8). The stub of WAVE2 2.x: replace render, keep the export.
// Until the registry says `available` a lesson cannot use it (Lessons::Types), so this is never mounted on a stored lesson.
import { el } from "lesson/dom"

export const type = "image"

export function render(_block, _ctx) {
  return el("div", { class: "block block-unavailable", "data-type": type, text: "image: non ancora disponibile" })
}
