// Renders agent text with the restricted markup (markup_parser.js) into DOM nodes.
// Text goes in with createTextNode: nothing an agent writes can become HTML.
// Formulas go through KaTeX with trust: false (no \href, \url, \includegraphics).
import katex from "katex"
import { parse } from "items/markup_parser"
import { glueFormulas } from "items/formula_punct"

const OPTIONS = { trust: false, strict: "ignore", output: "htmlAndMathml" }

// \ce{} and \pu{} (D-282) are macros of KaTeX's contrib/mhchem, which only the pages that draw chemistry need. Loaded once, on the
// first formula that uses them (or by a caller that knows it will, through ensureChem()).
let chemLoading = null
export function ensureChem() {
  chemLoading ??= import("katex/mhchem").catch((error) => { chemLoading = null; throw error })
  return chemLoading
}

// Targets whose \ce formula waits for mhchem: target -> latex. A target that is drawn again meanwhile (an expression preview that
// changes) leaves the map, so the late draw never overwrites newer content.
const waiting = new WeakMap()

function draw(latex, target, throwOnError) {
  katex.render(latex, target, { ...OPTIONS, throwOnError })
}

function undefinedChem(error) {
  return error instanceof katex.ParseError && /Undefined control sequence: \\(ce|pu)\b/.test(error.message)
}

// Synchronous, like every caller: a formula that needs mhchem before it is loaded shows as plain text for the moment (never as an
// error), and is drawn once mhchem arrives. If mhchem fails to load it stays plain text.
export function renderMath(latex, target) {
  waiting.delete(target)
  try {
    try {
      draw(latex, target, true)
    } catch (error) {
      if (undefinedChem(error)) {
        target.textContent = latex
        waiting.set(target, latex)
        ensureChem().then(() => {
          if (waiting.get(target) !== latex) return
          waiting.delete(target)
          renderMath(latex, target)
        }, () => {})
        return target
      }
      draw(latex, target, false)
    }
  } catch (_error) {
    target.textContent = latex
  }
  return target
}

function inlineNodes(nodes, parent, glued = false) {
  for (const node of glued ? nodes : glueFormulas(nodes)) {
    if (node.t === "text") {
      parent.appendChild(document.createTextNode(node.v))
    } else if (node.t === "bold") {
      const strong = document.createElement("strong")
      inlineNodes(node.children, strong)
      parent.appendChild(strong)
    } else if (node.t === "nowrap") {
      // a formula with the mark next to it, kept on one line (D-335)
      const span = document.createElement("span")
      span.className = "nowrap"
      inlineNodes(node.children, span, true)
      parent.appendChild(span)
    } else if (node.t === "code") {
      const code = document.createElement("code")
      code.className = "code-span"
      code.textContent = node.v
      parent.appendChild(code)
    } else if (node.t === "lang") {
      // Italian words quoted inside target-language text (D-402): lang="it" is the voice's cue, as in a lesson's language span
      const span = document.createElement("span")
      span.className = `lang lang-${node.lang}`
      span.setAttribute("lang", node.lang)
      span.textContent = node.v
      parent.appendChild(span)
    } else if (node.t === "math") {
      const span = document.createElement("span")
      span.className = "math"
      parent.appendChild(renderMath(node.v, span))
    }
  }
}

// Blocks (paragraphs, numbered lists) as a fragment. options.lists "v2" (lessons only) also
// renders "- " lists and one nested level.
export function renderMarkup(text, options = {}) {
  const fragment = document.createDocumentFragment()
  for (const block of parse(text, options)) {
    if (options.lists === "v2" && block.type !== "p") {
      const list = document.createElement(block.type)
      if (block.start) list.setAttribute("start", String(block.start))
      for (const item of block.items) {
        const li = document.createElement("li")
        inlineNodes(item.children, li)
        if (item.sub.length > 0) {
          const nested = document.createElement("ul")
          for (const sub of item.sub) {
            const subItem = document.createElement("li")
            inlineNodes(sub, subItem)
            nested.appendChild(subItem)
          }
          li.appendChild(nested)
        }
        list.appendChild(li)
      }
      fragment.appendChild(list)
    } else if (block.type === "ol") {
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
