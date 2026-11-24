// Agent text of a lesson/2, drawn as DOM nodes: markup v2 plus colour role spans and links (A5), and formulas
// through KaTeX with the one macro \role{name}{tex} -> \htmlClass{role-name}{tex}. trust allows only that
// \htmlClass with a class "role-..." (typing \htmlClass is refused earlier, in Ruby and by the parser).
import katex from "katex"
import palette from "lesson/palette"
import { parse, Refused } from "items/markup_parser"
import { glueFormulas } from "items/formula_punct"
import { el, icon } from "lesson/dom"
import { colourTokens, displayPieces, displayTex } from "lesson/eq"
import { speakerButton } from "lesson/speech_ui"
import { italianOf, targetOf } from "lesson/lang"
import { node as translationNode } from "items/translation"
import { plain } from "lesson/diagrams/common"
import { parsedText } from "lesson/raw_markup"

const ROLE_CLASS = /^role-[a-z]+([_-][a-z]+)*$/
const NOT_EQUAL = "\\html@mathml{\\mathrel{\\text{\\char\"2260}}}{\\mathrel{\\char`≠}}"
export const KATEX = {
  throwOnError: false,
  strict: "ignore",
  output: "htmlAndMathml",
  // \neq is the character itself, drawn by our symbols font in the weight of its line (KaTeX's composed glyph is always thin)
  macros: { "\\role": "\\htmlClass{role-#1}{#2}", "\\neq": NOT_EQUAL, "\\ne": NOT_EQUAL },
  trust: (context) => context.command === "\\htmlClass" && ROLE_CLASS.test(context.class ?? "")
}

// Text that a diagram lays out (a label, a node, an edge label, what the layout measures): the formula and its mark are not glued, since a
// span.nowrap changes the width a label is measured and wrapped at, and the layout then finds labels that overlap (D-335).
export const unglued = (ctx) => (ctx.noGlue ? ctx : { ...ctx, noGlue: true })

// Text inside a control (a choice option, a chip, a tile, a table's stacked label): the same inline markup as running text (formulas in their
// colours, roles, language spans, bold), with nothing that is itself a control: no speaker button, no glossary bubble, no link. A button or a
// link inside a <label> would take the tap meant for the option (D-310).
export const insideControl = (ctx) => ({ ...ctx, noSpeech: true, glossary: null, noLinks: true })

// A control that is a button (a tile, a chip that is a button, a map item, a <summary>): the same, and it draws no translation, because a
// translation is never inside a <button> (D-402). What it says is covered by the prompt's translation or is a fragment.
export const inButton = (ctx) => ({ ...insideControl(ctx), noTr: true })

// A place that was never a control but sits inside one (the front of a flip card, an option that is a button): its text draws no translation in a
// bilingual lesson, and a legacy lesson draws it exactly as it did.
export const noTranslation = (ctx) => (ctx.lang ? { ...ctx, noTr: true } : ctx)

// ---- the Italian of a bilingual lesson (D-402) ----
// A served bilingual lesson holds the TARGET text in every `_it` slot and the Italian in `tr` tables {target string: Italian}, one on the body, one on
// each card and one on each block (Lessons::Bilingual.fold). `ctx.lang` is the page's language ("en", "es"; none in a legacy lesson, which is drawn
// as it always was) and `ctx.trScopes` the objects whose `tr` a text is looked up in, the block first, then the card, then the body.

// A copy of ctx for one scope (a block, a card, a check's reply): the same members, getters kept, its tables in front of the others. Its `rich` is its own.
export function scoped(ctx, ...tables) {
  const next = Object.defineProperties({}, Object.getOwnPropertyDescriptors(ctx))
  const define = (name, value) => Object.defineProperty(next, name, { value, enumerable: true, writable: true, configurable: true })
  define("trScopes", [...tables.filter(Boolean), ...(ctx.trScopes ?? [])])
  define("rich", (text) => el("div", { class: "rich" }, renderRich(text, next)))
  return next
}

// The Italian of a text in this ctx, or null (a legacy lesson, a place that draws none, a string no table has: one that code built).
export const translationOf = (text, ctx) => (ctx.lang && !ctx.noTr && ctx.trScopes ? italianOf(text, ...ctx.trScopes) : null)

// The ctx the Italian is drawn with: no lookup, no language of the target (its role spans are Italian, its spans keep their speaker).
const italianCtx = (ctx) => ({ ...ctx, lang: null, noTr: true, translating: true })

// A translation node holding `italian` in `ctx`, or null when the place draws none (a legacy lesson, a button, an empty text): `block` draws paragraphs and
// lists (a div), else the inline content (a span), both `.tr`. The cell of a table brings its Italian with it (header_it, rows_it), so it is drawn from here.
export function translationWith(italian, ctx, { block = false, tag = block ? "div" : "span" } = {}) {
  if (!ctx.lang || ctx.noTr || typeof italian !== "string" || italian.trim() === "") return null
  const holder = translationNode(null, { tag })
  const inner = italianCtx(ctx)
  if (block) holder.appendChild(renderRich(italian, inner))
  else renderInlineRich(italian, holder, inner)
  return holder
}

// A translation node for `text` in `ctx` (its Italian looked up in the tables of the scopes), or null.
export function translationFor(text, ctx, options = {}) {
  const italian = translationOf(text, ctx)
  return italian === null ? null : translationWith(italian, ctx, options)
}

// Says what a drawn node is: target text (`lang`), with its translation (`data-translated`), or text that draws none on purpose (`data-tr-exempt`:
// the render check does not ask for one). A node that already has a language (a gloss, a line of a dialogue) is its own business.
function markTarget(node, ctx, translated) {
  if (!ctx.lang || node.getAttribute("lang")) return
  node.setAttribute("lang", ctx.lang)
  if (translated) node.setAttribute("data-translated", "")
  else if (ctx.noTr) node.setAttribute("data-tr-exempt", "")
}

// A plain text element (a hint line, a title drawn as text) with its translation beside it: the node, or a fragment of the node and its `.tr`.
export function beside(node, text, ctx, { tag = "p" } = {}) {
  const translation = translationFor(text, ctx, { tag })
  markTarget(node, ctx, translation !== null)
  if (!translation) return node
  const fragment = document.createDocumentFragment()
  fragment.append(node, translation)
  return fragment
}

// A language span of one short word ("-emos", "hablar") never breaks, not even at its hyphen; a phrase wraps as text does (D-310).
export const ONE_WORD_MAX = 24
export const oneWord = (text) => !/\s/.test(String(text).trim()) && String(text).trim().length <= ONE_WORD_MAX

// The words of an inline text with its markup taken away (a span's words, a role's text, a link's text, bold as its words, a formula as
// diagrams/common's plain() reads it: "$a^2 \cdot b$" is "a^2 · b"), for what is said and never drawn: a button's or a region's name, a
// screen reader's line (D-310). The same reader as the page's, so a role with a hyphen or "|it" loses its brackets too. A text the reader
// refuses is returned as written. Pure.
export function plainText(text) {
  let blocks
  try {
    blocks = parse(String(text ?? ""), { lists: "v2", roles: true })
  } catch (error) {
    if (!(error instanceof Refused)) throw error
    return String(text ?? "")
  }
  const words = (nodes) => nodes.map((node) => {
    if (node.t === "text") return node.v
    if (node.t === "math") return plain(node.v)
    if (node.t === "lang" || node.t === "code") return node.v
    if (node.t === "gloss") return node.term
    return node.children ? words(node.children) : ""
  }).join("")
  return blocks.map((block) => (block.type === "p" ? words(block.children) : block.items.map((item) => words(item.children)).join(" "))).join(" ")
}

// A card title up to its first colon followed by a space ("Esempio A: ..." -> "Esempio A"), never a colon inside a formula. Pure.
export function shortTitle(title) {
  const s = String(title ?? "")
  let math = false
  for (let i = 0; i < s.length - 1; i++) {
    if (s[i] === "\\") i += 1
    else if (s[i] === "$") math = !math
    else if (!math && s[i] === ":" && /\s/.test(s[i + 1])) return s.slice(0, i)
  }
  return s
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

// The bubble opens under its word and stays inside the card: as wide as the card allows (22rem at most), slid left when it would leave it.
function place(button, pop) {
  const box = pop.closest(".card-body, .l2-card") ?? document.documentElement
  const bounds = box.getBoundingClientRect()
  const anchor = pop.parentElement.getBoundingClientRect()
  const width = Math.min(bounds.width - 16, 22 * (parseFloat(getComputedStyle(pop).fontSize) || 20))
  pop.style.width = `${width}px`
  pop.style.maxWidth = `${width}px`
  const left = Math.max(bounds.left + 8, Math.min(anchor.left, bounds.right - 8 - width))
  pop.style.left = `${left - anchor.left}px`
}

// A glossary word: the word, a small book icon that is the button (a padded hit area), and the definition that opens under it (D-266). The
// definition is hidden until asked for, so the voice reads it only after the student opened it (L10); the card lists its words anyway.
function glossWord(term, ctx) {
  const entry = ctx.glossary?.get(term.toLowerCase())
  const word = el("span", { class: "gloss-word", text: term })
  if (!entry) return word
  const t = ctx.t.gloss
  const pop = el("span", { class: "gloss-pop", role: "note", hidden: "" })
  const inner = { ...ctx, glossary: null } // a word inside a definition is only a word: no glossary inside the glossary
  // inside a translation the word is the Italian term and its bubble holds the Italian definition
  const said = (text) => (ctx.translating ? italianOf(text, ...(ctx.trScopes ?? [])) ?? text : text)
  renderInlineRich(said(entry.def_it), pop.appendChild(el("span", { class: "gloss-def" })), inner)
  if (entry.example_it) renderInlineRich(said(entry.example_it), pop.appendChild(el("span", { class: "gloss-example" })), inner)
  const button = el("button", { type: "button", class: "gloss-btn", "aria-expanded": "false", "aria-label": `${t.what} ${term}?` }, icon("glossary", "gloss-ic"))
  const close = () => {
    pop.hidden = true
    button.setAttribute("aria-expanded", "false")
    document.removeEventListener("pointerdown", outside, true)
    document.removeEventListener("keydown", escape, true)
  }
  const outside = (event) => { if (!pop.contains(event.target) && event.target !== button && !button.contains(event.target)) close() }
  const escape = (event) => { if (event.key === "Escape") { close(); button.focus() } }
  button.addEventListener("click", () => {
    if (!pop.hidden) { close(); return }
    pop.hidden = false
    button.setAttribute("aria-expanded", "true")
    place(button, pop)
    document.addEventListener("pointerdown", outside, true)
    document.addEventListener("keydown", escape, true)
  })
  return el("span", { class: "gloss" }, word, button, pop)
}

function inlineNodes(nodes, parent, ctx, display = false, tiles = false, glued = false) {
  for (const node of display || glued || ctx.noGlue ? nodes : glueFormulas(nodes)) {
    if (node.t === "math" && display) {
      parent.appendChild(renderMath(node.v, el("span", { class: "math" }), ctx, true))
      continue
    }
    if (node.t === "text") {
      const text = document.createTextNode(node.v)
      parsedText.add(text)
      parent.appendChild(text)
    } else if (node.t === "bold") {
      const strong = el("strong")
      inlineNodes(node.children, strong, ctx)
      parent.appendChild(strong)
    } else if (node.t === "nowrap") {
      // a formula with the mark next to it, kept on one line (D-335); the voice reads the words it had
      const span = el("span", { class: "nowrap" })
      inlineNodes(node.children, span, ctx, false, tiles, true)
      parent.appendChild(span)
    } else if (node.t === "math") parent.appendChild(renderMath(node.v, el("span", { class: "math" }), ctx, false, tiles && /=/.test(node.v)))
    else if (node.t === "lang") {
      // [[en:..]] [[es:..]] [[la:..]]: words of another language, in the target ink, with a speaker where the device has a voice (D-266)
      const span = el("span", { class: `lang lang-${node.lang}${oneWord(node.v) ? " lang-word" : ""}`, lang: node.lang, text: node.v })
      parent.appendChild(span)
      // in a bilingual lesson the target text is read by the card's «Ascolta», and a speaker on every span would put one on every word (D-402)
      if (!ctx.safe && node.lang !== "la" && !ctx.noSpeech && !(ctx.lang && node.lang === ctx.lang)) parent.appendChild(speakerButton(ctx, { lang: node.lang, text: node.v, node: span }))
    } else if (node.t === "code") {
      parent.appendChild(el("code", { class: "code-span", text: node.v }))
    } else if (node.t === "gloss") {
      parent.appendChild(glossWord(node.term, ctx))
    } else if (node.t === "role") {
      const info = roleOf(ctx.subject, node.role)
      const span = el("span", { class: `role role-${node.role}${node.lang && node.lang !== "it" ? ` lang lang-${node.lang}` : ""}` })
      if (node.lang) span.setAttribute("lang", node.lang)
      if (info?.carrier === "icon" && info.icon) span.appendChild(icon(info.icon, "role-ic"))
      inlineNodes(node.children, span, ctx)
      parent.appendChild(span)
    } else if (node.t === "link" && (ctx.noLinks || (ctx.noCardLinks && node.kind === "scheda"))) {
      const span = el("span")
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
      } else a.setAttribute("href", ctx.topicHref(node.target))
      parent.appendChild(a)
    }
  }
}

function build(blocks, fragment, ctx, tiles = false, top = null) {
  for (const block of blocks) {
    if (block.type === "p") {
      const alone = block.children.length === 1 && block.children[0].t === "math"
      const p = el("p", alone ? { class: "eq-display" } : {})
      inlineNodes(block.children, p, ctx, alone, tiles)
      fragment.appendChild(p)
      top?.push(p)
    } else {
      const list = el(block.type)
      if (block.start) list.setAttribute("start", String(block.start))
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
      top?.push(list)
    }
  }
}

// Blocks (paragraphs, lists) into a fragment. A text the reader refuses is shown as plain text.
// In a bilingual lesson (ctx.lang) each paragraph and list is target text, and the Italian of the whole text follows it as one `.tr` (D-402).
export function renderRich(text, ctx, options = {}) {
  const fragment = document.createDocumentFragment()
  const top = []
  let blocks
  try {
    blocks = parse(text, { lists: "v2", roles: true, target: ctx.translating ? null : targetOf(ctx.subject) })
  } catch (error) {
    if (!(error instanceof Refused)) throw error
    const p = el("p", { text: String(text) })
    fragment.appendChild(p)
    top.push(p)
    blocks = null
  }
  if (blocks) build(blocks, fragment, ctx, !!options.tiles, top)
  const translation = translationFor(text, ctx, { block: true })
  for (const node of top) markTarget(node, ctx, translation !== null)
  if (translation) fragment.appendChild(translation)
  return fragment
}

// Inline only (labels, buttons, table cells): the first paragraph's content, into `target`. In a bilingual lesson `target` is target text and its
// translation is a `span.tr` at its end, unless ctx says the place draws none (a button, a fragment: ctx.noTr). `options.italian` is the Italian of a text
// that brings it along (a table cell: header_it, rows_it); without it the Italian is looked up in the scopes' `tr` tables.
export function renderInlineRich(text, target, ctx, options = {}) {
  let blocks = null
  try {
    blocks = parse(text, { lists: "v2", roles: true, target: ctx.translating ? null : targetOf(ctx.subject) })
  } catch (_error) {
    target.textContent = String(text)
  }
  if (blocks) {
    if (blocks.length >= 1 && blocks[0].type === "p") {
      const kids = blocks[0].children
      inlineNodes(kids, target, ctx, !!options.display && kids.length === 1 && kids[0].t === "math", !!options.tiles)
    }
    else build(blocks, target, ctx, !!options.tiles)
  }
  const translation = options.italian !== undefined ? translationWith(options.italian, ctx) : translationFor(text, ctx)
  markTarget(target, ctx, translation !== null)
  if (translation) target.appendChild(translation)
  return target
}

export function richElement(tag, text, ctx, attributes = {}) {
  const node = el(tag, attributes)
  node.appendChild(renderRich(text, ctx))
  return node
}
