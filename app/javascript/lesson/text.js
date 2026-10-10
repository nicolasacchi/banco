// Agent text of a lesson/2, drawn as DOM nodes: markup v2 plus colour role spans and links (A5), and formulas
// through KaTeX with the one macro \role{name}{tex} -> \htmlClass{role-name}{tex}. trust allows only that
// \htmlClass with a class "role-..." (typing \htmlClass is refused earlier, in Ruby and by the parser).
import katex from "katex"
import palette from "lesson/palette"
import { parse, Refused } from "items/markup_parser"
import { el, icon } from "lesson/dom"
import { colourTokens, displayPieces, displayTex } from "lesson/eq"

const ROLE_CLASS = /^role-[a-z]+(-[a-z]+)*$/
const NOT_EQUAL = "\\html@mathml{\\mathrel{\\text{\\char\"2260}}}{\\mathrel{\\char`≠}}"
export const KATEX = {
  throwOnError: false,
  strict: "ignore",
  output: "htmlAndMathml",
  // \neq is the character itself, drawn by our symbols font in the weight of its line (KaTeX's composed glyph is always thin)
  macros: { "\\role": "\\htmlClass{role-#1}{#2}", "\\neq": NOT_EQUAL, "\\ne": NOT_EQUAL },
  trust: (context) => context.command === "\\htmlClass" && ROLE_CLASS.test(context.class ?? "")
}

export function roleOf(subject, name) {
  return palette.subjects[subject]?.[name] ?? palette.common[name] ?? null
}

// An icon role in a formula gets its icon in front of the span, like in running text.
function decorateRoles(target, subject) {
  for (const node of target.querySelectorAll('[class*="role-"]')) {
    const name = [...node.classList].find((c) => c.startsWith("role-"))?.slice(5)
    const info = name && roleOf(subject, name)
    if (info?.carrier === "icon" && info.icon && !node.querySelector(":scope > .ic")) node.insertBefore(icon(info.icon, "role-ic"), node.firstChild)
  }
}

export function renderMath(tex, target, ctx, display = false, tiles = false) {
  try {
    // maths: the unknown and the numbers in their colours; a displayed equation also as two member tiles
    const tiled = ctx.subject === "math" && (display || tiles)
    if (display || tiles) target.classList.add("eqd")
    const pieces = tiled ? displayPieces(tex) : null
    if (pieces && pieces.length > 1) {
      // a chain of equations: one KaTeX span per equation and per arrow, so that it can break between them on a narrow screen
      target.classList.add("eq-chain")
      pieces.forEach((piece, i) => {
        if (i > 0) target.appendChild(document.createTextNode(" "))
        const span = el("span", { class: piece.arrow ? "eq-arrow" : "eq-piece" })
        katex.render(piece.arrow ?? piece.tex, span, { ...KATEX, displayMode: false })
        target.appendChild(span)
      })
    } else {
      const coloured = ctx.subject === "math" ? (tiled ? displayTex(tex) : colourTokens(tex)) : tex
      katex.render(coloured, target, { ...KATEX, displayMode: display })
    }
    decorateRoles(target, ctx.subject)
  } catch (_error) {
    target.textContent = tex
  }
  return target
}

function inlineNodes(nodes, parent, ctx, display = false, tiles = false) {
  for (const node of nodes) {
    if (node.t === "math" && display) {
      parent.appendChild(renderMath(node.v, el("span", { class: "math" }), ctx, true))
      continue
    }
    if (node.t === "text") parent.appendChild(document.createTextNode(node.v))
    else if (node.t === "bold") {
      const strong = el("strong")
      inlineNodes(node.children, strong, ctx)
      parent.appendChild(strong)
    } else if (node.t === "math") parent.appendChild(renderMath(node.v, el("span", { class: "math" }), ctx, false, tiles && /=/.test(node.v)))
    else if (node.t === "role") {
      const info = roleOf(ctx.subject, node.role)
      const span = el("span", { class: `role role-${node.role}` })
      if (info?.carrier === "icon" && info.icon) span.appendChild(icon(info.icon, "role-ic"))
      inlineNodes(node.children, span, ctx)
      parent.appendChild(span)
    } else if (node.t === "link") {
      const a = el("a", { class: "lesson-link" })
      inlineNodes(node.children, a, ctx)
      if (node.kind === "scheda") {
        a.setAttribute("href", `#scheda-${ctx.cardNumber?.(node.target) ?? ""}`)
        a.dataset.card = node.target
      } else if (ctx.unavailableTopics?.includes(node.target)) {
        parent.appendChild(el("span", { class: "unavailable" }, ...[...a.childNodes], ` (${ctx.t.topic_unavailable})`))
        continue
      } else a.setAttribute("href", `/topics/${node.target}`)
      parent.appendChild(a)
    }
  }
}

function build(blocks, fragment, ctx, tiles = false) {
  for (const block of blocks) {
    if (block.type === "p") {
      const alone = block.children.length === 1 && block.children[0].t === "math"
      const p = el("p", alone ? { class: "eq-display" } : {})
      inlineNodes(block.children, p, ctx, alone, tiles)
      fragment.appendChild(p)
    } else {
      const list = el(block.type)
      for (const item of block.items) {
        const li = el("li")
        inlineNodes(item.children, li, ctx, false, tiles)
        if (item.sub.length > 0) {
          const nested = el("ul")
          for (const sub of item.sub) {
            const subItem = el("li")
            inlineNodes(sub, subItem, ctx, false, tiles)
            nested.appendChild(subItem)
          }
          li.appendChild(nested)
        }
        list.appendChild(li)
      }
      fragment.appendChild(list)
    }
  }
}

// Blocks (paragraphs, lists) into a fragment. A text the reader refuses is shown as plain text.
export function renderRich(text, ctx, options = {}) {
  const fragment = document.createDocumentFragment()
  let blocks
  try {
    blocks = parse(text, { lists: "v2", roles: true })
  } catch (error) {
    if (!(error instanceof Refused)) throw error
    fragment.appendChild(el("p", { text: String(text) }))
    return fragment
  }
  build(blocks, fragment, ctx, !!options.tiles)
  return fragment
}

// Inline only (labels, buttons, table cells): the first paragraph's content, into `target`.
export function renderInlineRich(text, target, ctx, options = {}) {
  let blocks
  try {
    blocks = parse(text, { lists: "v2", roles: true })
  } catch (_error) {
    target.textContent = String(text)
    return target
  }
  if (blocks.length >= 1 && blocks[0].type === "p") {
    const kids = blocks[0].children
    inlineNodes(kids, target, ctx, !!options.display && kids.length === 1 && kids[0].t === "math", !!options.tiles)
  }
  else build(blocks, target, ctx, !!options.tiles)
  return target
}

export function richElement(tag, text, ctx, attributes = {}) {
  const node = el(tag, attributes)
  node.appendChild(renderRich(text, ctx))
  return node
}
