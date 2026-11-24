// legend: the colour, icon and label of each role, with the question it answers (A5, A6).
import { el, icon } from "lesson/dom"
import { beside, renderInlineRich, roleOf, translationWith } from "lesson/text"
import { markerSvg } from "lesson/diagrams/markers"

const fragmentOf = (...nodes) => {
  const fragment = document.createDocumentFragment()
  fragment.append(...nodes)
  return fragment
}

// The name or the question of a palette role in the language of a bilingual lesson (D-402): `label_en|es`, `question_en|es`, drawn as target text on `node` with
// the Italian one (`label_it`, `question_it`) as its translation after it. Returns { text, italian } (italian is a `.tr` node or null), or null when the lesson
// is a legacy one or the palette has no such name: the Italian one is drawn as it always was.
function named(node, info, base, ctx) {
  const target = ctx.lang ? info?.[`${base}_${ctx.lang}`] : null
  if (!target) return null
  const italian = info[`${base}_it`] ? translationWith(info[`${base}_it`], ctx, { tag: "span" }) : null
  node.setAttribute("lang", ctx.lang)
  node.setAttribute(italian ? "data-translated" : "data-tr-exempt", "")
  return { text: target, italian }
}

export function sample(role, ctx, label) {
  const info = roleOf(ctx.subject, role)
  const span = el("span", { class: `legend-sample role role-${role}` })
  if (info?.carrier === "icon" && info.icon) span.appendChild(icon(info.icon, "role-ic"))
  else if (info?.shape) span.appendChild(markerSvg(info.shape, `mk-${role}`))
  const name = label ? null : named(span, info, "label", ctx)
  span.appendChild(document.createTextNode(label ?? name?.text ?? info?.label_it ?? role))
  return name?.italian ? fragmentOf(span, name.italian) : span
}

function question(r, info, ctx) {
  // an authored question is a pair of the lesson (folded: the target text, its Italian in `tr`); the palette's own is `question_en|es` with `question_it`
  if (r.question_it) return beside(el("span", { class: "legend-question", text: r.question_it }), r.question_it, ctx, { tag: "span" })
  if (!info?.question_it) return null
  const node = el("span", { class: "legend-question" })
  const name = named(node, info, "question", ctx)
  node.textContent = name?.text ?? info.question_it
  return name?.italian ? fragmentOf(node, name.italian) : node
}

export function render(block, ctx) {
  const list = el("ul", { class: "block legend" })
  for (const r of block.roles) {
    const info = roleOf(ctx.subject, r.role)
    const li = el("li", { class: "legend-row" }, sample(r.role, ctx))
    const ask = question(r, info, ctx)
    if (ask) li.appendChild(ask)
    if (r.note_it) li.appendChild(renderInlineRich(r.note_it, el("span", { class: "legend-note" }), ctx))
    list.appendChild(li)
  }
  return list
}
