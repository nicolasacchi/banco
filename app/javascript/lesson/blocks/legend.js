// legend: the colour, icon and label of each role, with the question it answers (A5, A6).
import { el, icon } from "lesson/dom"
import { roleOf } from "lesson/text"
import { markerSvg } from "lesson/diagrams/markers"
import { renderInlineRich } from "lesson/text"

export function sample(role, ctx, label) {
  const info = roleOf(ctx.subject, role)
  const span = el("span", { class: `legend-sample role role-${role}` })
  if (info?.carrier === "icon" && info.icon) span.appendChild(icon(info.icon, "role-ic"))
  else if (info?.shape) span.appendChild(markerSvg(info.shape, `mk-${role}`))
  span.appendChild(document.createTextNode(label ?? info?.label_it ?? role))
  return span
}

export function render(block, ctx) {
  const list = el("ul", { class: "block legend" })
  for (const r of block.roles) {
    const info = roleOf(ctx.subject, r.role)
    const question = r.question_it ?? info?.question_it
    const li = el("li", { class: "legend-row" }, sample(r.role, ctx))
    if (question) li.appendChild(el("span", { class: "legend-question", text: question }))
    if (r.note_it) li.appendChild(renderInlineRich(r.note_it, el("span", { class: "legend-note" }), ctx))
    list.appendChild(li)
  }
  return list
}
