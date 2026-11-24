import { Controller } from "@hotwired/stimulus"
import { refresh, toggle } from "items/translation"

// «Traduzione» of a course page (D-402): the button of a list or topic page flips its scope (the element with data-tr-scope="page" around it), and
// opening it reports `translation_opened` once (items/translation.js posts to the scope's data-tr-url; the preview has none). The lessons and the
// practice pages have their own buttons, built by their renderers.
export default class extends Controller {
  connect() { refresh(this.element.closest("[data-tr-scope]") || this.element.parentNode) }

  toggle() { toggle(this.element) }
}
