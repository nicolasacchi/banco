import { Controller } from "@hotwired/stimulus"

// The lesson/2 page (A10): cards, the lesson map, checks answered by the server. The body is the projection
// of Lessons::StudentBody (no answers in it), embedded as JSON in #lesson-body; the texts and the addresses
// come as values. All the work is in lesson/render.js, loaded here on demand.
export default class extends Controller {
  static values = {
    topic: String, revisionId: Number, urls: Object, resume: Number, view: String, reduceMotion: Boolean, safe: Boolean,
    labels: Object, items: Object, questionLabels: Object, unavailable: Array, seen: Array, mode: { type: String, default: "student" }
  }

  async connect() {
    const source = document.getElementById("lesson-body")
    if (!source) return
    const body = JSON.parse(source.textContent)
    const { renderLesson } = await import("lesson/render")
    this.api = renderLesson(this.element, body, {
      mode: this.modeValue, safe: this.safeValue, topic: this.topicValue, revisionId: this.revisionIdValue, urls: this.urlsValue,
      resume: this.hasResumeValue && this.resumeValue > 0 ? this.resumeValue : null, view: this.viewValue,
      reduceMotion: this.reduceMotionValue, labels: this.labelsValue, items: this.itemsValue, questionLabels: this.questionLabelsValue,
      unavailableTopics: this.unavailableValue, seen: this.seenValue,
      savePreferences: (change) => this.save(change)
    })
    this.element.dataset.ready = "1"
    window.lessonApi = this.api
  }

  disconnect() {
    this.api?.destroy()
    this.api = null
  }

  // The student's choices (theme, size, view, reduced motion) go to the server, which keeps them for every computer.
  async save(change) {
    try {
      const body = new URLSearchParams()
      for (const [k, v] of Object.entries(change)) body.set(k, String(v))
      await fetch("/diagnosis/preferences", {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" },
        body
      })
    } catch (_error) { /* the choice stays on this page */ }
  }
}
