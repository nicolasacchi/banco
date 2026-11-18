import { Controller } from "@hotwired/stimulus"
import { Outbox, newId } from "items/outbox"

// One conversation of «I miei commenti» (D-349), like a chat. The composer grows with the text; on a computer Enter sends and
// Shift+Enter makes a new line, on a phone Enter makes a new line and «Invia» sends. A message is written to a local outbox
// (banco.routbox.<comment>.) and shown at once as a bubble that says «Invio…»; the server's JSON answer ("recorded") makes it
// a sent bubble with its time. When the network fails the bubble stays with «Non inviato. Tocca per riprovare.» and the text
// is kept (also after a reload: the outbox is read again). An answer "invalid" gives the text back to the composer with the
// reason. The server records each client_reply_id once, so a resend is safe. Nothing here reads a grade or an answer.
const PHONE = "(hover: none) and (pointer: coarse)"
const SHOW_COUNT_FROM = 1600
const SCHOOL_ZONE = "Europe/Rome"

export default class extends Controller {
  static targets = ["messages", "end", "form", "text", "count", "error", "chip", "chipLabel"]
  static values = { url: String, commentId: Number, max: Number, labels: Object }

  connect() {
    this.outbox = new Outbox({
      url: this.urlValue, csrf: () => document.querySelector("meta[name=csrf-token]")?.content || "",
      prefix: `banco.routbox.${this.commentIdValue}.`, statuses: ["recorded", "invalid", "missing"], httpStatuses: [200, 404],
      fields: ["client_reply_id", "text_it"]
    })
    this.flushing = false
    this.onOnline = () => this.flush()
    window.addEventListener("online", this.onOnline)
    // What an earlier visit left in the outbox is shown again as waiting bubbles, then sent.
    for (const entry of this.outbox.pending()) this.addBubble(entry.client_attempt_id, entry.text_it, "pending")
    this.scrollToEnd()
    if (this.hasTextTarget && !window.matchMedia(PHONE).matches) this.textTarget.focus({ preventScroll: true })
    if (this.outbox.size > 0) this.flush()
  }

  disconnect() {
    window.removeEventListener("online", this.onOnline)
  }

  // ---- the composer ---------------------------------------------------------------

  grow() {
    const field = this.textTarget
    field.style.height = "auto"
    field.style.height = `${field.scrollHeight}px`
    const length = field.value.length
    if (this.hasCountTarget) {
      this.countTarget.hidden = length < SHOW_COUNT_FROM
      this.countTarget.textContent = `${length} / ${this.maxValue}`
    }
    this.scrollToEnd()
  }

  key(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
    if (window.matchMedia(PHONE).matches) return // a phone: Enter is a new line, «Invia» sends
    event.preventDefault()
    this.send()
  }

  send(event) {
    event?.preventDefault()
    const text = this.textTarget.value.replace(/\r\n?/g, "\n").trim()
    if (!text) return
    if (text.length > this.maxValue) {
      this.errorTarget.textContent = this.labelsValue.reply_error.text_it
      return
    }
    this.errorTarget.textContent = ""
    const id = newId()
    this.outbox.add({ client_attempt_id: id, client_reply_id: id, text_it: text })
    this.addBubble(id, text, "pending")
    this.textTarget.value = ""
    this.grow()
    this.flush()
  }

  retry(event) {
    event.preventDefault()
    this.messagesTarget.querySelectorAll(".cm-msg[data-pending='failed']").forEach((node) => this.showPending(node))
    this.flush()
  }

  // ---- sending ----------------------------------------------------------------------

  async flush() {
    if (this.flushing) return // the running loop takes what was added meanwhile
    this.flushing = true
    try {
      while (this.outbox.size > 0) {
        const done = await this.outbox.flush()
        for (const [id, body] of Object.entries(done.results)) this.answered(id, body)
        if (done.blocked) {
          this.messagesTarget.querySelectorAll(".cm-msg[data-pending]").forEach((node) => this.showFailed(node))
          break
        }
      }
    } finally {
      this.flushing = false
    }
  }

  answered(id, body) {
    const node = this.messagesTarget.querySelector(`.cm-msg[data-id="${id}"]`)
    if (!node) return
    if (body.status === "recorded") {
      node.removeAttribute("data-pending")
      node.querySelector(".cm-time").textContent = this.clock(body.at ? new Date(body.at) : new Date())
      this.chipTarget.dataset.state = "sent"
      this.chipLabelTarget.textContent = this.labelsValue.state_sent
      return
    }
    // refused for good: the words go back to the composer, with the reason
    const text = node.querySelector(".cm-text").textContent
    node.remove()
    if (this.hasTextTarget && !this.textTarget.value) {
      this.textTarget.value = text
      this.grow()
    }
    const reason = this.labelsValue.reply_error[body.error]
    this.errorTarget.textContent = reason || this.labelsValue.error
  }

  // ---- the bubbles ------------------------------------------------------------------

  addBubble(id, text, state) {
    this.ensureToday()
    const node = document.createElement("div")
    node.className = "cm-msg"
    node.dataset.from = "student"
    node.dataset.id = id
    const bubble = document.createElement("div")
    bubble.className = "cm-bubble"
    const body = document.createElement("p")
    body.className = "cm-text"
    body.textContent = text
    bubble.append(body)
    const time = document.createElement("p")
    time.className = "cm-time"
    node.append(bubble, time)
    this.endTarget.before(node)
    if (state === "pending") this.showPending(node)
    this.scrollToEnd()
    return node
  }

  showPending(node) {
    node.dataset.pending = "sending"
    const time = node.querySelector(".cm-time")
    time.replaceChildren(this.labelsValue.sending)
  }

  showFailed(node) {
    node.dataset.pending = "failed"
    const time = node.querySelector(".cm-time")
    const button = document.createElement("button")
    button.type = "button"
    button.className = "cm-retry"
    button.textContent = this.labelsValue.failed
    button.dataset.action = "click->comment-thread#retry"
    time.replaceChildren(button)
  }

  // A separator «Oggi» before the first message of a new day.
  ensureToday() {
    const today = this.todayKey()
    const days = this.messagesTarget.querySelectorAll(".cm-day")
    if (days.length && days[days.length - 1].dataset.day === today) return
    const separator = document.createElement("div")
    separator.className = "cm-day"
    separator.setAttribute("role", "separator")
    separator.dataset.day = today
    const label = document.createElement("span")
    label.textContent = this.labelsValue.today
    separator.append(label)
    this.endTarget.before(separator)
  }

  todayKey() {
    return new Intl.DateTimeFormat("en-CA", { timeZone: SCHOOL_ZONE }).format(new Date())
  }

  clock(date) {
    return new Intl.DateTimeFormat("it-IT", { timeZone: SCHOOL_ZONE, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(date)
  }

  scrollToEnd() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}
