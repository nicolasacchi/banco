import { Controller } from "@hotwired/stimulus"

// The teacher's dashboard (D-242) keeps itself up to date. It polls a small digest of the ledger
// (every `interval` seconds while the tab is visible; every 60 after 10 polls that found nothing),
// polls at once when the tab becomes visible again or another tab says something was decided
// (BroadcastChannel "banco"), and when the digest changed it fetches the body and swaps it in,
// keeping the scroll position and the focus. Rows whose text changed say "aggiornato ora" for 10 s.
const SLOW_SECONDS = 60
const MARK_SECONDS = 10
const STORAGE_KEY = "banco.dashboard.newtab"

export default class extends Controller {
  static targets = ["body", "stamp", "live", "newtab"]
  static values = {
    stateUrl: String, fragmentUrl: String, digest: String, interval: { type: Number, default: 20 }, slowAfter: { type: Number, default: 10 },
    stampText: String, updatedText: String, announceText: String, announceOtherText: String, failedText: String
  }

  connect() {
    this.unchanged = 0
    this.busy = false
    this.marks = new Map()
    this.restoreToggle()
    this.applyNewTab()
    this.onVisible = () => { if (document.visibilityState === "visible") this.poll() }
    document.addEventListener("visibilitychange", this.onVisible)
    if ("BroadcastChannel" in window) {
      this.channel = new BroadcastChannel("banco")
      this.channel.onmessage = () => this.poll()
    }
    this.stamp()
    this.schedule()
    this.element.dataset.dashboardReady = "true"
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    this.channel?.close()
    clearTimeout(this.timer)
    for (const t of this.marks.values()) clearTimeout(t)
  }

  refresh() { this.poll(true) }

  toggleNewTab() {
    try { localStorage.setItem(STORAGE_KEY, this.newtabTarget.checked ? "on" : "off") } catch (_) { /* private mode */ }
    this.applyNewTab()
  }

  restoreToggle() {
    let saved = null
    try { saved = localStorage.getItem(STORAGE_KEY) } catch (_) { /* private mode */ }
    this.newtabTarget.checked = saved !== "off"
  }

  // Every link marked data-newtab opens in a new tab while the toggle is on.
  applyNewTab() {
    const on = this.newtabTarget.checked
    this.element.querySelectorAll("a[data-newtab]").forEach((a) => {
      if (on) { a.target = "_blank"; a.rel = "noopener" } else { a.removeAttribute("target"); a.removeAttribute("rel") }
    })
  }

  // The next poll, only while the tab is visible; the visibilitychange handler starts it again.
  schedule() {
    clearTimeout(this.timer)
    if (document.visibilityState !== "visible") return
    const seconds = this.unchanged >= this.slowAfterValue ? Math.max(SLOW_SECONDS, this.intervalValue) : this.intervalValue
    this.timer = setTimeout(() => this.poll(false, false), seconds * 1000)
  }

  // fresh: the timer lets the server answer from its few-seconds cache; every other trigger asks for the current value.
  async poll(force = false, fresh = true) {
    if (this.busy) return
    this.busy = true
    clearTimeout(this.timer)
    try {
      const state = await this.getJSON(fresh ? `${this.stateUrlValue}?fresh=1` : this.stateUrlValue)
      if (force || state.digest !== this.digestValue) {
        await this.replaceBody()
        this.digestValue = state.digest
        this.unchanged = 0
      } else {
        this.unchanged += 1
      }
      this.stamp()
    } catch (_) {
      this.stampTarget.textContent = this.failedTextValue
    } finally {
      this.busy = false
      this.schedule()
    }
  }

  async getJSON(url) {
    const response = await fetch(url, { credentials: "same-origin", headers: { Accept: "application/json" }, cache: "no-store" })
    if (!response.ok) throw new Error(String(response.status))
    return response.json()
  }

  async replaceBody() {
    const response = await fetch(this.fragmentUrlValue, { credentials: "same-origin", headers: { Accept: "text/html" }, cache: "no-store" })
    if (!response.ok) throw new Error(String(response.status))
    const html = await response.text()
    const before = this.snapshot()
    const scroll = { x: window.scrollX, y: window.scrollY }
    const focus = this.focusKey()
    this.bodyTarget.innerHTML = html
    this.applyNewTab()
    window.scrollTo(scroll.x, scroll.y)
    this.restoreFocus(focus)
    this.markChanged(before)
  }

  snapshot() {
    const map = new Map()
    this.bodyTarget.querySelectorAll("[data-row-key]").forEach((el) => map.set(el.dataset.rowKey, this.textOf(el)))
    return map
  }

  // The text of a row without the "aggiornato ora" badge, so a mark is never a change of its own.
  textOf(el) {
    const copy = el.cloneNode(true)
    copy.querySelectorAll(".updated-badge").forEach((b) => b.remove())
    return copy.textContent.replace(/\s+/g, " ").trim()
  }

  markChanged(before) {
    const names = []
    this.bodyTarget.querySelectorAll("[data-row-key]").forEach((el) => {
      const key = el.dataset.rowKey
      if (before.get(key) === this.textOf(el)) return
      this.mark(el, key)
      if (el.dataset.rowName && !names.includes(el.dataset.rowName)) names.push(el.dataset.rowName)
    })
    this.liveTarget.textContent = names.length ? this.announceTextValue.replace("{names}", names.join(", ")) : this.announceOtherTextValue
  }

  mark(el, key) {
    el.classList.add("just-updated")
    const badge = document.createElement("span")
    badge.className = "updated-badge"
    badge.textContent = this.updatedTextValue
    el.prepend(badge)
    clearTimeout(this.marks.get(key))
    this.marks.set(key, setTimeout(() => {
      el.classList.remove("just-updated")
      badge.remove()
      this.marks.delete(key)
    }, MARK_SECONDS * 1000))
  }

  focusKey() {
    const el = document.activeElement
    if (!el || !this.bodyTarget.contains(el)) return null
    return el.id ? { id: el.id } : { href: el.getAttribute("href"), text: el.textContent }
  }

  restoreFocus(key) {
    if (!key) return
    let target = null
    if (key.id) target = document.getElementById(key.id)
    else target = [...this.bodyTarget.querySelectorAll("a, button")].find((a) => a.getAttribute("href") === key.href && a.textContent === key.text)
    target?.focus({ preventScroll: true })
  }

  stamp() {
    const now = new Date()
    const time = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`
    this.stampTarget.textContent = this.stampTextValue.replace("{time}", time)
  }
}
