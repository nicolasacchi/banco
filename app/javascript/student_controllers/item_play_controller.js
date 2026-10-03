import { Controller } from "@hotwired/stimulus"
import { renderItem } from "items/render"

// "Prova" (teacher): one instance of one item, drawn by the student's renderer. There
// is no endpoint for the answer: "Invia" only says that nothing is saved.
export default class extends Controller {
  static targets = ["box", "status", "send"]
  static values = { url: String, texts: Object, sentText: String }

  async connect() {
    const reply = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
    if (!reply.ok) { this.statusTarget.textContent = this.textsValue.error_generic; return }
    const data = await reply.json()
    this.handle = await renderItem(data.item, { t: this.textsValue })
    this.boxTarget.appendChild(this.handle.element)
    this.handle.mounted()
    this.handle.focus()
  }

  send() {
    this.statusTarget.textContent = this.sentTextValue
  }
}
