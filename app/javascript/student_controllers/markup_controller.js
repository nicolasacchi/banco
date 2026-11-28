import { Controller } from "@hotwired/stimulus"
import { drawMarked } from "items/markup"

// Agent text that the server put in the page as plain text (prompts, solutions on the end-of-subject screen, the task of a writing box) is rendered again with
// the restricted markup, as items/markup.js draws it: `data-markup="inline"` bold and $formulas$ in one run, `data-markup="block"` also paragraphs and numbered
// lists, as the stem of an item is drawn (D-410). The text is read with textContent and rebuilt as DOM nodes.
export default class extends Controller {
  connect() {
    drawMarked(this.element)
  }
}
