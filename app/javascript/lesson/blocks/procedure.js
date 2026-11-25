// procedure: numbered steps, each with the tag's icon and Italian verb (step_tags of the palette), a short
// line and an example; the mnemonic line on top ("Sviluppa → Sposta → Somma → Dividi"). A step may have no tag (two «Rileggi» in a row would only
// repeat): it has no chip, and the mnemonic names the tagged steps only.
import palette from "lesson/palette"
import { el, icon } from "lesson/dom"
import { renderInlineRich, renderMath } from "lesson/text"

export const tagInfo = (subject, tag) => palette.step_tags[subject]?.[tag] ?? { label_it: tag, icon: "info" }

export function render(block, ctx) {
  const box = el("section", { class: "block procedure" })
  if (block.title_it) box.appendChild(renderInlineRich(block.title_it, el("h3", { class: "block-title" }), ctx)) // a formula in the title is drawn (D-310)
  const tagged = block.steps.filter((s) => s.tag)
  const mnemonic = el("p", { class: "mnemonic", "aria-label": tagged.map((s) => tagInfo(ctx.subject, s.tag).label_it).join(", ") })
  tagged.forEach((s, i) => {
    if (i > 0) mnemonic.appendChild(el("span", { class: "mn-arrow", "aria-hidden": "true" }, icon("next")))
    mnemonic.appendChild(el("span", { class: "mn-pill", "aria-hidden": "true", text: tagInfo(ctx.subject, s.tag).label_it }))
  })
  if (tagged.length > 0) box.appendChild(mnemonic)
  const list = el("ol", { class: "steps" })
  block.steps.forEach((step, i) => {
    const info = step.tag ? tagInfo(ctx.subject, step.tag) : null
    const main = el("div", { class: "step-main" })
    if (info) main.appendChild(el("p", { class: "step-tag" }, icon(info.icon, "step-ic"), el("strong", { text: info.label_it })))
    main.appendChild(renderInlineRich(step.text_it, el("p", { class: "step-text" }), ctx))
    const li = el("li", { class: "step" }, el("span", { class: "step-no", "aria-hidden": "true", text: String(i + 1) }), main)
    if (step.example_tex) {
      li.querySelector(".step-main").appendChild(el("p", { class: "step-example" }, el("span", { class: "step-example-label", text: ctx.t.example_short }), renderMath(step.example_tex, el("span", { class: "math" }), ctx, true)))
    }
    list.appendChild(li)
  })
  box.appendChild(list)
  return box
}
