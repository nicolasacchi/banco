// Teacher mode (A14): next to a check, an example blank or an exercise, what the student's page never has,
// from the full body (GET /teacher/lesson-revisions/:id/full.json): the answer, the error messages, the
// explanation, the solution and the final. Text only.
import { el } from "lesson/dom"
import { renderInlineRich, renderRich } from "lesson/text"
import { moduleFor } from "lesson/diagrams/registry"

const tileText = (t) => t?.text_en ?? t?.text_es ?? t?.text_it ?? ""

// The names of the stored target ids of a select check, as the teacher reads them ("nucleoide, ribosomi"): the type's optional name_it
// per target, else the id. The student never sees these (his page has t1..tN).
export function targetNames(spec, ids) {
  let list = []
  try {
    list = moduleFor(spec.diagram?.type)?.targets?.(spec.diagram, spec.targets) ?? []
  } catch (_error) {
    list = []
  }
  return (ids ?? []).map((id) => list.find((t) => String(t.key) === String(id))?.name_it ?? id)
}

// A list of ids of tiles or items as the teacher reads it: the built sentence, or the items in order, joined by arrows.
export function sequenceText(spec, ids) {
  const pool = new Map((spec.tiles ?? spec.items ?? []).map((t) => [t.id, t]))
  const texts = (ids ?? []).map((id) => tileText(pool.get(id)) || id)
  return spec.component === "ordering" ? texts.join(" → ") : texts.join(" ")
}

function answerText(spec, ctx, value = spec.answer) {
  const a = value
  if (spec.component === "choice") return spec.options?.find((o) => o.id === a)?.text_it ?? String(a)
  if (spec.component === "matching") {
    const left = new Map((spec.left ?? []).map((i) => [i.id, i.text_it]))
    const right = new Map((spec.right ?? []).map((i) => [i.id, i.text_it]))
    return Object.entries(a ?? {}).map(([k, v]) => `${left.get(k) ?? k} → ${right.get(v) ?? v}`).join("; ")
  }
  if (spec.component === "tiles" || spec.component === "ordering") return sequenceText(spec, a)
  if (spec.component === "select") return `${targetNames(spec, a).join(", ")} (${spec.pick === "one" ? ctx.t.checks.teacher_pick_one : ctx.t.checks.teacher_pick_many})`
  if (spec.component === "span_select") return (a ?? []).map((id) => spec.spans?.find((s) => s.id === id)?.text_it ?? id).join(", ")
  return String(a)
}

const errorText = (spec, answer) => (spec.component === "select" ? targetNames(spec, answer).join(", ") : sequenceText(spec, answer))

export function checkNotes(full, ctx) {
  if (!full) return null
  const box = el("details", { class: "teacher-notes", open: "" }, el("summary", { text: ctx.t.teacher_answer }))
  box.appendChild(el("p", {}, el("strong", { text: `${ctx.t.teacher_right}: ` }), renderInlineRich(answerText(full, ctx), el("span"), ctx)))
  const errors = el("ul")
  for (const e of full.errors ?? []) errors.appendChild(el("li", {}, renderInlineRich(typeof e.answer === "string" ? e.answer : ["tiles", "ordering", "select"].includes(full.component) ? errorText(full, e.answer) : JSON.stringify(e.answer), el("code"), ctx), ` → `, renderInlineRich(e.message_it, el("span"), ctx), e.code ? ` (${e.code})` : ""))
  if (errors.children.length) box.append(el("p", { text: `${ctx.t.teacher_errors}:` }), errors)
  if (full.explain_it) box.appendChild(el("div", {}, el("strong", { text: `${ctx.t.teacher_explain}: ` }), renderRich(full.explain_it, ctx)))
  return box
}

export function exerciseNotes(full, ctx) {
  if (!full) return null
  const box = el("details", { class: "teacher-notes", open: "" }, el("summary", { text: ctx.t.teacher_solution }))
  if (full.solution_steps) {
    const list = el("ol")
    for (const s of full.solution_steps) list.appendChild(el("li", {}, renderInlineRich(s.do_it, el("span"), ctx), " — ", renderInlineRich(s.why_it ?? "", el("span"), ctx)))
    box.appendChild(list)
  } else if (full.solution_it) box.appendChild(renderRich(full.solution_it, ctx))
  if (full.final_it) box.appendChild(el("p", {}, el("strong", { text: `${ctx.t.final}: ` }), renderInlineRich(full.final_it, el("span"), ctx)))
  return box
}

export function stepNotes(fullStep, ctx) {
  if (!fullStep?.blank) return null
  const box = checkNotes(fullStep.blank, ctx)
  if (box && fullStep.do_it) box.appendChild(el("p", {}, el("strong", { text: `${ctx.t.teacher_step}: ` }), renderInlineRich(fullStep.do_it, el("span"), ctx)))
  return box
}
