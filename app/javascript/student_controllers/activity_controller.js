import { Controller } from "@hotwired/stimulus"

// The teacher's minutes (C-04): while the page is visible and the teacher has done
// something in the last minute (a key, a click, a scroll, a pointer move), one beat
// per minute goes to the server with the unit of the page. The server keeps at most
// one minute per minute.
export default class extends Controller {
  static values = { url: String, unit: String, interval: { type: Number, default: 60 } }

  connect() {
    this.used = false
    this.mark = () => { this.used = true }
    for (const type of ["keydown", "pointerdown", "pointermove", "scroll", "touchstart"]) {
      window.addEventListener(type, this.mark, { passive: true })
    }
    this.timer = setInterval(() => this.beat(), this.intervalValue * 1000)
  }

  disconnect() {
    for (const type of ["keydown", "pointerdown", "pointermove", "scroll", "touchstart"]) {
      window.removeEventListener(type, this.mark)
    }
    clearInterval(this.timer)
  }

  async beat() {
    if (document.visibilityState !== "visible" || !this.used) return
    this.used = false
    const token = document.querySelector("meta[name=csrf-token]")?.content || ""
    try {
      await fetch(this.urlValue, {
        method: "POST", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
        body: JSON.stringify({ unit: this.unitValue })
      })
    } catch (_) { /* the next beat tries again */ }
  }
}
