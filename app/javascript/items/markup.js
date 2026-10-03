// Renders agent text with the restricted markup (markup_parser.js) into DOM nodes.
// Text goes in with createTextNode: nothing an agent writes can become HTML.
// Formulas go through KaTeX with trust: false (no \href, \url, \includegraphics).
import katex from "katex"
import { parse } from "items/markup_parser"

export function renderMath(latex, target) {
  try {
    katex.render(latex, target, { trust: false, throwOnError: false, strict: "ignore", output: "htmlAndMathml" })
  } catch (_error) {
    target.textContent = latex
  }
  return target
}

function inlineNodes(nodes, parent) {
  for (const node of nodes) {
    if (node.t === "text") {
      parent.appendChild(document.createTextNode(node.v))
    } else if (node.t === "bold") {
      const strong = document.createElement("strong")
      inlineNodes(node.children, strong)
      parent.appendChild(strong)
    } else if (node.t === "math") {
      const span = document.createElement("span")
      span.className = "math"
      parent.appendChild(renderMath(node.v, span))
    }
  }
}

// Blocks (paragraphs, numbered lists) as a fragment.
export function renderMarkup(text) {
  const fragment = document.createDocumentFragment()
  for (const block of parse(text)) {
    if (block.type === "ol") {
      const ol = document.createElement("ol")
      for (const item of block.items) {
        const li = document.createElement("li")
        inlineNodes(item, li)
        ol.appendChild(li)
      }
      fragment.appendChild(ol)
    } else {
      const p = document.createElement("p")
      inlineNodes(block.children, p)
      fragment.appendChild(p)
    }
  }
  return fragment
}

// Inline only, into an existing element (labels, table cells, options): the first
// paragraph's inline content, further blocks appended after it.
export function renderInline(text, target) {
  const blocks = parse(text)
  if (blocks.length === 1 && blocks[0].type === "p") {
    inlineNodes(blocks[0].children, target)
  } else {
    target.appendChild(renderMarkup(text))
  }
  return target
}
