import { Controller } from "@hotwired/stimulus"

// «Stampa» on a schema (D-372): the browser's own print dialog. The print rules (one schema on an A4 page, no menu, no buttons) are
// in schemas.css; the lesson's figures redraw for the paper by themselves (lesson/render.js listens to the print media query).
export default class extends Controller {
  print(event) {
    event?.preventDefault()
    window.print()
  }
}
