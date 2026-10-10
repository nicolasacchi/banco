// procedure: numbered steps, each with the tag's icon and Italian verb (step_tags of the palette), a short
// line and an example; the mnemonic line on top ("Sviluppa → Sposta → Somma → Dividi").
import palette from "lesson/palette"
import { el, icon } from "lesson/dom"
import { renderInlineRich, renderMath } from "lesson/text"

export const tagInfo = (subject, tag) => palette.step_tags[subject]?.[tag] ?? { label_it: tag, icon: "info" }

export function render(block, ctx) {
  const box = el("section", { class: "block procedure" })
  if (block.title_it) box.appendChild(el("h3", { class: "block-title", text: block.title_it }))
  box.appendChild(el("p", { class: "mnemonic", text: block.steps.map((s) => tagInfo(ctx.subject, s.tag).label_it).join(" → ") }))
  const list = el("ol", { class: "steps" })
  block.steps.forEach((step, i) => {
    const info = tagInfo(ctx.subject, step.tag)
    const li = el("li", { class: "step" },
      el("span", { class: "step-no", "aria-hidden": "true", text: String(i + 1) }),
      el("div", { class: "step-main" },
        el("p", { class: "step-tag" }, icon(info.icon, "step-ic"), el("strong", { text: info.label_it })),
        renderInlineRich(step.text_it, el("p", { class: "step-text" }), ctx)))
    if (step.example_tex) {
      li.querySelector(".step-main").appendChild(el("p", { class: "step-example" }, el("span", { class: "step-example-label", text: `${ctx.t.example_short} ` }), renderMath(step.example_tex, el("span", { class: "math" }), ctx)))
    }
    list.appendChild(li)
  })
  box.appendChild(list)
  return box
}
