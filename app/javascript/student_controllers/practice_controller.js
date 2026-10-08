import { Controller } from "@hotwired/stimulus"
import { Outbox, PRACTICE_PREFIX, newId } from "items/outbox"
import { renderItem } from "items/render"
import { renderInline } from "items/markup"

// The practice page (A9): one page, no Turbo. It asks the server for a serve as JSON, draws the item with the
// templates in app/javascript/items/, and posts each answer through the practice outbox (banco.poutbox.). The
// server grades and chooses every sentence; this controller only shows what it is told. The feedback sits in a
// polite live region; every step works from the keyboard and the focus goes where the next step is.
export default class extends Controller {
  static targets = ["skillState", "reason", "work", "itemBox", "hints", "hintList", "controls", "check", "hintButton", "solutionButton",
                    "feedback", "solutionBox", "nextActions"]
  static values = { topic: String, skill: String, serveUrl: String, answerUrl: String, backUrl: String, texts: Object, labels: Object }

  connect() {
    this.labels = this.labelsValue
    this.texts = this.textsValue
    this.outbox = new Outbox({
      url: this.answerUrlValue, csrf: () => this.csrf(), prefix: PRACTICE_PREFIX,
      fields: ["serve_id", "client_attempt_id", "raw", "source"], statuses: ["graded", "invalid", "closed", "not_found"],
      httpStatuses: [200, 404, 409]
    })
    this.serveId = null
    this.handle = null
    this.busy = false
    this.hintsTotal = 0
    this.hintsShown = 0
    this.start()
  }

  csrf() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }

  async start() {
    this.say(this.labels.loading)
    // An answer left in the outbox by an earlier page goes out first, on its own.
    if (this.outbox.size > 0) await this.outbox.flush()
    await this.serve(null)
  }

  // ---- serving -------------------------------------------------------------------------------------

  async serve(follow) {
    this.say(this.labels.loading)
    this.workTarget.hidden = true
    this.nextActionsTarget.hidden = true
    this.nextActionsTarget.textContent = ""
    this.solutionBoxTarget.hidden = true
    this.solutionBoxTarget.textContent = ""
    const { body } = await this.post(this.serveUrlValue, { topic: this.topicValue, skill: this.skillValue, follow })
    if (!body || body.type !== "item") return this.say(this.labels.error)
    await this.show(body)
    return null
  }

  async show(reply) {
    this.serveId = reply.serve_id
    this.itemBoxTarget.inert = false
    this.itemBoxTarget.textContent = ""
    try {
      this.handle = await renderItem(reply.item, { t: this.texts })
    } catch (error) {
      console.error(error)
      return this.say(this.labels.error)
    }
    this.itemBoxTarget.appendChild(this.handle.element)
    this.handle.mounted()
    this.showSkill(reply.skill)
    this.showReason(reply)
    this.hintsTotal = reply.hints.total
    this.hintsShown = 0
    this.hintListTarget.textContent = ""
    reply.hints.shown.forEach((h) => this.addHint(h.n, h.hint_it))
    this.updateHintButton()
    this.setQuestionServe()
    this.workTarget.hidden = false
    this.controlsTarget.hidden = false
    this.solutionButtonTarget.hidden = false
    this.setControls(true)
    this.say("")
    this.handle.focus()
    return null
  }

  showSkill(skill) {
    this.skillStateTarget.textContent = `${skill.state_it}. ${skill.why_it}`
  }

  showReason(reply) {
    const text = reply.reason_it
    this.reasonTarget.hidden = !text
    this.reasonTarget.textContent = text || ""
    this.reasonText = text
  }

  setQuestionServe() {
    const question = this.element.querySelector("[data-controller~=question]")
    if (question) question.dataset.questionServeIdValue = String(this.serveId)
  }

  // ---- answering -----------------------------------------------------------------------------------

  async check() {
    if (!this.handle || this.busy) return
    if (this.handle.isEmpty()) return this.say(this.labels.empty)
    this.setControls(false)
    this.say(this.labels.saving)
    const entry = this.outbox.add({ serve_id: this.serveId, client_attempt_id: newId(), raw: this.handle.raw(), source: this.handle.source() })
    const reply = await this.deliver(entry)
    if (!reply) return this.serve(null)
    return this.answered(reply)
  }

  // Sends the queue until the server has the answer; waits and retries when it cannot be reached.
  async deliver(entry) {
    for (;;) {
      const flushed = await this.outbox.flush()
      if (!flushed.blocked) return flushed.results[entry.client_attempt_id]
      this.say(this.labels.blocked)
      await new Promise((resolve) => setTimeout(resolve, 8000))
    }
  }

  answered(reply) {
    if (reply.status === "invalid") {
      this.say(reply.message_it)
      this.setControls(true)
      this.handle.focus()
      return null
    }
    if (reply.status === "closed" || reply.status === "not_found") {
      this.close()
      this.say(reply.message_it || this.labels.closed)
      this.showActions(["next", "back"])
      return null
    }
    const lines = [reply.message_it, reply.note_it].filter(Boolean)
    if (reply.skill) {
      this.showSkill(reply.skill)
      if (reply.skill.changed) lines.push(this.labels.skill_now.replace("%{state}", reply.skill.state_it.toLowerCase()))
    }
    this.say(lines.join(" "))
    if (reply.hint) this.addHint(reply.hint.n, reply.hint.hint_it)
    if (reply.solution) this.showSolution(reply.solution)
    this.applyActions(reply.actions)
    return null
  }

  // ---- hints and solution --------------------------------------------------------------------------

  async hint() {
    if (!this.serveId || this.busy) return
    const n = this.hintsShown + 1
    this.setControls(false)
    const { status, body } = await this.post(`/practice/serves/${this.serveId}/hint`, { n })
    if (status === 200 && body?.hint_it) {
      this.addHint(body.n, body.hint_it)
      this.hintListTarget.lastElementChild?.focus?.()
    } else if (status === 409) {
      this.close()
      this.say(body?.message_it || this.labels.closed)
      this.showActions(["next", "back"])
      return
    } else {
      this.say(this.labels.error)
    }
    this.setControls(true)
  }

  async solution() {
    if (!this.serveId || this.busy) return
    this.setControls(false)
    const { status, body } = await this.post(`/practice/serves/${this.serveId}/solution`, {})
    if (status === 200 && body?.solution) {
      this.say("")
      this.showSolution(body.solution)
      this.applyActions(body.actions)
    } else if (status === 409) {
      this.close()
      this.say(body?.message_it || this.labels.closed)
      this.showActions(["next", "back"])
    } else {
      this.say(this.labels.error)
      this.setControls(true)
    }
  }

  addHint(n, text) {
    if (n <= this.hintsShown) return
    this.hintsShown = n
    this.hintsTarget.hidden = false
    const li = document.createElement("li")
    li.tabIndex = -1
    renderInline(text, li)
    this.hintListTarget.appendChild(li)
    this.updateHintButton()
  }

  updateHintButton() {
    const left = this.hintsShown < this.hintsTotal
    this.hintButtonTarget.hidden = !left
    this.hintsTarget.hidden = this.hintsShown === 0
    if (left) this.hintButtonTarget.textContent = this.labels.hint.replace("%{n}", this.hintsShown + 1).replace("%{total}", this.hintsTotal)
  }

  showSolution(solution) {
    const box = this.solutionBoxTarget
    box.textContent = ""
    const title = document.createElement("h2")
    title.textContent = this.labels.solution_title
    box.appendChild(title)
    const list = document.createElement("ol")
    for (const step of solution.steps || []) {
      const li = document.createElement("li")
      renderInline(step.text_it, li)
      if (step.math) {
        li.appendChild(document.createTextNode(" "))
        renderInline(step.math, li.appendChild(document.createElement("span")))
      }
      list.appendChild(li)
    }
    box.appendChild(list)
    if (solution.final) {
      const p = document.createElement("p")
      const label = document.createElement("strong")
      label.textContent = `${this.labels.final}: `
      p.appendChild(label)
      renderInline(solution.final, p.appendChild(document.createElement("span")))
      box.appendChild(p)
    }
    box.hidden = false
  }

  // ---- what happens next ---------------------------------------------------------------------------

  // actions: retry stays on the same exercise; the others are buttons (A8.3).
  applyActions(actions) {
    const list = actions || []
    if (list.includes("retry")) {
      this.nextActionsTarget.hidden = true
      this.solutionButtonTarget.hidden = !list.includes("show_solution")
      this.setControls(true)
      this.updateHintButton()
      this.handle.focus()
    } else {
      this.close()
      this.showActions(list)
    }
  }

  // The exercise is over: its input and helps are put away.
  close() {
    this.itemBoxTarget.inert = true
    this.controlsTarget.hidden = true
    this.hintButtonTarget.hidden = true
  }

  showActions(actions) {
    const box = this.nextActionsTarget
    box.textContent = ""
    const make = (label, handler, primary) => {
      const b = document.createElement("button")
      b.type = "button"
      b.className = primary ? "button" : "button secondary"
      b.textContent = label
      b.addEventListener("click", handler)
      box.appendChild(b)
      return b
    }
    const follow = (kind) => () => this.serve({ serve_id: this.serveId, kind })
    let first = null
    const keep = (b) => { first ||= b }
    for (const action of actions) {
      if (action === "prova_questo") keep(make(this.labels.try_this, follow("prova_questo"), true))
      else if (action === "after_solution") keep(make(this.labels.after_solution, follow("after_solution"), true))
      else if (action === "next") keep(make(this.labels.next, () => this.serve(null), !actions.includes("prova_questo") && !actions.includes("after_solution")))
      else if (action === "show_solution") keep(make(this.labels.solution, () => this.solution(), false))
    }
    if (actions.includes("back")) {
      const a = document.createElement("a")
      a.className = "button secondary"
      a.href = this.backUrlValue
      a.textContent = this.labels.back
      box.appendChild(a)
      keep(a)
    }
    box.hidden = false
    first?.focus()
  }

  // ---- helpers -------------------------------------------------------------------------------------

  setControls(enabled) {
    this.busy = !enabled
    this.checkTarget.disabled = !enabled
    this.hintButtonTarget.disabled = !enabled
    this.solutionButtonTarget.disabled = !enabled
  }

  say(text) {
    this.feedbackTarget.textContent = text || ""
  }

  // POST JSON; {status, body} with body null when the reply is not JSON, is a redirect or the network is down.
  async post(url, payload) {
    try {
      const response = await fetch(url, {
        method: "POST", redirect: "manual", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": this.csrf() },
        body: JSON.stringify(payload)
      })
      if (response.type === "opaqueredirect") return { status: 0, body: null }
      if (!(response.headers.get("content-type") || "").includes("json")) return { status: response.status, body: null }
      return { status: response.status, body: await response.json() }
    } catch (_error) {
      return { status: 0, body: null }
    }
  }
}
