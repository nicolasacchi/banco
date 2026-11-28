import { Controller } from "@hotwired/stimulus"
import { Outbox, WRITING_PREFIX, newId } from "items/outbox"
import { TEXT_MAX, check, countWords, draftKey } from "items/writing"

// «Scrivi tu» (D-407): one writing task. The student writes a text of his own, the draft stays in localStorage (banco.wdraft.<item>) so a reload or a
// closed tab loses nothing, a live word count runs under the box, and «Consegna» posts to /topics/:topic/writings through its own outbox
// (banco.woutbox.<item revision>.): the text is written there before it is posted and leaves only when the server says it has recorded it (or has
// refused it), and a resend carries the same client_writing_id, so a text that did arrive is never stored twice. After it is recorded the text is read-only
// and says «Consegnato. Lo corregge il docente.»; a corrected text shows the teacher's words under it (server drawn) and «Scrivi una nuova versione»
// opens a new box. Nothing here is graded and no model answers (firm rule 1): the teacher corrects.
export default class extends Controller {
  static targets = ["form", "text", "count", "chars", "status", "send", "cancel", "sent", "sentText", "note", "correction", "again"]
  static values = { url: String, itemRevision: Number, itemKey: String, preview: Boolean, last: String, labels: Object }

  connect() {
    this.sending = false
    this.outbox = new Outbox({ url: this.urlValue, csrf: () => document.querySelector("meta[name=csrf-token]")?.content || "", prefix: `${WRITING_PREFIX}${this.itemRevisionValue}.`,
                               idField: "client_writing_id", fields: ["client_writing_id", "item_revision_id", "text"], httpStatuses: [200, 422] })
    this.storage = safeStorage()
    if (this.hasFormTarget && !this.formTarget.hidden) this.restore()
    this.count()
    // a text that was written to the outbox and never answered (a reload in the middle of a send) is sent again, with the same id
    const waiting = this.outbox.pending()[0]
    if (waiting && this.hasFormTarget) {
      this.textTarget.value = waiting.text
      this.count()
      this.deliver()
    }
  }

  // ---- the draft ----------------------------------------------------------------------------

  get draftKey() { return draftKey(this.itemKeyValue, this.previewValue) }

  restore() {
    const draft = this.storage?.getItem(this.draftKey)
    if (draft && !this.textTarget.value) this.textTarget.value = draft
  }

  input() {
    try {
      if (this.textTarget.value) this.storage?.setItem(this.draftKey, this.textTarget.value)
      else this.storage?.removeItem(this.draftKey)
    } catch (_error) {
      // storage full or refused: the text is still in the box
    }
    this.statusTarget.textContent = ""
    this.count()
  }

  count() {
    if (!this.hasTextTarget) return
    const words = countWords(this.textTarget.value)
    this.countTarget.textContent = words === 1 ? this.labelsValue.one : this.labelsValue.other.replace("%{count}", words)
    if (this.hasCharsTarget) this.charsTarget.textContent = this.labelsValue.chars.replace("%{n}", this.textTarget.value.length).replace("%{max}", TEXT_MAX)
  }

  // ---- sending ------------------------------------------------------------------------------

  async send(event) {
    event.preventDefault()
    if (this.sending) return
    const text = this.textTarget.value
    const problem = check(text)
    if (problem) {
      this.statusTarget.textContent = this.labelsValue[problem]
      return
    }
    const waiting = this.outbox.pending()[0]
    if (!waiting || waiting.text !== text) {
      this.outbox.pending().forEach((entry) => this.outbox.remove(entry.client_writing_id))
      this.outbox.add({ client_writing_id: newId(), item_revision_id: this.itemRevisionValue, text })
    }
    await this.deliver()
  }

  async deliver() {
    this.sending = true
    this.sendTarget.disabled = true
    this.statusTarget.textContent = this.labelsValue.sending
    const result = await this.outbox.flush()
    this.sending = false
    this.sendTarget.disabled = false
    const reply = Object.values(result.results)[0]
    if (reply?.status === "recorded") this.recorded(reply.submission)
    else if (reply?.status === "invalid") this.statusTarget.textContent = this.labelsValue[reply.error] || this.labelsValue.invalid
    else this.statusTarget.textContent = this.labelsValue.error
  }

  recorded(submission) {
    try {
      this.storage?.removeItem(this.draftKey)
    } catch (_error) {
      // nothing to do
    }
    this.sentTextTarget.textContent = submission.text
    if (this.hasCorrectionTarget) this.correctionTarget.hidden = true
    this.formTarget.hidden = true
    this.sentTarget.hidden = false
    this.againTarget.hidden = true
    this.noteTarget.textContent = this.labelsValue.sent
    this.noteTarget.focus()
    this.statusTarget.textContent = ""
    this.element.dataset.state = "sent"
  }

  // ---- a new version ------------------------------------------------------------------------

  again() {
    this.formTarget.hidden = false
    this.againTarget.hidden = true
    this.cancelTarget.hidden = false
    this.textTarget.value = this.storage?.getItem(this.draftKey) || this.lastValue
    this.count()
    this.textTarget.focus()
  }

  cancel() {
    this.formTarget.hidden = true
    this.againTarget.hidden = false
  }
}

function safeStorage() {
  try {
    const storage = window.localStorage
    storage.getItem("banco.wdraft.")
    return storage
  } catch (_error) {
    return null
  }
}
