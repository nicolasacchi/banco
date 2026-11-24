// One card (A3, A10): the header band with the icon and title, the roles legend when the card uses roles,
// then the blocks. Returns the element; the diagrams of the card are mounted by ctx.mounts afterwards.
import { el, icon } from "lesson/dom"
import { renderCheck } from "lesson/blocks/check"
import { render as callout } from "lesson/blocks/callout"
import { render as code } from "lesson/blocks/code"
import { render as cases } from "lesson/blocks/cases"
import { render as diagram } from "lesson/blocks/diagram"
import { render as example } from "lesson/blocks/example"
import { render as legend, sample } from "lesson/blocks/legend"
import { render as math } from "lesson/blocks/math"
import { render as mistake } from "lesson/blocks/mistake"
import { render as dialogue } from "lesson/blocks/dialogue"
import { render as oral } from "lesson/blocks/oral"
import { render as freePage } from "lesson/blocks/page"
import { render as reveal } from "lesson/blocks/reveal"
import { render as source } from "lesson/blocks/source"
import { render as more } from "lesson/blocks/more"
import { render as procedure } from "lesson/blocks/procedure"
import { render as summary } from "lesson/blocks/summary"
import { render as table } from "lesson/blocks/table"
import { render as text } from "lesson/blocks/text"
import { render as tryBlock } from "lesson/blocks/try"
import { questionControl } from "lesson/question"
import { equationTex } from "lesson/diagrams/balance"
import { inButton, insideControl, roleOf, renderInlineRich, scoped, translationFor } from "lesson/text"
import { cardListen } from "lesson/speech_ui"
import { refresh, toggleButton, unitLabel } from "items/translation"

// The names that [[name:..]] reserves for spans of their own (D-266): never colour roles.
const RESERVED_SPANS = ["en", "es", "it", "la", "code", "g"]

const DEFAULT_ICON = { idea: "lightbulb", example: "pencil-ruler", mistakes: "triangle-alert", try: "notebook-pen", summary: "list-checks" }

// The colour roles that a card's running text uses ([[role:..]] and \role{..}{..}), in first-use order.
export function rolesUsed(card) {
  const found = []
  const scan = (value) => {
    if (typeof value === "string") {
      for (const m of value.matchAll(/\[\[([a-z]+(?:[_-][a-z]+)*)(?:\|it)?:|\\role\{([a-z]+(?:-[a-z]+)*)\}/g)) {
        const name = m[1] ?? m[2]
        if (!RESERVED_SPANS.includes(name) && !found.includes(name)) found.push(name)
      }
    } else if (Array.isArray(value)) value.forEach(scan)
    else if (value && typeof value === "object") Object.entries(value).forEach(([k, v]) => k !== "diagram" && k !== "schema" && scan(v))
  }
  scan(card.blocks)
  return found
}

// The glossary words a card uses ([[g:term]]), once each, in the order of first use.
export function glossTerms(card) {
  const found = []
  const scan = (value) => {
    if (typeof value === "string") {
      for (const m of value.matchAll(/\[\[g:([^\]]+?)\]\]/g)) if (!found.some((t) => t.toLowerCase() === m[1].trim().toLowerCase())) found.push(m[1].trim())
    } else if (Array.isArray(value)) value.forEach(scan)
    else if (value && typeof value === "object") Object.values(value).forEach(scan)
  }
  scan(card.blocks)
  return found
}

// "Parole di questa scheda": the card's glossary words, one line each, always shown (a student who mis-taps a word still finds its meaning).
export function glossaryList(card, ctx) {
  const entries = glossTerms(card).map((t) => ctx.glossary?.get(t.toLowerCase())).filter(Boolean)
  if (entries.length === 0) return null
  const id = `scheda-${card.n}-words`
  const list = el("dl", { class: "card-glossary-list" })
  const inner = { ...ctx, glossary: null }
  for (const e of entries) {
    const dd = el("dd", {}, renderInlineRich(e.def_it, el("span", { class: "glossary-def" }), inner))
    if (e.example_it) dd.append(document.createTextNode(" "), renderInlineRich(e.example_it, el("span", { class: "glossary-example" }), inner))
    // a bilingual lesson's term has its translation under it, like any text (D-402); a legacy one is the term as written
    list.append(ctx.lang ? renderInlineRich(e.term_it, el("dt"), inner) : el("dt", { text: e.term_it }), dd)
  }
  return el("aside", { class: "card-glossary", "aria-labelledby": id }, el("h3", { id, text: ctx.t.gloss.card_title }), list)
}

export const iconOf = (card) => card.icon || DEFAULT_ICON[card.role] || "lightbulb"

const VISUAL = new Set(["diagram", "schema"])

// The picture comes first and is the card's main thing: a callout written before it moves to just after it.
export function visualFirst(blocks) {
  const first = blocks.findIndex((b) => VISUAL.has(b.type))
  if (first <= 0) return blocks
  const lead = blocks.slice(0, first)
  if (!lead.every((b) => b.type === "callout")) return blocks
  return [blocks[first], ...lead, ...blocks.slice(first + 1)]
}

// A card of exactly one text block and one figure draws the figure first (lesson.css: .card-body.is-split > .block-diagram { order: -1 }),
// at every width, whatever the order written; the brief tells the author to write the text so that it reads after the picture.
export function isSplit(blocks) {
  const types = blocks.map((b) => b.type)
  return types.length === 2 && types.includes("text") && types.some((t) => VISUAL.has(t))
}

// A chain of equations that starts from the equation the balance above it already shows does not say it twice: the
// balance is its first line (the chain keeps at least two lines).
export function dropRepeatedStart(blocks) {
  const norm = (t) => String(t).replace(/\s+/g, "")
  return blocks.map((b, i) => {
    if (b.type !== "math" || !Array.isArray(b.lines) || b.lines.length < 3 || b.lines[0].note_it) return b
    const balance = blocks.slice(0, i).reverse().find((x) => x.type === "diagram" && x.diagram?.type === "balance")
    if (!balance || norm(equationTex(balance.diagram, 0)) !== norm(b.lines[0].tex)) return b
    return { ...b, lines: b.lines.slice(1) }
  })
}

export function renderCard(card, ctx, position) {
  const article = el("article", {
    class: `l2-card card-${card.role} card-${card.level}${card.tone ? ` card-tone-${card.tone}` : ""}`,
    id: `scheda-${card.n}`, "data-comment-anchor": `card:${card.n}`, "data-n": card.n, "data-role": card.role, "data-card": card.id, "aria-labelledby": `scheda-${card.n}-title`
  })
  // a title may hold a formula (the parser accepts $...$ in a heading) or a word of another language: drawn, never printed as written (D-310)
  // in a bilingual lesson the card is a translation scope, and its title's translation sits under the heading, not in it (the heading names the card)
  const cardCtx = ctx.lang ? scoped(ctx, card) : ctx
  if (ctx.lang) {
    article.setAttribute("data-tr-scope", "card")
    article.setAttribute("data-tr-card", String(card.n))
  }
  const heading = renderInlineRich(card.title_it, el("h2", { id: `scheda-${card.n}-title`, tabindex: "-1" }), { ...insideControl(cardCtx), noTr: true })
  const titleTr = ctx.lang ? translationFor(card.title_it, cardCtx, { tag: "p" }) : null
  if (titleTr) {
    heading.removeAttribute("data-tr-exempt")
    heading.setAttribute("data-translated", "")
  }
  const head = el("header", { class: "card-head" },
    el("span", { class: "badge", "aria-hidden": "true" }, icon(iconOf(card), "badge-ic")),
    el("div", { class: "card-titles" }, position.kicker ? el("p", { class: "kicker", "data-nospeech": "", text: position.kicker }) : null, heading, titleTr),
    ctx.safe || ctx.noSpeech ? null : cardListen(article, ctx))
  article.appendChild(head)
  // a legend chip only on the first card where a role appears (the lesson map has them all); it sits below the card, not above the picture
  const roles = position.newRoles ?? rolesUsed(card)
  const hasLegend = card.blocks.some((b) => b.type === "legend")
  const body = el("div", { class: "card-body" })
  if (isSplit(card.blocks)) body.classList.add("is-split")
  const renderBlock = (block) => anchored(renderOne(block, card, ctx, renderBlock), block)
  const blockCtx = (block) => (ctx.lang ? scoped(ctx, block, card) : ctx)
  let grid = null
  let group
  for (const block of dropRepeatedStart(visualFirst(card.blocks))) {
    if (block.type === "mistake") {
      if (!grid) {
        const [pre, post] = ctx.t.mistakes_intro.split("%{tap}")
        body.appendChild(el("p", { class: "mistakes-intro" }, document.createTextNode(pre), el("strong", { text: ctx.t.mistakes_tap }), document.createTextNode(post ?? "")))
        grid = el("div", { class: "mistakes-grid" })
        body.appendChild(grid)
        group = undefined
      }
      // the mistakes of one group sit under one heading: repeated kinds read as a set
      if (block.group_it && block.group_it !== group) {
        // one span in the heading (a flex box): words, a formula and a word of another language wrap as one line of text (D-310)
        grid.appendChild(el("h3", { class: "mistakes-group" }, renderInlineRich(block.group_it, el("span", { class: "mistakes-group-title" }), insideControl(blockCtx(block)))))
        group = block.group_it
      }
      grid.appendChild(anchored(mistake(block, blockCtx(block), { group: block.group_it }), block))
      continue
    }
    grid = null
    body.appendChild(renderBlock(block))
  }
  if (roles.length > 0 && !hasLegend) {
    const line = el("p", { class: "card-legend", "data-nospeech": "", "aria-label": ctx.t.legend_label }, el("span", { class: "legend-intro", text: `${ctx.t.legend_label}: ` }))
    roles.forEach((r) => line.appendChild(sample(r, ctx)))
    body.appendChild(line)
  }
  article.appendChild(body)
  const words = ctx.safe ? null : glossaryList(card, cardCtx)
  if (words) article.appendChild(words)
  if (card.n !== undefined && card.role !== "try") {
    const q = questionControl(ctx, { section: card.role, card: card.n })
    if (q) article.appendChild(el("footer", { class: "card-foot", "data-nospeech": "" }, q))
  }
  if (ctx.lang) cardToggle(article, head, ctx)
  return article
}

// «Traduzione» of a card, in its head beside «Ascolta» (D-402): drawn only where the card has an Italian text to show. It opens every `.tr` in the card,
// those added later too (the reply of a check, a solution), and the unit buttons of the blocks are its exceptions. The cover puts it beside «Comincia».
export function cardToggle(article, host, ctx) {
  if (!article.querySelector(".tr")) return null
  const button = toggleButton({ text: ctx.t.translation.toggle, icon: icon("languages", "tr-ic") })
  host.appendChild(button)
  refresh(article)
  return button
}

// The blocks that get a small unit button (D-402): a long Italian text is opened on its own, without opening the whole card. A mistake and a reveal are
// flip cards drawn as one button, so nothing is put inside them: the card's button opens theirs.
const UNIT_TYPES = new Set(["text", "callout", "example", "procedure", "check"])
// more than a line of Italian on a 390 px phone (about 35 characters): a shorter text is not worth a button of its own
const UNIT_MIN_CHARS = 40
// where a unit button may not stand: in a control, a heading, a name
const NOT_FOR_BUTTON = "button, summary, label, a, strong, h1, h2, h3, h4, h5, h6, figcaption, caption, th, td"

export function withUnitButton(node, block, ctx) {
  if (!ctx.lang || !UNIT_TYPES.has(block.type) || !node?.querySelectorAll) return node
  const target = [...node.querySelectorAll(".tr")].find((tr) => !tr.closest(NOT_FOR_BUTTON) && (tr.textContent ?? "").trim().length >= UNIT_MIN_CHARS)
  if (!target) return node
  const source = block.text_it ?? block.problem_it ?? block.prompt_it ?? block.title_it ?? block.steps?.[0]?.text_it ?? ""
  const button = toggleButton({ unit: true, icon: icon("languages", "tr-ic"), ariaLabel: unitLabel(ctx.t.translation.unit, source) })
  node.setAttribute("data-tr-scope", "block")
  node.setAttribute("data-tr-block", String(block.n))
  target.parentNode.insertBefore(el("span", { class: "tr-unit", "data-nospeech": "" }, button), target)
  refresh(node)
  return node
}

// "Commenta" (D-304): every block is a place a comment can name, "block:N" under its card.
function anchored(node, block) {
  if (node?.setAttribute && block.n !== undefined && !node.hasAttribute("data-comment-anchor")) node.setAttribute("data-comment-anchor", `block:${block.n}`)
  return node
}

function renderOne(block, card, root, renderBlock) {
  const loc = { card: card.n, block: block.n }
  // in a bilingual lesson a block draws with its own table of translations in front of its card's and the lesson's
  const ctx = root.lang ? scoped(root, block, card) : root
  return withUnitButton(drawBlock(block, ctx, loc, renderBlock), block, ctx)
}

function drawBlock(block, ctx, loc, renderBlock) {
  switch (block.type) {
    case "text": return text(block, ctx)
    case "callout": return callout(block, ctx)
    case "math": return math(block, ctx)
    case "procedure": return procedure(block, ctx)
    case "cases": return cases(block, ctx)
    case "legend": return legend(block, ctx)
    case "mistake": return mistake(block, ctx)
    case "summary": return summary(block, ctx)
    case "source": return source(block, ctx)
    case "reveal": return reveal(block, ctx)
    case "dialogue": return dialogue(block, ctx)
    case "oral": return oral(block, ctx, loc)
    case "code": return code(block, ctx)
    case "page": return freePage(block, ctx, loc)
    case "table": return table(block, ctx)
    case "diagram":
    case "schema": return diagram(block, ctx)
    case "more": return more(block, ctx, renderBlock)
    case "example": return ctx.safe ? safeExample(block, ctx) : example(block, ctx, loc)
    case "check": return ctx.safe ? el("div") : el("div", { class: "block block-check" }, renderCheck(block, ctx, loc).element)
    case "try": return tryBlock(block, ctx, loc)
    default: return el("div", { class: "block block-unknown" })
  }
}

// Safe mode (BANCO_LESSON2_ENABLED=0): the served example steps as plain text, no reveal, no checks.
function safeExample(block, ctx) {
  const root = el("section", { class: "block example" })
  root.appendChild(el("p", { class: "example-label" }, el("strong", { text: ctx.t.problem })))
  root.appendChild(ctx.rich(block.problem_it))
  const list = el("ol", { class: "example-steps" })
  for (const s of block.steps) if (s.do_it) list.appendChild(el("li", { class: "example-step" }, ctx.rich(s.do_it), s.why_it ? ctx.rich(s.why_it) : null))
  root.appendChild(list)
  return root
}

export { roleOf }
