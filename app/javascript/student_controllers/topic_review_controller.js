import { Controller } from "@hotwired/stimulus"
import { drawFrozen } from "items/frozen_slot"

// The teacher's guided review of a topic (D-240): four steps with a progress bar. The sample instances are drawn
// by the student's own templates and switched off. "Ho letto la lezione" and "visto" post a record of what was read
// (an app event, never a decision); a guest has no buttons and posts nothing. When the lesson is read and every
// exercise is seen, the approval button opens if the server said the gate holds.
export default class extends Controller {
  static targets = ["slot", "step", "bar", "count", "approve", "need", "card", "seenBar"]
  static values = { texts: Object, labels: Object, url: String, writable: Boolean, gate: Boolean, allowed: Boolean, steps: Object }

  connect() {
    this.state = { ...this.stepsValue }
    this.drawVisible()
    if (this.writableValue && "IntersectionObserver" in window) {
      this.observer = new IntersectionObserver((entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.intersectionRatio >= 0.5) this.mark(entry.target)
        }
      }, { threshold: [0.5] })
      this.cardTargets.forEach((card) => { if (card.dataset.seen !== "true") this.observer.observe(card) })
    }
    this.refresh()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  opened() {
    this.drawVisible()
  }

  async drawVisible() {
    for (const slot of this.slotTargets) {
      if (slot.dataset.drawn || slot.closest("details:not([open])")) continue
      await drawFrozen(slot, this.textsValue)
    }
  }

  async readLesson(event) {
    event.preventDefault()
    if (await this.post({ part: "lesson" })) {
      this.state.lesson = true
      this.refresh()
    }
  }

  async seeExercise(event) {
    event.preventDefault()
    this.mark(event.currentTarget.closest("[data-exercise-card]"))
  }

  async mark(card) {
    if (!card || card.dataset.seen === "true") return
    if (await this.post({ part: "exercise", item_revision_id: card.dataset.exerciseCard })) {
      card.dataset.seen = "true"
      this.observer?.unobserve(card)
      const label = card.querySelector("[data-seen-label]")
      if (label) label.textContent = this.labelsValue.seen
      this.state.exercises = this.cardTargets.every((c) => c.dataset.seen === "true")
      this.refresh()
    }
  }

  async post(body) {
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", credentials: "same-origin", redirect: "manual",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" },
        body: JSON.stringify(body)
      })
      return response.status === 200
    } catch (_error) {
      return false
    }
  }

  // Step states, the bar, the seen counter and the approval button follow this.state.
  refresh() {
    const labels = this.labelsValue
    let done = 0
    for (const step of this.stepTargets) {
      const name = step.dataset.step
      const isDone = !!this.state[name]
      step.dataset.done = String(isDone)
      const badge = step.querySelector("[data-step-state]")
      if (badge) badge.textContent = isDone ? labels.done : labels.todo
      document.querySelectorAll(`[data-nav-step="${name}"]`).forEach((link) => { link.dataset.done = String(isDone) })
      if (isDone) done += 1
    }
    this.barTargets.forEach((bar) => { bar.value = done })
    this.countTargets.forEach((node) => { node.textContent = String(done) })
    const seen = this.cardTargets.filter((c) => c.dataset.seen === "true").length
    this.seenBarTargets.forEach((node) => { node.textContent = `${seen}/${this.cardTargets.length}` })
    this.needTargets.forEach((need) => {
      if (this.state[need.dataset.need]) need.hidden = true
    })
    if (this.hasApproveTarget) {
      const ready = this.gateValue && this.allowedValue && this.state.lesson && this.state.exercises
      this.element.querySelectorAll("[data-approve-field]").forEach((node) => { node.disabled = !ready })
      this.approveTarget.disabled = !ready
      const hint = this.element.querySelector("[data-approve-ready]")
      if (hint) hint.hidden = !ready
    }
  }
}
