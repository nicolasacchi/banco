import { Controller } from "@hotwired/stimulus"

// Settings (D-354, D-378): choosing a colour, a size or a language changes the page and is saved at once; there is no «Salva» button. The change goes to the page's own
// preferences endpoint (the student's or the teacher preview's base path) as JSON.
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
    // the language changes the texts of the whole page (D-356): once saved, the page is asked for again in it
    if (input.name === "language") this.queue = this.queue.then(() => this.reloadIfLanguageChanged())
  }

  // The Enter key on a choice submits the form (there is no button): send what is checked and stay here (no redirect, so no second entry in the history).
  submit(event) {
    event.preventDefault()
    this.statusTarget.textContent = ""
    const checked = this.element.querySelectorAll("input[type=radio]:checked")
    this.queue = this.queue.then(() => this.save(Object.fromEntries([...checked].map((input) => [input.name, input.value]))))
    this.queue = this.queue.then(() => this.reloadIfLanguageChanged())
  }

  // The language checked is not the one the page is in, and it was saved: reload (a failed save leaves the page and its line as they are).
  reloadIfLanguageChanged() {
    const language = this.element.querySelector("input[name=language]:checked")?.value
    if (language && language !== document.documentElement.lang && this.saved) window.location.reload()
  }

  async save(fields) {
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" },
        body: new URLSearchParams(fields)
      })
      this.saved = response.ok
      this.statusTarget.textContent = response.ok ? this.savedValue : this.failedValue
    } catch (_error) {
      this.saved = false
      this.statusTarget.textContent = this.failedValue
    }
  }
}
