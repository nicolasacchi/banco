// Small DOM helpers shared by the item templates. Text always goes in as text.

export function el(tag, attributes = {}, ...children) {
  const node = document.createElement(tag)
  for (const [name, value] of Object.entries(attributes)) {
    if (value === false || value === null || value === undefined) continue
    if (name === "class") node.className = value
    else if (name === "text") node.textContent = value
    else node.setAttribute(name, value === true ? "" : String(value))
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false) continue
    node.appendChild(typeof child === "string" ? document.createTextNode(child) : child)
  }
  return node
}

let counter = 0
export function uid(prefix = "f") {
  counter += 1
  return `${prefix}${counter}`
}

// The raw answer of "Non lo so" and "Non l'ho ancora studiato" (decision D-030).
export const DONT_KNOW = '{"dont_know":true}'

// The student changed the answer of an item (typing, a choice, a move): a bubbling event from the template's element, which the
// page listens for to save the half-typed answer. A restore is silent (it never calls this).
export function announceChange(element) {
  element.dispatchEvent(new CustomEvent("item-change", { bubbles: true }))
}

// A draft that is a JSON object ({...}), else null: a restore ignores anything else.
export function parseDraft(text) {
  if (typeof text !== "string") return null
  try {
    const value = JSON.parse(text)
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null
  } catch {
    return null
  }
}

// An answer from an item template: raw (the text posted), source (the input
// channel), isEmpty() (nothing entered yet), focus(), and mounted(), which the page
// calls once the element is in the document (a MathLive field can only be set up
// then). draft() is the PARTIAL answer as text ("" when nothing is typed or chosen), restore(draft) puts it back and ignores,
// without throwing, a draft that is broken or not of this item (the half-typed answer of an exercise left open, practice/2).
// showMissing() is only on a component that can be answered in part (matching, testlet): it marks what is left empty, scrolls to the first
// and focuses it; callers use handle.showMissing?.().
export function handle(element, { raw, isEmpty, source = "text", focus = () => {}, mounted = () => {}, draft = () => "", restore = () => {}, showMissing }) {
  const result = { element, raw, isEmpty, source: () => (typeof source === "function" ? source() : source), focus, mounted, draft, restore }
  if (showMissing) result.showMissing = showMissing
  return result
}
