// The item templates of the Diagnosi page (X-02): one module per component, all
// rendering on the app origin from the JSON the server served. renderItem() is the
// one entry point; testlet.js calls renderPart() for its sub items.
import { el } from "items/dom"
import { renderInline } from "items/markup"
import { renderPrompt, renderSteps } from "items/prompt"
import { langOf, sides, trNode } from "items/bilingual"
import { render as number } from "items/number"
import { render as fraction } from "items/fraction"
import { render as expression } from "items/expression"
import { render as choice } from "items/choice"
import { render as ordering } from "items/ordering"
import { render as matching } from "items/matching"
import { render as normalizedText } from "items/normalized_text"
import { render as shortAnswer } from "items/short_answer"
import { render as testlet } from "items/testlet"

export const TEMPLATES = {
  number, fraction, expression, choice, ordering, matching,
  normalized_text: normalizedText, short_answer: shortAnswer, testlet
}

// One answerable part. The handle carries promptElement as well, so a testlet can
// place each sub item's prompt above its input.
export async function renderPart(part, ctx) {
  const template = TEMPLATES[part.component]
  if (!template) throw new Error(`no template for component ${part.component}`)
  const result = await template(part, ctx)
  result.promptElement = renderPrompt(part, ctx)
  // "Commenta" (D-304): the answer area is a place of its own (the prompt and the item are set where they are built).
  if (!result.element.hasAttribute("data-comment-anchor")) result.element.setAttribute("data-comment-anchor", "answer")
  // What to do (steps) goes with the prompt, above the input; the form of the answer sits under the input (D-216). A bilingual item has both
  // texts (`steps_<lang>` + `steps_it`, `answer_format_<lang>` + `answer_format_it`, D-402); the Italian is a line under each, hidden until opened.
  const lang = langOf(part)
  const steps = sides(part, "steps", lang)
  if (Array.isArray(steps?.text) && steps.text.length > 0) result.promptElement.appendChild(renderSteps(steps.text, ctx, lang ? steps.italian : null))
  const format = sides(part, "answer_format", lang)
  if (format?.text) {
    const line = renderInline(format.text, el("p", { class: "answer-format" }))
    if (lang) line.setAttribute("lang", lang)
    result.element.appendChild(line)
    if (lang && format.italian) result.element.appendChild(trNode(format.italian))
  }
  return result
}

// The whole item: prompt, then input. A testlet puts the prompt of each sub item
// inside its own section, so only the input part is placed here.
export async function renderItem(item, ctx) {
  const result = await renderPart(item, ctx)
  const box = el("div", { class: "item-body", "data-comment-anchor": "item" })
  if (item.component !== "testlet") box.appendChild(result.promptElement)
  box.appendChild(result.element)
  return { ...result, element: box }
}
