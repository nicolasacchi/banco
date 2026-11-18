import { Controller } from "@hotwired/stimulus"

// "Penso che la mia risposta fosse giusta": one request per attempt, read by the
// teacher. No outcome comes back.
export default class extends Controller {
  static values = { flagUrl: String }

  // «Vedi le soluzioni»: scroll to the section without adding a step to the history, so the arrow back leaves the page (D-355).
  jump(event) {
    const target = document.getElementById(event.currentTarget.hash.slice(1))
    if (!target) return
    event.preventDefault()
    target.setAttribute("tabindex", "-1")
    target.scrollIntoView({ block: "start" })
    target.focus({ preventScroll: true })
  }

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
