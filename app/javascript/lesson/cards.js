// One card (A3, A10): the header band with the icon and title, the roles legend when the card uses roles,
// then the blocks. Returns the element; the diagrams of the card are mounted by ctx.mounts afterwards.
import { el, icon } from "lesson/dom"
import { renderCheck } from "lesson/blocks/check"
import { render as callout } from "lesson/blocks/callout"
import { render as cases } from "lesson/blocks/cases"
import { render as diagram } from "lesson/blocks/diagram"
import { render as example } from "lesson/blocks/example"
import { render as legend, sample } from "lesson/blocks/legend"
import { render as math } from "lesson/blocks/math"
import { render as mistake } from "lesson/blocks/mistake"
import { render as more } from "lesson/blocks/more"
import { render as procedure } from "lesson/blocks/procedure"
import { render as summary } from "lesson/blocks/summary"
import { render as table } from "lesson/blocks/table"
import { render as text } from "lesson/blocks/text"
import { render as tryBlock } from "lesson/blocks/try"
import { questionControl } from "lesson/question"
import { equationTex } from "lesson/diagrams/balance"
import { roleOf } from "lesson/text"

const DEFAULT_ICON = { idea: "lightbulb", example: "pencil-ruler", mistakes: "triangle-alert", try: "notebook-pen", summary: "list-checks" }

// The colour roles that a card's running text uses ([[role:..]] and \role{..}{..}), in first-use order.
export function rolesUsed(card) {
  const found = []
  const scan = (value) => {
    if (typeof value === "string") {
      for (const m of value.matchAll(/\[\[([a-z]+(?:-[a-z]+)*):|\\role\{([a-z]+(?:-[a-z]+)*)\}/g)) {
        const name = m[1] ?? m[2]
        if (!found.includes(name)) found.push(name)
      }
    } else if (Array.isArray(value)) value.forEach(scan)
    else if (value && typeof value === "object") Object.entries(value).forEach(([k, v]) => k !== "diagram" && k !== "schema" && scan(v))
  }
  scan(card.blocks)
  return found
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
    id: `scheda-${card.n}`, "data-n": card.n, "data-role": card.role, "data-card": card.id, "aria-labelledby": `scheda-${card.n}-title`
  })
  const heading = el("h2", { id: `scheda-${card.n}-title`, tabindex: "-1", text: card.title_it })
  article.appendChild(el("header", { class: "card-head" },
    el("span", { class: "badge", "aria-hidden": "true" }, icon(iconOf(card), "badge-ic")),
    el("div", { class: "card-titles" }, position.kicker ? el("p", { class: "kicker", text: position.kicker }) : null, heading)))
  // a legend chip only on the first card where a role appears (the lesson map has them all); it sits below the card, not above the picture
  const roles = position.newRoles ?? rolesUsed(card)
  const hasLegend = card.blocks.some((b) => b.type === "legend")
  const body = el("div", { class: "card-body" })
  const types = card.blocks.map((b) => b.type)
  if (types.length === 2 && types.includes("text") && types.some((t) => VISUAL.has(t))) body.classList.add("is-split")
  const renderBlock = (block) => renderOne(block, card, ctx, renderBlock)
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
        grid.appendChild(el("h3", { class: "mistakes-group", text: block.group_it }))
        group = block.group_it
      }
      grid.appendChild(mistake(block, ctx, { group: block.group_it }))
      continue
    }
    grid = null
    body.appendChild(renderBlock(block))
  }
  if (roles.length > 0 && !hasLegend) {
    const line = el("p", { class: "card-legend", "aria-label": ctx.t.legend_label }, el("span", { class: "legend-intro", text: `${ctx.t.legend_label}: ` }))
    roles.forEach((r) => line.appendChild(sample(r, ctx)))
    body.appendChild(line)
  }
  article.appendChild(body)
  if (card.n !== undefined && card.role !== "try") {
    const q = questionControl(ctx, { section: card.role, card: card.n })
    if (q) article.appendChild(el("footer", { class: "card-foot" }, q))
  }
  return article
}

function renderOne(block, card, ctx, renderBlock) {
  const loc = { card: card.n, block: block.n }
  switch (block.type) {
    case "text": return text(block, ctx)
    case "callout": return callout(block, ctx)
    case "math": return math(block, ctx)
    case "procedure": return procedure(block, ctx)
    case "cases": return cases(block, ctx)
    case "legend": return legend(block, ctx)
    case "mistake": return mistake(block, ctx)
    case "summary": return summary(block, ctx)
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
