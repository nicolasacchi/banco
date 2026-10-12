// check component ordering: reserved (w2-1, track T1). The stub of WAVE2 2.11: replace render, keep the exports.
// render(check, ctx, hooks) mounts the component and calls hooks.answer(response) when the student presses Controlla; the server
// grades it (Lessons::Checks). Until the registry says `available` a lesson cannot use it.
import { el } from "lesson/dom"

export const type = "ordering"

export function render(_check, _ctx, _hooks) {
  return el("div", { class: "check-unavailable", "data-component": type, text: "ordering: non ancora disponibile" })
}
