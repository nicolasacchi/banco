import { Controller } from "@hotwired/stimulus"
import { renderInline } from "items/markup"

// Agent text that the server put in the page as plain text (prompts, solutions on
// the end-of-subject screen) is rendered again with the restricted markup: bold and
// $formulas$ only. The text is read with textContent and rebuilt as DOM nodes.
export default class extends Controller {
  connect() {
    for (const node of this.element.querySelectorAll("[data-markup]")) {
      const text = node.textContent
      node.textContent = ""
      renderInline(text, node)
    }
  }
}
