import { Controller } from "@hotwired/stimulus"

// The teacher's box (A14): the student's renderer, live, in a container whose width, theme and text size the
// teacher picks. Nothing is recorded: no events, no questions. Checks go to a teacher-only endpoint (seed
// "preview"); "Modalità docente" fetches the full body (answers, errors, solutions) and opens every "more".
export default class extends Controller {
  static targets = ["box", "root", "body", "status", "teacherToggle"]
  static values = { revisionId: Number, topic: String, labels: Object, items: Object }

  connect() {
    this.full = null
    this.mount(false)
  }

  disconnect() {
    this.api?.destroy()
  }

  async mount(teacher) {
    const { renderLesson } = await import("lesson/render")
    const keep = this.api?.current?.() ?? 0
    this.api?.destroy()
    const base = `/teacher/lesson-revisions/${this.revisionIdValue}`
    this.api = renderLesson(this.rootTarget, JSON.parse(this.bodyTarget.textContent), {
      mode: "preview", teacher, full: teacher ? this.full : null, topic: this.topicValue, revisionId: this.revisionIdValue,
      urls: { check: `${base}/checks`, solution: `${base}/exercises`, practice: "#" }, view: "cards", labels: this.labelsValue, items: this.itemsValue,
      startCard: keep
    })
    this.rootTarget.dataset.ready = "1"
  }

  width(event) {
    this.boxTarget.style.width = `${event.target.value}px`
    this.api?.relayout()
  }

  theme(event) {
    this.boxTarget.dataset.theme = event.target.value
    this.api?.relayout()
  }

  size(event) {
    this.boxTarget.dataset.size = event.target.value
    this.api?.relayout()
  }

  async teacher(event) {
    if (!event.target.checked) return this.mount(false)
    if (!this.full) {
      try {
        const response = await fetch(`/teacher/lesson-revisions/${this.revisionIdValue}/full.json`, { credentials: "same-origin", headers: { Accept: "application/json" } })
        if (response.status === 200) this.full = await response.json()
      } catch (_error) { /* shown below */ }
    }
    if (!this.full) {
      event.target.checked = false
      this.statusTarget.textContent = this.labelsValue.box.teacher_unavailable
      return
    }
    this.statusTarget.textContent = ""
    this.mount(true)
  }
}
