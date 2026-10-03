// testlet: one passage and its sub items, answered as one unit. Each sub item has
// the template of its own component and a "Non lo so" of its own. The raw answer
// is JSON text: {sub item id: that sub item's raw answer}. A sub item that was
// not answered and not given up blocks the send, so no unit goes in half done.
import { DONT_KNOW, el, handle } from "items/dom"
import { renderMarkup } from "items/markup"
import { renderPart } from "items/render"

export async function render(part, ctx) {
  const wrapper = el("div", { class: "answer testlet" })
  wrapper.appendChild(el("h2", { class: "passage-title", text: ctx.t.passage }))
  const passage = el("div", { class: "passage" })
  passage.appendChild(renderMarkup(part.passage_it || ""))
  wrapper.appendChild(passage)

  const subs = []
  for (const [index, sub] of (part.sub_items || []).entries()) {
    const handleOfSub = await renderPart(sub, ctx)
    const give_up = el("input", { type: "checkbox", class: "give-up" })
    const section = el("section", { class: "sub-item", "data-sub": sub.id },
      el("h3", { text: ctx.t.question_of.replace("%{n}", String(index + 1)) }),
      handleOfSub.promptElement,
      handleOfSub.element,
      el("label", { class: "option" }, give_up, el("span", { class: "option-text", text: ctx.t.dont_know })))
    give_up.addEventListener("change", () => section.classList.toggle("given-up", give_up.checked))
    wrapper.appendChild(section)
    subs.push({ id: sub.id, handle: handleOfSub, give_up })
  }

  const value = (entry) => (entry.give_up.checked ? DONT_KNOW : entry.handle.raw())
  return handle(wrapper, {
    raw: () => JSON.stringify(Object.fromEntries(subs.map((entry) => [entry.id, value(entry)]))),
    isEmpty: () => subs.some((entry) => !entry.give_up.checked && entry.handle.isEmpty()),
    source: "text",
    focus: () => subs[0]?.handle.focus(),
    mounted: () => subs.forEach((entry) => entry.handle.mounted())
  })
}
