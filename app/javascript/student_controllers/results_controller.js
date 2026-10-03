import { Controller } from "@hotwired/stimulus"

// "Penso che la mia risposta fosse giusta": one request per attempt, read by the
// teacher. No outcome comes back.
export default class extends Controller {
  static values = { flagUrl: String }

  async flag(event) {
    const button = event.currentTarget
    button.disabled = true
    try {
      const response = await fetch(this.flagUrlValue, {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: {
          "Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
        },
        body: JSON.stringify({ attempt_id: button.dataset.attemptId })
      })
      if (response.status === 200) {
        button.hidden = true
        button.parentElement.querySelector(".flagged").hidden = false
        return
      }
    } catch (_error) {
      // falls through: the button comes back
    }
    button.disabled = false
  }
}
