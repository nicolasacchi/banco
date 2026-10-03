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

// An answer from an item template: raw (the text posted), source (the input
// channel), isEmpty() (nothing entered yet), focus(), and mounted(), which the page
// calls once the element is in the document (a MathLive field can only be set up
// then).
export function handle(element, { raw, isEmpty, source = "text", focus = () => {}, mounted = () => {} }) {
  return { element, raw, isEmpty, source: () => (typeof source === "function" ? source() : source), focus, mounted }
}
