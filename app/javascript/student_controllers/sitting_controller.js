import { Controller } from "@hotwired/stimulus"
import { DONT_KNOW } from "items/dom"
import { Outbox, newId } from "items/outbox"
import { renderItem } from "items/render"

// The one app page of a sitting (X-02, E-10): Turbo is not loaded. This controller
// asks the server for each item as JSON (POST step), draws it with the templates in
// app/javascript/items/, and posts each answer through the local outbox. It shows no
// timer, bar or total. Pause and visibility are posted when they change; one request
// every ten minutes while the page is visible keeps the session alive (B-05).
export default class extends Controller {
  static targets = ["intro", "stage", "heading", "itemBox", "sendButton", "unknownButton", "pauseButton", "paused",
                    "work", "status", "blocked", "over", "wait"]
  static values = { stepUrl: String, eventsUrl: String, answerUrl: String, listUrl: String, subject: String,
                    resuming: Boolean, keepaliveSeconds: { type: Number, default: 600 }, texts: Object }

  connect() {
    this.texts = this.textsValue
    this.outbox = new Outbox({ url: this.answerUrlValue, csrf: () => this.csrf() })
    this.current = null
    this.active = false
    this.paused = false
    this.onVisibility = () => this.visibilityChanged()
    document.addEventListener("visibilitychange", this.onVisibility)
    this.keepalive = setInterval(() => this.ping(), this.keepaliveSecondsValue * 1000)
    // An answer left in the outbox by an earlier page goes out first, on its own.
    if (this.outbox.size > 0) this.outbox.flush()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
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
    this.hideBlocked()
    this.workTarget.hidden = false
    this.current = reply
    this.unknownButtonTarget.textContent = reply.not_studied_button ? this.texts.not_studied : this.texts.dont_know
    this.itemBoxTarget.textContent = ""
    try {
      this.handle = await renderItem(reply.item, { t: this.texts })
    } catch (error) {
      console.error(error)
      return this.setStatus(this.texts.error_generic)
    }
    this.headingTarget.textContent = this.texts.header.replace("%{subject}", reply.subject).replace("%{number}", reply.number)
    this.itemBoxTarget.appendChild(this.handle.element)
    this.handle.mounted()
    this.setButtons(true)
    this.handle.focus()
    return null
  }

  send() {
    if (!this.handle) return
    if (this.handle.isEmpty()) return this.setStatus(this.texts.empty)
    this.submit(this.handle.raw(), this.handle.source())
  }

  dontKnow() {
    if (!this.handle) return
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
      this.setStatus(reply.message_it || this.texts.unreadable)
      if (reply.message_it === this.texts.gone) return this.advance()
      this.setButtons(true)
      return null
    }
    this.setStatus(this.current.item.kind === "short_answer" ? this.texts.short_answer_saved : this.texts.saved)
    this.handle = null
    await new Promise((resolve) => setTimeout(resolve, 600))
    return this.advance()
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

  pause() {
    this.paused = true
    this.workTarget.hidden = true
    this.pausedTarget.hidden = false
    this.pauseButtonTarget.hidden = true
    this.postEvent("paused")
  }

  resume() {
    this.paused = false
    this.pausedTarget.hidden = true
    this.pauseButtonTarget.hidden = false
    this.workTarget.hidden = false
    this.postEvent("resumed")
    this.handle?.focus()
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

  setButtons(enabled) {
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
