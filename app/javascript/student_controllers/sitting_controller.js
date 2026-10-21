import { Controller } from "@hotwired/stimulus"
import { DONT_KNOW } from "items/dom"
import { Outbox, newId } from "items/outbox"
import { renderItem } from "items/render"
import { renderHelp } from "items/help"
import { renderMarkup } from "items/markup"
import { Refusals } from "items/refusals"
import { showRefusalNotice } from "items/refusal_notice"

// The one app page of a sitting (X-02, E-10): Turbo is not loaded. This controller
// asks the server for each item as JSON (POST step), draws it with the templates in
// app/javascript/items/, and posts each answer through the local outbox. It shows no
// timer, bar or total. Pause and visibility are posted when they change; one request
// every ten minutes while the page is visible keeps the session alive (B-05).
export default class extends Controller {
  static targets = ["intro", "stage", "heading", "itemBox", "sendButton", "unknownButton", "work", "status", "blocked", "over", "wait", "help", "helpBody", "sheetButton", "sheet", "sheetBody", "leaveBox"]
  static values = { stepUrl: String, eventsUrl: String, supportUrl: String, answerUrl: String, listUrl: String, subject: String,
                    resuming: Boolean, keepaliveSeconds: { type: Number, default: 600 }, texts: Object }

  connect() {
    this.texts = this.textsValue
    this.outbox = new Outbox({ url: this.answerUrlValue, csrf: () => this.csrf() })
    this.current = null
    this.refusals = new Refusals()
    this.active = false
    this.onVisibility = () => this.visibilityChanged()
    document.addEventListener("visibilitychange", this.onVisibility)
    // The menu of a sitting has one link, "Pausa: torna a Oggi" (D-240). It sits in the layout, outside this element.
    this.onLeaveClick = (event) => this.leaveClicked(event)
    document.addEventListener("click", this.onLeaveClick)
    this.keepalive = setInterval(() => this.ping(), this.keepaliveSecondsValue * 1000)
    // An answer left in the outbox by an earlier page goes out first, on its own.
    if (this.outbox.size > 0) this.outbox.flush()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    document.removeEventListener("click", this.onLeaveClick)
    clearInterval(this.keepalive)
    clearInterval(this.retryTimer)
  }

  csrf() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }

  // ---- flow ---------------------------------------------------------------

  async begin() {
    this.introTarget.hidden = true
    this.stageTarget.hidden = false
    this.active = true
    await this.advance()
  }

  async advance() {
    this.setStatus(this.texts.loading)
    const flushed = await this.outbox.flush()
    if (flushed.blocked) return this.showBlocked()
    const reply = await this.postJson(this.stepUrlValue)
    if (!reply) return this.showBlocked()
    this.setStatus("")
    switch (reply.type) {
      case "item": return this.showItem(reply)
      case "sitting_over": return this.showOnly(this.overTarget)
      case "wait": return this.showOnly(this.waitTarget)
      case "final": window.location.assign(reply.results_url); return null
      default: return this.showBlocked()
    }
  }

  async showItem(reply) {
    this.element.dataset.ready = "false"
    this.hideBlocked()
    this.workTarget.hidden = false
    this.current = reply
    // "Commenta" (D-304): a comment on this question names the served event; the server checks it is this run's.
    this.itemBoxTarget.dataset.commentServedEventId = String(reply.served_event_id)
    this.unknownButtonTarget.textContent = reply.not_studied_button ? this.texts.not_studied : this.texts.dont_know
    this.itemBoxTarget.textContent = ""
    try {
      this.handle = await renderItem(reply.item, { t: this.texts })
    } catch (error) {
      console.error(error)
      return this.setStatus(this.texts.error_generic)
    }
    // The subject, then the question number in a piece that never breaks (D-307); the text reads "Matematica · Domanda 7".
    const subject = Object.assign(document.createElement("span"), { className: "sitting-subject", textContent: reply.subject })
    const count = Object.assign(document.createElement("span"), { className: "sitting-count", textContent: this.texts.header_count.replace("%{number}", reply.number) })
    this.headingTarget.replaceChildren(subject, " · ", count)
    this.itemBoxTarget.appendChild(this.handle.element)
    this.handle.mounted()
    this.showSupports(reply)
    this.setButtons(true)
    this.handle.focus()
    return null
  }

  // ---- supports (D-216): "Come si risponde" and the declared formula sheet --------------------

  // The help follows the component of the item on screen and starts closed. The sheet is only
  // ever in the reply when the teacher switched it on and the item was served with it.
  showSupports(reply) {
    renderHelp(reply.item, this.texts, this.helpBodyTarget)
    this.helpTarget.open = false
    this.sheetBodyTarget.textContent = ""
    this.sheetTarget.hidden = true
    this.sheetButtonTarget.setAttribute("aria-expanded", "false")
    if (reply.formula_sheet_it) {
      this.sheetBodyTarget.appendChild(renderMarkup(reply.formula_sheet_it))
      this.sheetButtonTarget.hidden = false
    } else {
      this.sheetButtonTarget.hidden = true
    }
  }

  helpToggled() {
    if (this.helpTarget.open && this.current) this.postSupport("help_opened", { component: this.current.item.component })
  }

  toggleSheet() {
    const opening = this.sheetTarget.hidden
    this.sheetTarget.hidden = !opening
    this.sheetButtonTarget.setAttribute("aria-expanded", String(opening))
    if (opening && this.current) this.postSupport("formula_sheet_opened", {})
  }

  postSupport(kind, extra) {
    return this.postJson(this.supportUrlValue, { kind, served_event_id: this.current.served_event_id, ...extra }).catch(() => null)
  }

  send() {
    if (!this.handle || this.refusals.cooling(Date.now())) return
    if (this.handle.isEmpty()) return this.setStatus(this.texts.empty)
    this.submit(this.handle.raw(), this.handle.source())
  }

  dontKnow() {
    if (!this.handle || this.refusals.cooling(Date.now())) return
    this.submit(DONT_KNOW, "button")
  }

  async submit(raw, source) {
    this.setButtons(false)
    const entry = this.outbox.add({
      client_attempt_id: newId(), served_event_id: this.current.served_event_id, raw, source
    })
    this.setStatus(this.texts.saving)
    const flushed = await this.outbox.flush()
    if (flushed.blocked) return this.showBlocked()
    const reply = flushed.results[entry.client_attempt_id]
    if (reply?.status === "invalid") {
      const message = reply.message_it || this.texts.unreadable
      if (reply.message_it === this.texts.gone) { this.setStatus(message); return this.advance() }
      return this.refused(message)
    }
    // An answer the program could not read is kept for the teacher (D-317): the server says so in a neutral line.
    this.setStatus(reply?.message_it || (this.current.item.kind === "short_answer" ? this.texts.short_answer_saved : this.texts.saved))
    this.handle = null
    await new Promise((resolve) => setTimeout(resolve, 600))
    return this.advance()
  }

  // An answer the server could not read (D-298): the buttons stay inert for a moment, the focus stays in the box,
  // and from the second refusal of the same item its answer format is shown above the box with the message.
  refused(message) {
    const item = this.current
    const count = this.refusals.record(item.served_event_id, Date.now())
    if (this.refusals.showFormat(item.served_event_id)) {
      this.setStatus("")
      showRefusalNotice(this.handle, { message, format: item.item.answer_format_it })
    } else {
      this.setStatus(message)
    }
    this.handle.focus()
    setTimeout(() => { if (this.current === item && this.handle) this.setButtons(true) }, this.refusals.cooldownMs)
    return count
  }

  // ---- blocked: session expired, network down ---------------------------------

  showBlocked() {
    this.workTarget.hidden = true
    this.blockedTarget.hidden = false
    this.setStatus("")
    clearInterval(this.retryTimer)
    this.retryTimer = setInterval(() => this.retry(), 20000)
    return null
  }

  hideBlocked() {
    this.blockedTarget.hidden = true
    clearInterval(this.retryTimer)
  }

  async retry() {
    if (this.retrying) return
    this.retrying = true
    try {
      const flushed = await this.outbox.flush()
      if (!flushed.blocked) {
        const reply = await this.postJson(this.stepUrlValue)
        if (reply) return this.advance()
      }
    } finally {
      this.retrying = false
    }
    return null
  }

  // "Accedi di nuovo": a full navigation sends the browser through the login of the
  // edge proxy and back to this page, where connect() resends what is queued.
  signIn() {
    window.location.reload()
  }

  showOnly(target) {
    this.workTarget.hidden = true
    this.stageTarget.hidden = true
    this.active = false
    this.overTarget.hidden = target !== this.overTarget
    this.waitTarget.hidden = target !== this.waitTarget
    return null
  }

  // ---- pause, visibility, keep-alive ---------------------------------------------

  // "Pausa: torna a Oggi": the pause is recorded, then the browser goes to Oggi. Answers already
  // sent are kept; an answer typed and not sent asks one line first, in the page.
  leaveClicked(event) {
    const link = event.target.closest?.("a[data-sitting-leave]")
    if (!link) return
    event.preventDefault()
    this.leaveHref = link.href
    if (this.hasUnsent() && this.hasLeaveBoxTarget) {
      this.leaveBoxTarget.hidden = false
      this.leaveBoxTarget.querySelector("#leave-stay").focus()
      return
    }
    this.leaveNow()
  }

  hasUnsent() {
    return this.active && !!this.handle && !this.handle.isEmpty() && !this.sendButtonTarget.disabled
  }

  stay() {
    this.leaveBoxTarget.hidden = true
    this.handle?.focus()
  }

  async leaveNow() {
    if (this.active) await Promise.race([this.postEvent("paused"), new Promise((resolve) => setTimeout(resolve, 1500))])
    window.location.assign(this.leaveHref || "/today")
  }

  visibilityChanged() {
    if (!this.active) return
    this.postEvent(document.visibilityState === "visible" ? "visible" : "hidden")
  }

  ping() {
    if (this.active && document.visibilityState === "visible") this.postEvent("keepalive")
  }

  postEvent(kind) {
    return this.postJson(this.eventsUrlValue, { kind }).catch(() => null)
  }

  // ---- helpers ------------------------------------------------------------------

  // data-ready is the one honest "an item is on screen and can be answered" signal (the system tests wait on it).
  setButtons(enabled) {
    this.element.dataset.ready = String(enabled && !!this.handle)
    this.sendButtonTarget.disabled = !enabled
    this.unknownButtonTarget.disabled = !enabled
  }

  setStatus(text) {
    this.statusTarget.textContent = text || ""
  }

  // POST JSON; null when the reply is not JSON, is a redirect or is not a 200.
  async postJson(url, body = {}) {
    try {
      const response = await fetch(url, {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": this.csrf() },
        body: JSON.stringify(body)
      })
      if (response.type === "opaqueredirect" || response.status !== 200) return null
      if (!(response.headers.get("content-type") || "").includes("json")) return null
      return await response.json()
    } catch (_error) {
      return null
    }
  }
}
