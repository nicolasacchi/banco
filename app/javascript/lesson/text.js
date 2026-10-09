// Agent text of a lesson/2, drawn as DOM nodes: markup v2 plus colour role spans and links (A5), and formulas
// through KaTeX with the one macro \role{name}{tex} -> \htmlClass{role-name}{tex}. trust allows only that
// \htmlClass with a class "role-..." (typing \htmlClass is refused earlier, in Ruby and by the parser).
import katex from "katex"
import palette from "lesson/palette"
import { parse, Refused } from "items/markup_parser"
import { el, icon } from "lesson/dom"

const ROLE_CLASS = /^role-[a-z]+(-[a-z]+)*$/
const KATEX = {
  throwOnError: false,
  strict: "ignore",
  output: "htmlAndMathml",
  macros: { "\\role": "\\htmlClass{role-#1}{#2}" },
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

export function renderMath(tex, target, ctx, display = false) {
  try {
    katex.render(tex, target, { ...KATEX, displayMode: display })
    decorateRoles(target, ctx.subject)
  } catch (_error) {
    target.textContent = tex
  }
  return target
}

function inlineNodes(nodes, parent, ctx) {
  for (const node of nodes) {
    if (node.t === "text") parent.appendChild(document.createTextNode(node.v))
    else if (node.t === "bold") {
      const strong = el("strong")
      inlineNodes(node.children, strong, ctx)
      parent.appendChild(strong)
    } else if (node.t === "math") parent.appendChild(renderMath(node.v, el("span", { class: "math" }), ctx))
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

function build(blocks, fragment, ctx) {
  for (const block of blocks) {
    if (block.type === "p") {
      const p = el("p")
      inlineNodes(block.children, p, ctx)
      fragment.appendChild(p)
    } else {
      const list = el(block.type)
      for (const item of block.items) {
        const li = el("li")
        inlineNodes(item.children, li, ctx)
        if (item.sub.length > 0) {
          const nested = el("ul")
          for (const sub of item.sub) {
            const subItem = el("li")
            inlineNodes(sub, subItem, ctx)
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
export function renderRich(text, ctx) {
  const fragment = document.createDocumentFragment()
  let blocks
  try {
    blocks = parse(text, { lists: "v2", roles: true })
  } catch (error) {
    if (!(error instanceof Refused)) throw error
    fragment.appendChild(el("p", { text: String(text) }))
    return fragment
  }
  build(blocks, fragment, ctx)
  return fragment
}

// Inline only (labels, buttons, table cells): the first paragraph's content, into `target`.
export function renderInlineRich(text, target, ctx) {
  let blocks
  try {
    blocks = parse(text, { lists: "v2", roles: true })
  } catch (_error) {
    target.textContent = String(text)
    return target
  }
  if (blocks.length >= 1 && blocks[0].type === "p") inlineNodes(blocks[0].children, target, ctx)
  else build(blocks, target, ctx)
  return target
}

export function richElement(tag, text, ctx, attributes = {}) {
  const node = el(tag, attributes)
  node.appendChild(renderRich(text, ctx))
  return node
}
