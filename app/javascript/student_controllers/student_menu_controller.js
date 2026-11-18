import { Controller } from "@hotwired/stimulus"

// The student's «Menu» (D-307): a button in the top bar opens the dialog with the links, like the lesson's menu.
// Escape and the close button close it; so does a tap on the backdrop. The browser gives the focus back to the button.
export default class extends Controller {
  static targets = ["opener", "dialog"]

  // The arrow back may bring this page out of the browser's cache with the menu still open (the student left through a link in it): it comes back closed (D-355).
  connect() {
    this.onShow = (event) => { if (event.persisted) this.close() }
    window.addEventListener("pageshow", this.onShow)
  }

  disconnect() {
    window.removeEventListener("pageshow", this.onShow)
  }

  open() {
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  // A click on the dialog element itself (not on its content) is a click on the backdrop.
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
