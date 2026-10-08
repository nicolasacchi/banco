import { Controller } from "@hotwired/stimulus"
import { newId } from "items/outbox"

// "Non ho capito": a button opens one optional line; the line goes to the teacher, who answers in person.
// Nothing here is graded and no model answers (firm rule 1). Keyboard: Escape closes, focus returns to the button.
export default class extends Controller {
  static targets = ["opener", "form", "text", "status"]
  static values = { url: String, topic: String, lessonRevisionId: Number, section: String, exercise: Number, serveId: Number, labels: Object }

  connect() {
    this.pendingId = null
  }

  toggle() {
    const opening = this.formTarget.hidden
    this.formTarget.hidden = !opening
    this.openerTarget.setAttribute("aria-expanded", String(opening))
    if (opening) this.textTarget.focus()
    else this.openerTarget.focus()
  }

  key(event) {
    if (event.key === "Escape" && !this.formTarget.hidden) {
      event.preventDefault()
      this.toggle()
    }
  }

  async send(event) {
    event.preventDefault()
    this.pendingId ||= newId()
    const body = { client_question_id: this.pendingId, topic: this.topicValue, text_it: this.textTarget.value.trim() || null,
                   lesson_revision_id: this.hasLessonRevisionIdValue ? this.lessonRevisionIdValue : null,
                   serve_id: this.hasServeIdValue ? this.serveIdValue : null,
                   section: this.hasSectionValue ? this.sectionValue : null,
                   exercise: this.hasExerciseValue ? this.exerciseValue : null }
    let ok = false
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" },
        body: JSON.stringify(body)
      })
      ok = response.status === 200 && (response.headers.get("content-type") || "").includes("json") && (await response.json()).ok === true
    } catch (_error) {
      ok = false
    }
    if (ok) {
      this.pendingId = null
      this.textTarget.value = ""
      this.formTarget.hidden = true
      this.openerTarget.setAttribute("aria-expanded", "false")
      this.statusTarget.textContent = this.labelsValue.sent
      this.openerTarget.focus()
    } else {
      this.statusTarget.textContent = this.labelsValue.error
    }
  }
}
