// The item templates of the Diagnosi page (X-02): one module per component, all
// rendering on the app origin from the JSON the server served. renderItem() is the
// one entry point; testlet.js calls renderPart() for its sub items.
import { el } from "items/dom"
import { renderPrompt } from "items/prompt"
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
  return result
}

// The whole item: prompt, then input. A testlet puts the prompt of each sub item
// inside its own section, so only the input part is placed here.
export async function renderItem(item, ctx) {
  const result = await renderPart(item, ctx)
  const box = el("div", { class: "item-body" })
  if (item.component !== "testlet") box.appendChild(result.promptElement)
  box.appendChild(result.element)
  return { ...result, element: box }
}
