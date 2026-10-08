import { Controller } from "@hotwired/stimulus"
import { renderMarkup } from "items/markup"

// The teacher's review page shows a lesson with the student's renderer: markup v2 blocks (paragraphs,
// numbered and bulleted lists, **bold**, $formulas$). The server puts the text in the page as plain text;
// it is read with textContent and rebuilt as DOM nodes, never as HTML.
export default class extends Controller {
  connect() {
    for (const node of this.element.querySelectorAll("[data-lesson-markup]")) {
      const text = node.textContent
      node.textContent = ""
      node.appendChild(renderMarkup(text, { lists: "v2" }))
    }
  }
}
