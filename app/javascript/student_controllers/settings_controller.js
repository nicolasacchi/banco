import { Controller } from "@hotwired/stimulus"

// Settings (D-354): choosing a colour or a size changes the page and is saved at once, with no «Salva». The change goes to the page's own
// preferences endpoint (the student's or the teacher preview's base path) as JSON; the form and its button stay for a browser without scripts.
// The page changes first: the choice is on screen even when the save fails, and then a line says it was not saved.
export default class extends Controller {
  static targets = ["status"]
  static values = { url: String, saved: String, failed: String }

  connect() { this.queue = Promise.resolve() }

  choose(event) {
    const input = event.target
    const root = document.documentElement
    if (input.name === "size") root.dataset.size = input.value
    if (input.name === "theme") {
      root.dataset.themeChoice = input.value
      // «Automatico» is the device's own: cream by day, dark by night, as the layout's head script resolves it
      root.dataset.theme = input.value === "auto" ? (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "cream") : input.value
    }
    this.statusTarget.textContent = ""
    // one request after the other, so that the last choice is the one the server keeps
    this.queue = this.queue.then(() => this.save({ [input.name]: input.value }))
  }

  // «Salva» with scripts: the choices are already on the page; send what is checked and stay here (no redirect, so no second entry in the history).
  submit(event) {
    event.preventDefault()
    this.statusTarget.textContent = ""
    const checked = this.element.querySelectorAll("input[type=radio]:checked")
    this.queue = this.queue.then(() => this.save(Object.fromEntries([...checked].map((input) => [input.name, input.value]))))
  }

  async save(fields) {
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" },
        body: new URLSearchParams(fields)
      })
      this.statusTarget.textContent = response.ok ? this.savedValue : this.failedValue
    } catch (_error) {
      this.statusTarget.textContent = this.failedValue
    }
  }
}
