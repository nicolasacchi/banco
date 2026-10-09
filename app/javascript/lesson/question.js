// "Non ho capito": the same control as the course pages (course/_question.html.erb), built here so that the
// existing Stimulus controller (question_controller.js) connects to it. One per card, and one per try exercise.
import { el } from "lesson/dom"

let counter = 0

export function questionControl(ctx, { section, exercise, card }) {
  if (!ctx.questions) return null
  counter += 1
  const field = `q-l2-${counter}`
  const attrs = {
    class: "question",
    "data-controller": "question",
    "data-question-url-value": ctx.questions.url,
    "data-question-topic-value": ctx.topic,
    "data-question-lesson-revision-id-value": String(ctx.revisionId),
    "data-question-section-value": section,
    "data-question-card-value": String(card),
    "data-question-labels-value": JSON.stringify(ctx.questions.labels)
  }
  if (exercise) attrs["data-question-exercise-value"] = String(exercise)
  const t = ctx.questions.labels
  return el("div", attrs,
    el("button", { type: "button", class: "button secondary small", "data-question-target": "opener", "data-action": "question#toggle", "aria-expanded": "false", text: t.button }),
    el("form", { "data-question-target": "form", "data-action": "submit->question#send keydown->question#key", hidden: "" },
      el("label", { class: "hint", for: field, text: t.label }),
      el("input", { type: "text", id: field, class: "answer-input wide", maxlength: "300", autocomplete: "off", "data-question-target": "text" }),
      el("p", {},
        el("button", { type: "submit", class: "button small", text: t.send }), " ",
        el("button", { type: "button", class: "button secondary small", "data-action": "question#toggle", text: t.close }))),
    el("p", { role: "status", "aria-live": "polite", class: "status", "data-question-target": "status" }))
}
