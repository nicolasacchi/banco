import { Controller } from "@hotwired/stimulus"
import { drawFrozen } from "items/frozen_slot"

// "Tutte le domande" (teacher): every stored instance of every pinned item, drawn by the
// student's own templates from the presentation the page carries, then switched off. Nothing
// is posted: the page has no answer endpoint. The key, the typical errors and the solution are
// in hidden blocks that "Mostra risposte" opens; the first instance of each item is drawn at
// once, the others when their "Altre varianti" opens (or before printing).
export default class extends Controller {
  static targets = ["slot", "answers", "others"]
  static values = { texts: Object }

  connect() {
    this.beforePrint = () => this.openAll()
    window.addEventListener("beforeprint", this.beforePrint)
    this.drawVisible()
  }

  disconnect() {
    window.removeEventListener("beforeprint", this.beforePrint)
  }

  toggleAnswers(event) {
    const shown = event.target.checked
    this.element.classList.toggle("show-answers", shown)
    this.answersTargets.forEach((box) => { box.hidden = !shown })
  }

  print() {
    window.print()
  }

  opened() {
    this.drawVisible()
  }

  openAll() {
    this.othersTargets.forEach((details) => { details.open = true })
    this.drawVisible()
  }

  // Draws each slot that is not drawn yet and is not inside a closed <details>.
  async drawVisible() {
    for (const slot of this.slotTargets) {
      if (slot.dataset.drawn || slot.closest("details:not([open])")) continue
      await drawFrozen(slot, this.textsValue)
    }
  }
}
