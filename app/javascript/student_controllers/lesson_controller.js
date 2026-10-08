import { Controller } from "@hotwired/stimulus"
import { renderMarkup } from "items/markup"

// The lesson page: the sections arrive as plain text in the page and are drawn here with markup v2
// (bold, $formulas$, lists), as DOM nodes and KaTeX with trust: false. The solution of an exercise is not in
// the page at all: it is fetched on the click (A9.3) and shown in a live region.
export default class extends Controller {
  static targets = ["solution"]
  static values = { solutionBase: String, labels: Object }

  connect() {
    for (const node of this.element.querySelectorAll("[data-lesson-markup]")) this.draw(node)
    this.shown = new Set()
  }

  draw(node) {
    const text = node.textContent
    node.textContent = ""
    try {
      node.appendChild(renderMarkup(text, { lists: "v2" }))
    } catch (_error) {
      const p = document.createElement("p")
      p.textContent = text
      node.appendChild(p)
    }
  }

  async solution(event) {
    const n = Number(event.params.n)
    const button = event.currentTarget
    const box = this.solutionTargets.find((t) => Number(t.dataset.n) === n)
    if (!box) return
    if (this.shown.has(n)) {
      // a second click hides the solution again
      const hide = box.hidden === false
      box.hidden = hide
      button.setAttribute("aria-expanded", String(!hide))
      return
    }
    box.textContent = this.labelsValue.loading_solution
    const reply = await this.fetchSolution(n)
    if (!reply) {
      box.textContent = this.labelsValue.error
      return
    }
    box.textContent = ""
    const title = document.createElement("h3")
    title.textContent = this.labelsValue.solution_title
    box.appendChild(title)
    const body = document.createElement("div")
    try {
      body.appendChild(renderMarkup(reply.solution_it, { lists: "v2" }))
    } catch (_error) {
      body.textContent = reply.solution_it
    }
    box.appendChild(body)
    this.shown.add(n)
    button.setAttribute("aria-expanded", "true")
  }

  async fetchSolution(n) {
    try {
      const response = await fetch(`${this.solutionBaseValue}/${n}/solution`, {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" },
        body: "{}"
      })
      if (response.status !== 200 || !(response.headers.get("content-type") || "").includes("json")) return null
      return await response.json()
    } catch (_error) {
      return null
    }
  }
}
