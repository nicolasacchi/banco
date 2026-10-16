import { Controller } from "@hotwired/stimulus"

// The Materie panel of the teacher's menu: Enter or Space on the button opens it, Esc closes it and
// gives the focus back to the button, a click or a tab outside closes it. Nothing depends on hover.
export default class extends Controller {
  static targets = ["button", "panel", "sheet"]

  // On a phone the whole menu is a sheet (a modal dialog); on a desktop it is the bar and the sheet is never opened.
  openSheet() {
    if (this.hasSheetTarget && !this.sheetTarget.open) this.sheetTarget.showModal()
  }

  closeSheet() {
    if (this.hasSheetTarget && this.sheetTarget.open) this.sheetTarget.close()
  }

  // A click on the backdrop (the dialog itself, not its content) closes the sheet.
  backdrop(event) {
    if (event.target === this.sheetTarget) this.closeSheet()
  }

  toggle() { this.isOpen ? this.close() : this.open() }

  open() {
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }

  key(event) {
    if (event.key !== "Escape" || !this.isOpen) return
    this.close()
    this.buttonTarget.focus()
  }

  outside(event) {
    if (this.isOpen && !this.element.contains(event.target)) this.close()
  }

  focusout(event) {
    if (this.isOpen && event.relatedTarget && !this.element.contains(event.relatedTarget)) this.close()
  }

  get isOpen() { return !this.panelTarget.hidden }
}
