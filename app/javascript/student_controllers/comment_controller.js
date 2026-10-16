import { Controller } from "@hotwired/stimulus"
import { Outbox, newId } from "items/outbox"
import { anchorPath, buildComment, clip, describeAnchor, listTargets, refsOf, SELECTED_MAX, TEXT_MAX } from "items/comment_anchor"

// "Commenta" on every student page (D-304). A tap on a «Commenta» control (any element with data-comment-open)
// starts the comment mode: the page's commentable elements are outlined and a tap picks one (or "Tutta la pagina",
// or the list in the box, for keyboard and screen reader). The box takes a reason and an optional text of up to 500
// characters. In a sitting (data-comment-events-url) the counted time stops while the box is open: comment_opened
// and comment_closed are posted to the run's events, and the fold leaves that interval out. A comment is written to
// a local outbox first (banco.coutbox.) and sent when the network allows. Nothing here reads a grade or an answer.
export default class extends Controller {
  static targets = ["includeSelected", "banner", "dialog", "where", "text", "count", "status", "selected", "clockNote", "reason", "form", "excerpt", "toast"]
  static values = { url: String, eventsUrl: String, pagePath: String, labels: Object, mode: { type: Boolean, default: false } }

  connect() {
    this.outbox = new Outbox({ url: this.urlValue, csrf: () => this.csrf(), prefix: "banco.coutbox.", statuses: ["recorded", "invalid"],
      fields: ["client_comment_id", "reason", "text_it", "selected_text", "anchor", "refs", "page_path", "viewport_width", "viewport_height", "theme", "text_size"] })
    this.picked = null
    this.pendingId = null
    this.boxOpen = false
    this.lastSelection = ""
    this.onClick = (event) => this.documentClick(event)
    this.onKey = (event) => { if (event.key === "Escape" && this.modeValue && !this.boxOpen) { event.preventDefault(); this.endMode() } }
    this.onResize = () => { if (this.boxOpen) this.placeBox() }
    this.onSelection = () => this.rememberSelection()
    this.onOnline = () => this.flush()
    document.addEventListener("click", this.onClick, true)
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("selectionchange", this.onSelection)
    window.addEventListener("online", this.onOnline)
    window.addEventListener("resize", this.onResize)
    // A box left open by an earlier page (a reload, a closed tab) must not keep the clock stopped.
    if (this.hasEventsUrlValue && this.eventsUrlValue) this.postEvent("comment_closed")
    this.flush()
  }

  disconnect() {
    document.removeEventListener("click", this.onClick, true)
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("selectionchange", this.onSelection)
    window.removeEventListener("online", this.onOnline)
    window.removeEventListener("resize", this.onResize)
    clearTimeout(this.toastTimer)
  }

  csrf() { return document.querySelector("meta[name=csrf-token]")?.content || "" }

  // ---- the mode -----------------------------------------------------------------

  startMode() {
    this.modeValue = true
    document.body.classList.add("comment-mode")
    this.bannerTarget.hidden = false
    this.bannerTarget.querySelector("button")?.focus()
  }

  endMode() {
    this.modeValue = false
    document.body.classList.remove("comment-mode")
    this.bannerTarget.hidden = true
    this.opener?.focus?.()
  }

  documentClick(event) {
    const opener = event.target.closest?.("[data-comment-open]")
    if (opener) {
      event.preventDefault()
      event.stopPropagation()
      this.opener = opener
      if (!this.modeValue) this.startMode()
      return
    }
    if (!this.modeValue || this.boxOpen) return
    if (event.target.closest?.("[data-comment-ui]")) return
    // a tap in the comment mode picks, it does not act on the page
    event.preventDefault()
    event.stopPropagation()
    this.openBox(event.target)
  }

  wholePage() { this.openBox(null) }
  chooseFromList() { this.openBox(null, { focusList: true }) }

  // ---- the box ------------------------------------------------------------------

  rememberSelection() {
    const text = window.getSelection?.()?.toString() ?? ""
    if (text.trim() && !this.dialogTarget.contains(window.getSelection().anchorNode)) this.lastSelection = clip(text, SELECTED_MAX)
  }

  openBox(node, { focusList = false } = {}) {
    this.places = listTargets(document.querySelector("main") || document.body, this.labelsValue.whole_page).slice(0, 80)
    this.picked = node ? { node, anchor: anchorPath(node, null) } : null
    this.whereTarget.replaceChildren(...this.places.map((t, i) => new Option(this.nameOf(t), String(i))))
    const index = this.picked ? this.places.findIndex((t) => t.anchor === this.picked.anchor) : 0
    this.whereTarget.value = String(Math.max(index, 0))
    if (this.picked && index < 0) this.whereTarget.prepend(new Option(this.nameOf(this.picked) || this.labelsValue.whole_page, "picked", true, true))
    this.selectedTarget.textContent = this.lastSelection
    this.selectedTarget.closest("p").hidden = !this.lastSelection
    this.includeSelectedTarget.checked = true
    this.textTarget.value = ""
    this.updateCount()
    this.statusTarget.textContent = ""
    this.reasonTargets.forEach((radio) => { radio.checked = false })
    this.clockNoteTarget.hidden = !this.eventsUrlValue
    this.boxOpen = true
    this.dialogTarget.removeAttribute("data-placed")
    this.dialogTarget.style.cssText = ""
    this.dialogTarget.showModal()
    this.placeChanged()
    if (this.eventsUrlValue) this.postEvent("comment_opened")
    ;(focusList ? this.whereTarget : this.reasonTargets[0])?.focus()
  }

  // The words for a place: its name from the anchor ("Scheda 3 · Blocco 2"), plus the start of its text.
  nameOf(target) {
    if (!target.anchor) return this.labelsValue.whole_page
    const name = describeAnchor(target.anchor, this.labelsValue.anchors)
    const label = target.label && target.label !== target.anchor ? clip(target.label, 30) : ""
    return [name, label].filter(Boolean).join(" · ") || target.anchor
  }

  // The part chosen is echoed in the box: its name above (the list), a short excerpt of its words under it, and the part stays
  // outlined on the page behind the box.
  placeChanged() {
    const place = this.currentPlace()
    document.querySelectorAll(".comment-picked").forEach((n) => n.classList.remove("comment-picked"))
    place.node?.classList?.add("comment-picked")
    const excerpt = place.node ? clip(place.node.textContent, 90) : clip(document.title, 90)
    this.excerptTarget.textContent = excerpt
    this.excerptTarget.hidden = !excerpt
    this.placeBox()
  }

  // On a wide screen the card sits next to the chosen part (below it when there is room, else above), clamped to the window; on a
  // phone the CSS makes it a sheet at the bottom and nothing is placed.
  placeBox() {
    const box = this.dialogTarget
    const node = this.currentPlace().node
    const reset = () => { box.removeAttribute("data-placed"); box.style.cssText = "" }
    if (!box.open || window.innerWidth <= 640 || !node?.getBoundingClientRect) return reset()
    const rect = node.getBoundingClientRect()
    if (rect.width === 0 && rect.height === 0) return reset()
    box.setAttribute("data-placed", "")
    const gap = 16
    const width = box.offsetWidth
    const height = box.offsetHeight
    const below = window.innerHeight - rect.bottom
    let top = below >= height + gap ? rect.bottom + gap : rect.top >= height + gap ? rect.top - height - gap : (window.innerHeight - height) / 2
    top = Math.min(Math.max(gap, top), Math.max(gap, window.innerHeight - height - gap))
    const left = Math.min(Math.max(gap, rect.left), Math.max(gap, window.innerWidth - width - gap))
    box.style.top = `${Math.round(top)}px`
    box.style.left = `${Math.round(left)}px`
  }

  // The dialog closed (cancel, Escape or after a send): the counted time runs again and the mode is over.
  boxClosed() {
    if (!this.boxOpen) return
    this.boxOpen = false
    document.querySelectorAll(".comment-picked").forEach((n) => n.classList.remove("comment-picked"))
    if (this.eventsUrlValue) this.postEvent("comment_closed")
    this.lastSelection = ""
    this.endMode()
  }

  cancel(event) {
    event?.preventDefault()
    if (this.dialogTarget.open) this.dialogTarget.close()
    else this.endMode()
  }

  updateCount() { this.countTarget.textContent = this.labelsValue.chars.replace("%{n}", String(this.textTarget.value.length)).replace("%{max}", String(TEXT_MAX)) }

  currentPlace() {
    const value = this.whereTarget.value
    const chosen = value === "picked" ? this.picked : this.places[Number(value)]
    if (!chosen || (!chosen.node && value !== "picked")) return { node: null, anchor: null }
    return { node: chosen.node, anchor: chosen.anchor }
  }

  async send(event) {
    event.preventDefault()
    const reason = this.reasonTargets.find((radio) => radio.checked)?.value
    if (!reason) { this.statusTarget.textContent = this.labelsValue.reason_required; this.reasonTargets[0]?.focus(); return }
    const place = this.currentPlace()
    this.pendingId ||= newId()
    const html = document.documentElement
    const payload = buildComment({
      id: this.pendingId, reason, text: this.textTarget.value, selected: this.includeSelectedTarget.checked ? this.lastSelection : "", anchor: place.anchor,
      refs: refsOf(place.node, document), pagePath: this.pagePathValue || window.location.pathname,
      viewport: { width: window.innerWidth, height: window.innerHeight }, theme: html.dataset.theme, size: html.dataset.size
    })
    if (payload.error) { this.statusTarget.textContent = this.labelsValue.error; return }
    this.outbox.add({ ...payload, client_attempt_id: payload.client_comment_id })
    this.pendingId = null
    const flushed = await this.outbox.flush()
    this.dialogTarget.close()
    this.announce(flushed.blocked ? this.labelsValue.queued : this.labelsValue.sent, flushed.blocked)
  }

  async flush() {
    if (this.outbox.size === 0) return
    const flushed = await this.outbox.flush()
    if (!flushed.blocked) this.announce(this.labelsValue.sent)
  }

  // The confirmation: a pill that shows for a few seconds and fades; it is also the live region for a screen reader.
  announce(text, queued = false) {
    const live = this.element.querySelector("[data-comment-live]")
    if (live) live.textContent = text
    if (!this.hasToastTarget) return
    this.toastTarget.classList.toggle("queued", queued)
    this.toastTarget.classList.add("show")
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => this.toastTarget.classList.remove("show"), 3500)
  }

  async postEvent(kind) {
    try {
      await fetch(this.eventsUrlValue, {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": this.csrf() },
        body: JSON.stringify({ kind })
      })
    } catch (_error) {
      // offline: the interval stays open until the next item is served, which closes it
    }
  }
}
