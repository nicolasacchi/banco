// testlet: one passage and its sub items, answered as one unit. Each sub item has
// the template of its own component and a "Non lo so" of its own. The raw answer
// is JSON text: {sub item id: that sub item's raw answer}. A sub item that was
// not answered and not given up blocks the send, so no unit goes in half done.
import { DONT_KNOW, announceChange, el, handle, parseDraft } from "items/dom"
import { renderMarkup } from "items/markup"
import { renderPart } from "items/render"

function clearMark(section) {
  section.classList.remove("missing")
  section.removeAttribute("aria-invalid")
}

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
    const section = el("section", { class: "sub-item", "data-sub": sub.id, "data-comment-anchor": `part:${index + 1}` },
      el("h3", { text: ctx.t.question_of.replace("%{n}", String(index + 1)) }),
      handleOfSub.promptElement,
      handleOfSub.element,
      el("label", { class: "option" }, give_up, el("span", { class: "option-text", text: ctx.t.dont_know })))
    give_up.addEventListener("change", () => {
      section.classList.toggle("given-up", give_up.checked)
      clearMark(section)
      announceChange(wrapper)
    })
    // The sub item's own item-change bubbles up to here and on to the page: a part that was marked missing is answered now.
    section.addEventListener("item-change", () => clearMark(section))
    wrapper.appendChild(section)
    subs.push({ id: sub.id, handle: handleOfSub, give_up, section })
  }

  const draftOf = (entry) => ({ d: entry.handle.draft(), g: entry.give_up.checked })
  const value = (entry) => (entry.give_up.checked ? DONT_KNOW : entry.handle.raw())
  return handle(wrapper, {
    raw: () => JSON.stringify(Object.fromEntries(subs.map((entry) => [entry.id, value(entry)]))),
    isEmpty: () => subs.some((entry) => !entry.give_up.checked && entry.handle.isEmpty()),
    source: "text",
    focus: () => subs[0]?.handle.focus(),
    // Marks what is missing: the sub items that show their own empty rows (matching), else the section of a part with no answer and no
    // "Non lo so". The first mark is scrolled into view and focused. Returns how many parts are marked.
    showMissing: (focusFirst = true) => {
      let marked = 0
      for (const entry of subs) {
        if (entry.give_up.checked) continue
        const focusIt = focusFirst && marked === 0
        if (entry.handle.showMissing) {
          if (entry.handle.showMissing(focusIt) > 0) marked += 1
        } else if (entry.handle.isEmpty()) {
          entry.section.classList.add("missing")
          entry.section.dataset.missing = ctx.t.missing
          entry.section.setAttribute("aria-invalid", "true")
          marked += 1
          if (focusIt) {
            entry.section.scrollIntoView?.({ block: "center" })
            entry.handle.focus()
          }
        }
      }
      return marked
    },
    // A JSON of the parts' drafts: {sub item id: {"d": that part's draft, "g": true when "Non lo so" is ticked}}; "" when nothing is set.
    draft: () => {
      const all = subs.map((entry) => [entry.id, draftOf(entry)])
      return all.every(([, part]) => part.d === "" && !part.g) ? "" : JSON.stringify(Object.fromEntries(all))
    },
    restore: (draft) => {
      const parts = parseDraft(draft)
      if (!parts) return
      for (const entry of subs) {
        const part = parts[entry.id]
        if (part === null || typeof part !== "object") continue
        if (typeof part.d === "string") entry.handle.restore(part.d)
        entry.give_up.checked = part.g === true
        entry.section.classList.toggle("given-up", entry.give_up.checked)
      }
    },
    mounted: () => subs.forEach((entry) => entry.handle.mounted())
  })
}
