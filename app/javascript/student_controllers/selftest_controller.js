import { Controller } from "@hotwired/stimulus"

// The browser matrix page (D-289, SPEC B10.8): the free page block, as the lesson page draws it, with a stub of the lesson's ctx; the page's
// "done" event carries one character per row (rows.mjs of the fixture), shown here as a table the operator copies into the RUNBOOK.
const ROWS = [
  ["module", "funziona"], ["kit", "funziona"], ["three", "funziona"], ["webgl", "funziona o testo"], ["texture", "funziona"], ["font", "funziona"], ["bridge", "funziona"],
  ["fetch_own", "bloccato"], ["fetch_app", "bloccato"], ["cookie", "bloccato"], ["top", "bloccato"], ["frame", "bloccato"], ["rtc", "bloccato"], ["prefetch", "bloccato"], ["storage", "bloccato"]
]
const WORDS = { w: "funziona", b: "bloccato", n: "NON bloccato", x: "non funziona", f: "senza 3D (testo)" }

export default class extends Controller {
  static targets = ["frame", "status", "table", "browser"]
  static values = { view: Object, labels: Object }

  async connect() {
    const { render } = await import("lesson/blocks/page")
    const ctx = {
      t: { pages: this.labelsValue }, reduced: () => matchMedia("(prefers-reduced-motion: reduce)").matches, safe: false,
      pageEvent: (kind, detail) => this.heard(kind, detail)
    }
    const block = { n: 1, type: "page", page: "math.pages-selftest", revision: 0, view: this.viewValue }
    this.frameTarget.append(render(block, ctx, { card: 1, block: 1 }))
    this.browserTarget.textContent = navigator.userAgent
  }

  heard(kind, detail) {
    if (kind === "page_failed") this.statusTarget.textContent = `La pagina non si è avviata (${detail.limit}).`
    if (kind === "page_event" && detail.kind === "done" && typeof detail.data?.rows === "string") this.show(detail.data.rows)
  }

  show(encoded) {
    const body = this.tableTarget.querySelector("tbody")
    body.replaceChildren()
    ROWS.forEach(([id, expected], i) => {
      const tr = document.createElement("tr")
      const result = encoded[i] ?? "x"
      for (const text of [id, expected, WORDS[result] ?? result]) {
        const td = document.createElement("td")
        td.textContent = text
        tr.append(td)
      }
      body.append(tr)
    })
    this.tableTarget.hidden = false
    this.statusTarget.textContent = "Ecco cosa ha risposto il browser."
  }
}
