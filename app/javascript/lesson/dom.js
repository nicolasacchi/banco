// DOM helpers of the lesson renderer. Text goes in with createTextNode / textContent: nothing an agent
// writes can become HTML. SVG is built with createElementNS and classes only.
import { el } from "items/dom"

export { el }
export const SVG_NS = "http://www.w3.org/2000/svg"
export const SPRITE = "/vendor/lucide@1.54.0/banco-sprite.svg"

export function svg(tag, attributes = {}) {
  const node = document.createElementNS(SVG_NS, tag)
  for (const [name, value] of Object.entries(attributes)) {
    if (value === false || value === null || value === undefined) continue
    if (name === "class") node.setAttribute("class", value)
    else node.setAttribute(name, String(value))
  }
  return node
}

// An icon of our sprite (A6). aria-hidden: the label next to it carries the meaning.
export function icon(name, cls = "") {
  const node = svg("svg", { class: `ic ${cls}`.trim(), "aria-hidden": "true", focusable: "false", viewBox: "0 0 24 24" })
  node.appendChild(svg("use", { href: `${SPRITE}#${name}` }))
  return node
}

export function button(text, attributes = {}, handler) {
  const b = el("button", { type: "button", ...attributes }, typeof text === "string" ? document.createTextNode(text) : text)
  if (handler) b.addEventListener("click", handler)
  return b
}

let counter = 0
export const uid = (prefix = "l") => `${prefix}-${++counter}`

export const clear = (node) => {
  while (node.firstChild) node.removeChild(node.firstChild)
  return node
}
