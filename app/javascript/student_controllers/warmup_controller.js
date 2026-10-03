import { Controller } from "@hotwired/stimulus"
import { DONT_KNOW, el } from "items/dom"
import { renderItem } from "items/render"

// The warm-up, "prova dei comandi" (B-11): one task per component, then Pausa,
// "Non lo so", the decimal comma, accents and the editor. It does not count and
// never fails: a wrong answer says "Riprova" at once. The server grades each answer
// (Diagnosis::Warmup) and the editor tasks give up after three tries.
export default class extends Controller {
  static targets = ["stage", "step", "itemBox", "sendButton", "unknownButton", "pauseButton", "resumeButton", "status",
                    "done", "doneText"]
  static values = { tasksUrl: String, answerUrl: String, completeUrl: String, listUrl: String, texts: Object }

  async connect() {
    this.texts = this.textsValue
    const reply = await this.get(this.tasksUrlValue)
    if (!reply) return
    this.tasks = reply.tasks
    this.done = new Set(reply.done)
    this.fallback = false
    this.stageTarget.hidden = false
    await this.next()
  }

  csrf() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }

  async next() {
    const index = this.tasks.findIndex((task) => !this.done.has(task.id))
    if (index < 0) return this.finish()
    this.task = this.tasks[index]
    this.stepTarget.textContent = this.texts.warmup_step.replace("%{n}", index + 1).replace("%{total}", this.tasks.length)
    this.statusTarget.textContent = ""
    this.itemBoxTarget.textContent = ""
    const kind = this.task.component
    this.sendButtonTarget.hidden = kind === "dont_know" || kind === "pause"
    this.unknownButtonTarget.hidden = kind !== "dont_know"
    this.pauseButtonTarget.hidden = kind !== "pause"
    this.resumeButtonTarget.hidden = true
    this.handle = null
    const box = el("div", { class: "prompt" }, el("p", { text: this.task.prompt_it }))
    this.itemBoxTarget.appendChild(box)
    if (kind !== "dont_know" && kind !== "pause") {
      const part = this.partFor(this.task)
      this.handle = await renderItem(part, { t: this.texts })
      this.itemBoxTarget.appendChild(this.handle.element)
      this.handle.mounted()
      this.handle.focus()
    }
    return null
  }

  partFor(task) {
    const display = task.display || {}
    return {
      component: task.component, options: display.options, elements: display.elements, left: display.left,
      right: display.right, accents: task.accents, input: this.fallback ? "text" : "mathlive"
    }
  }

  async send() {
    if (!this.handle) return
    if (this.handle.isEmpty()) return this.show(this.texts.retry)
    return this.answer(this.handle.raw())
  }

  dontKnow() {
    return this.answer(DONT_KNOW)
  }

  pause() {
    this.pauseButtonTarget.hidden = true
    this.resumeButtonTarget.hidden = false
    this.statusTarget.textContent = this.texts.warmup_paused
  }

  resume() {
    this.resumeButtonTarget.hidden = true
    this.statusTarget.textContent = ""
    return this.answer("done")
  }

  async answer(raw) {
    const reply = await this.post(this.answerUrlValue, { task_id: this.task.id, raw })
    if (!reply) return null
    if (reply.status === "right" || reply.status === "skip") {
      if (reply.status === "skip") this.fallback = true
      this.done.add(this.task.id)
      this.show(reply.status === "right" ? this.texts.warmup_right : this.texts.warmup_skip)
      await new Promise((resolve) => setTimeout(resolve, 500))
      return this.next()
    }
    return this.show(this.texts.retry)
  }

  async finish() {
    await this.post(this.completeUrlValue, {})
    this.stageTarget.hidden = true
    this.doneTarget.hidden = false
    if (this.fallback) this.doneTextTarget.textContent = `${this.doneTextTarget.textContent} ${this.texts.warmup_fallback_note}`
  }

  show(text) {
    this.statusTarget.textContent = text
    return null
  }

  async get(url) {
    return this.request(url, { method: "GET" })
  }

  async post(url, body) {
    return this.request(url, { method: "POST", body: JSON.stringify(body) })
  }

  async request(url, options) {
    try {
      const response = await fetch(url, {
        redirect: "manual", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": this.csrf() },
        ...options
      })
      if (response.type === "opaqueredirect" || response.status !== 200) return this.show(this.texts.blocked)
      return await response.json()
    } catch (_error) {
      return this.show(this.texts.blocked)
    }
  }
}
