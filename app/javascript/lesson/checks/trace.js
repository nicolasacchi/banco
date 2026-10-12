// check component trace: reserved (w2-3, track T9). The stub of WAVE2 2.11: replace render, keep the exports.
// render(check, ctx, hooks) mounts the component and calls hooks.answer(response) when the student presses Controlla; the server
// grades it (Lessons::Checks). Until the registry says `available` a lesson cannot use it.
import { el } from "lesson/dom"

export const type = "trace"

export function render(_check, _ctx, _hooks) {
  return el("div", { class: "check-unavailable", "data-component": type, text: "trace: non ancora disponibile" })
}
