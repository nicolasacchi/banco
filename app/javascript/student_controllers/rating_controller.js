import { Controller } from "@hotwired/stimulus"
import { newId } from "items/outbox"

// «Ti è piaciuto?» (D-365): 1 to 5 stars (real radio inputs with labels) and an optional comment of up to 2000 characters, both optional, one of
// them at least. «Invia» posts to /ratings; then «Grazie!» and what he sent, with «Cambia» (a new rating: the older one stays in the ledger and the
// latest is the current one). If the network fails the box says so and keeps what he wrote: pressing «Invia» again retries with the SAME
// client_rating_id, so a rating that did arrive is never stored twice. Used on the practice page (the serve value names the exercise once it is over,
// practice_controller.js sets it) and at the end of a lesson. Nothing here reads a grade or an answer, and a rating changes nothing else.
const TEXT_MAX = 2000

export default class extends Controller {
  static targets = ["form", "star", "starBox", "glyph", "clear", "text", "counter", "status", "send", "cancel", "done", "thanks", "sentStars", "sentText", "change"]
  static values = { url: String, kind: String, topic: String, lessonRevision: Number, serve: Number, current: Object, labels: Object }

  // Another exercise (or the same box shown again): an empty form, or what he gave before.
  serveValueChanged() {
    this.pendingId = null
    this.editing = false
    this.justSent = false
    this.render()
  }

  currentValueChanged() {
    this.editing = false
    this.render()
  }

  // A card of a lesson is taken off the page and put back as he moves: what he has written stays.
  connect() {
    if (this.ready) return
    this.ready = true
    this.sending = false
    this.render()
  }

  // ---- what is on the screen -------------------------------------------------------------------

  get current() {
    const value = this.currentValue || {}
    return value.stars || value.text_it ? value : null
  }

  render() {
    if (!this.hasFormTarget) return
    const current = this.current
    const showForm = !current || this.editing
    this.formTarget.hidden = !showForm
    this.doneTarget.hidden = showForm
    if (showForm) {
      this.fill(this.editing ? current : null)
      this.cancelTarget.hidden = !current
      this.statusTarget.textContent = ""
    } else {
      this.drawDone(current)
    }
  }

  fill(rating) {
    const stars = rating?.stars ?? 0
    this.starTargets.forEach((radio) => { radio.checked = Number(radio.value) === stars })
    this.textTarget.value = rating?.text_it ?? ""
    this.updateStars()
    this.count()
  }

  drawDone(rating) {
    this.thanksTarget.textContent = this.justSent ? this.labelsValue.thanks : ""
    this.thanksTarget.hidden = !this.justSent
    const stars = rating.stars ?? 0
    this.sentStarsTarget.hidden = !stars
    this.sentStarsTarget.textContent = stars ? "★".repeat(stars) + "☆".repeat(5 - stars) : ""
    if (stars) this.sentStarsTarget.setAttribute("aria-label", this.starLabel(stars))
    this.sentTextTarget.hidden = !rating.text_it
    this.sentTextTarget.textContent = rating.text_it || ""
  }

  starLabel(n) { return n === 1 ? this.labelsValue.star_one : this.labelsValue.star_other.replace("%{count}", String(n)) }

  selected() {
    const radio = this.starTargets.find((r) => r.checked)
    return radio ? Number(radio.value) : 0
  }

  picked() { this.updateStars() }

  // A filled star for every star up to the chosen one, an empty one after it (the shape says it, not only the colour).
  updateStars() {
    const chosen = this.selected()
    this.starBoxTargets.forEach((box, i) => box.classList.toggle("on", i < chosen))
    this.glyphTargets.forEach((glyph, i) => { glyph.textContent = i < chosen ? "★" : "☆" })
    this.clearTarget.hidden = chosen === 0
  }

  clear() {
    this.starTargets.forEach((radio) => { radio.checked = false })
    this.updateStars()
    this.starTargets[0]?.focus()
  }

  count() {
    this.counterTarget.textContent = this.labelsValue.chars.replace("%{n}", String(this.textTarget.value.length)).replace("%{max}", String(TEXT_MAX))
  }

  // ---- change and cancel -----------------------------------------------------------------------

  change() {
    this.editing = true
    this.justSent = false
    this.pendingId = null
    this.render()
    ;(this.starTargets.find((r) => r.checked) || this.starTargets[0])?.focus()
  }

  cancel() {
    this.editing = false
    this.pendingId = null
    this.render()
    this.changeTarget.focus()
  }

  // ---- sending ---------------------------------------------------------------------------------

  csrf() { return document.querySelector("meta[name=csrf-token]")?.content || "" }

  payload() {
    const stars = this.selected()
    const body = { client_rating_id: this.pendingId, kind: this.kindValue, stars: stars || null, text_it: this.textTarget.value.trim() }
    if (this.kindValue === "item") body.serve_id = this.serveValue
    else Object.assign(body, { topic: this.topicValue, lesson_revision_id: this.lessonRevisionValue })
    return body
  }

  async send(event) {
    event?.preventDefault()
    if (this.sending) return
    if (!this.selected() && !this.textTarget.value.trim()) {
      this.statusTarget.textContent = this.labelsValue.empty
      this.starTargets[0]?.focus()
      return
    }
    this.sending = true
    this.sendTarget.disabled = true
    this.statusTarget.textContent = this.labelsValue.sending
    this.pendingId ||= newId() // kept while the network fails, so that a repeat is the same rating
    const body = this.payload()
    let status = 0
    let reply = null
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": this.csrf() },
        body: JSON.stringify(body)
      })
      status = response.type === "opaqueredirect" ? 0 : response.status
      reply = (response.headers.get("content-type") || "").includes("json") ? await response.json() : null
    } catch (_error) {
      status = 0
    }
    this.sending = false
    this.sendTarget.disabled = false
    if (status === 200 && reply?.status === "recorded") {
      this.pendingId = null
      this.justSent = true
      this.editing = false
      this.currentValue = { stars: reply.rating?.stars ?? null, text_it: reply.rating?.text_it ?? null }
      this.render()
      this.thanksTarget.focus()
    } else if (status === 422 && reply?.status === "invalid") {
      this.pendingId = null
      this.statusTarget.textContent = this.labelsValue.invalid
    } else {
      this.statusTarget.textContent = this.labelsValue.error
    }
  }
}
