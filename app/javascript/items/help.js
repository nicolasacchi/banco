// "Come si risponde" (D-216): the help of the sitting page, drawn from help_sections.js. It is
// interface help: opening it is logged as an app event and never changes the evidence.
import { el } from "items/dom"
import { helpSections } from "items/help_sections"

// Draws the sections into +target+ (cleared first): a short list per section.
export function renderHelp(item, t, target) {
  target.textContent = ""
  for (const section of helpSections(item, t)) {
    if (section.heading) target.appendChild(el("h3", { class: "help-heading", text: section.heading }))
    target.appendChild(el("ul", { class: "plain help-list" }, section.lines.map((line) => el("li", { text: line }))))
  }
  return target
}
