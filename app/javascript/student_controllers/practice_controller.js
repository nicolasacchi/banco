import { Controller } from "@hotwired/stimulus"
import { Outbox, PRACTICE_PREFIX, newId } from "items/outbox"
import { practiceUrls } from "items/practice_urls"
import { Refusals } from "items/refusals"
import { showRefusalNotice } from "items/refusal_notice"
import { renderItem } from "items/render"
import { renderInline } from "items/markup"
import { spriteUrl } from "lesson/sprite"

// The practice page (A9): one page, no Turbo. It asks the server for a serve as JSON, draws the item with the
// templates in app/javascript/items/, and posts each answer through the practice outbox (banco.poutbox.). The
// server grades and chooses every sentence; this controller only shows what it is told. The feedback sits in a
// polite live region; every step works from the keyboard and the focus goes where the next step is.
const SPRITE = spriteUrl()
// The tone of a feedback notice by the grader's outcome (D-307): never red and green; the words come from the server.
const TONES = { correct: "success", correct_aided: "success", near_miss: "nearly", typical_error: "error", unrecognised: "error", form: "error", undetermined: "info" }
const TONE_ICONS = { success: "circle-check", nearly: "triangle-alert", error: "alert", info: "info", hint: "wrong-hint" }
// The statuses of an exercise in the list (D-337): an icon from the sprite, a tone and the word, so colour is never alone.
const ENTRY_STATUS = {
  todo: { icon: "step-practice", tone: "muted" },
  done: { icon: "circle-check", tone: "success" },
  finished: { icon: "circle-check", tone: "muted" },
  finished_solution: { icon: "circle-check", tone: "muted" },
  unfinished: { icon: "notebook-pen", tone: "nearly" },
  skipped: { icon: "next", tone: "muted" },
  now: { icon: "pin", tone: "info" }
}
const FINISHED_STATUSES = ["done", "finished", "finished_solution"]
const DRAFT_WAIT_MS = 1500
const DRAFT_TIMEOUT_MS = 4000
const STATE_TONES = { demonstrated: "success", consolidated: "success", in_study: "info", to_recover: "nearly", to_review: "nearly", to_learn: "nearly", not_seen: "muted" }

export default class extends Controller {
  static targets = ["skillState", "skillWhy", "skillMissing", "dots", "reason", "reminder", "work", "itemBox", "hints", "hintList", "controls", "check", "hintButton", "solutionButton",
                    "feedback", "solutionBox", "nextActions", "done", "doneTitle", "doneOffer", "doneActions", "skip", "list", "listPanel", "listCount", "listBody"]
  static values = { topic: String, skill: String, baseUrl: String, backUrl: String, texts: Object, labels: Object }

  connect() {
    this.labels = this.labelsValue
    this.texts = this.textsValue
    this.urls = practiceUrls(this.baseUrlValue)
    this.outbox = new Outbox({
      url: this.urls.answer, csrf: () => this.csrf(), prefix: PRACTICE_PREFIX,
      fields: ["serve_id", "client_attempt_id", "raw", "source"], statuses: ["graded", "invalid", "same_answer", "closed", "not_found"],
      httpStatuses: [200, 404, 409]
    })
    this.serveId = null
    this.itemKey = null
    this.handle = null
    this.refusals = new Refusals()
    this.busy = false
    this.hintsTotal = 0
    this.hintsShown = 0
    this.serving = false
    this.contesting = false
    // The half-typed answer (D-337): `drafting` while the open exercise may take a draft; `lastSaved` is what the server holds
    // (null after a try: the tried answer then goes up as a newer draft).
    this.drafting = false
    this.lastSaved = ""
    this.draftTimer = null
    this.draftChain = Promise.resolve()
    this.listSeq = 0
    this.doneOpen = new Set() // the skills whose «Già fatti» the student opened
    this.leaveSave = () => { this.saveDraft({ keepalive: true }) }
    this.hiddenSave = () => { if (document.visibilityState === "hidden") this.saveDraft({ keepalive: true }) }
    window.addEventListener("pagehide", this.leaveSave)
    document.addEventListener("visibilitychange", this.hiddenSave)
    // The list is open when the page has two columns and closed on a phone: student.css decides (a container query in rem, so it
    // follows the text size) and the layout's own display says which one is on.
    this.wideLayout = () => window.getComputedStyle(this.listTarget.parentElement).display === "grid"
    this.wasWide = null
    this.sizeList = () => {
      const wide = this.wideLayout()
      if (wide === this.wasWide) return
      this.wasWide = wide
      this.listPanelTarget.open = wide
    }
    this.sizeList()
    this.resizer = new ResizeObserver(this.sizeList)
    this.resizer.observe(this.element)
    this.start()
  }

  disconnect() {
    clearTimeout(this.draftTimer)
    window.removeEventListener("pagehide", this.leaveSave)
    document.removeEventListener("visibilitychange", this.hiddenSave)
    this.resizer?.disconnect()
  }

  csrf() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }

  async start() {
    this.say(this.labels.loading)
    // An answer left in the outbox by an earlier page goes out first, on its own; the page was away, so its verdict is told
    // once the exercise is on the screen.
    const left = this.outbox.size > 0 ? Object.values((await this.outbox.flush()).results).filter((reply) => reply?.status === "graded").pop() : null
    // `?item=KEY` (a link from the list of another skill) opens that exercise once; a reload then resumes the last one.
    const url = new URL(window.location.href)
    const item = url.searchParams.get("item")
    await this.serve(item ? { item } : {})
    if (item) {
      url.searchParams.delete("item")
      window.history.replaceState(window.history.state, "", url)
    }
    if (left && !this.workTarget.hidden) this.sayEarlier(left)
  }

  // The verdict of the answer the last page left behind, above the exercise now served: the notice with a title of its own.
  sayEarlier(reply) {
    const right = reply.outcome === "correct" || reply.outcome === "correct_aided"
    const tone = right && reply.note_it ? "nearly" : (TONES[reply.outcome] || "info")
    this.say(reply.message_it, { tone, title: this.labels.earlier, note: [reply.note_it, reply.count_it].filter(Boolean).join(" ") })
  }

  // ---- serving -------------------------------------------------------------------------------------

  // `extra` is what the request adds to {topic, skill}: {item}, {advance: true} or {follow}; nothing resumes the last exercise.
  // The half-typed answer of the exercise being left goes up first.
  async serve(extra = {}) {
    if (this.serving) return null
    this.serving = true
    try {
      await this.saveDraft()
      return await this.serveNow(extra)
    } finally {
      this.serving = false
    }
  }

  async serveNow(extra) {
    this.drafting = false
    this.say(this.labels.loading)
    this.workTarget.hidden = true
    this.nextActionsTarget.hidden = true
    this.doneTarget.hidden = true
    this.hideRating()
    this.nextActionsTarget.textContent = ""
    this.solutionBoxTarget.hidden = true
    this.solutionBoxTarget.textContent = ""
    const { body } = await this.post(this.urls.serve, { topic: this.topicValue, skill: this.skillValue, ...extra })
    if (body?.type === "exhausted") return this.showExhausted(body)
    if (body?.type === "topic_done") return this.showTopicDone(body)
    if (!body || body.type !== "item") return this.say(this.labels.error)
    await this.show(body)
    return null
  }

  // D-348: every exercise of the skill was seen and none is open, so none is served on its own. The page says it; the list of exercises
  // (a click redoes one) and the way back stay.
  showExhausted(reply) {
    this.serveId = null
    this.hideRating()
    this.handle = null
    this.showSkill(reply.skill)
    this.showReason({})
    this.say(reply.message_it, { tone: "info", note: reply.note_it })
    this.showActions(["back"])
    this.refreshList()
    return null
  }

  // D-366: every skill of the topic is demonstrated, so no exercise is served on its own: the page closes the topic. The words, the next topic and the
  // addresses come from the server (the same next topic as Oggi's, the preview's root); it speaks of this topic only. The list of exercises stays
  // (a click redoes one, as before); the slot `#topic-done-extra` after the buttons is left alone for a later link.
  showTopicDone(reply) {
    this.serveId = null
    this.itemKey = null
    this.hideRating()
    this.handle = null
    this.showSkill(reply.skill)
    this.showReason({})
    this.say("")
    this.doneTitleTarget.textContent = reply.title_it
    const offer = this.doneOfferTarget
    offer.textContent = ""
    offer.hidden = !(reply.next && reply.offer_it)
    if (!offer.hidden) offer.append(`${reply.offer_it} `, Object.assign(document.createElement("strong"), { className: "topic-done-next", textContent: reply.next.title_it }))
    const actions = this.doneActionsTarget
    actions.textContent = ""
    const link = (spec, primary) => {
      const a = document.createElement("a")
      a.className = primary ? "button" : "button secondary"
      a.href = spec.url
      a.textContent = spec.label_it
      actions.appendChild(a)
    }
    if (reply.next) link(reply.next, true)
    link(reply.today, !reply.next)
    this.doneTarget.hidden = false
    this.doneTitleTarget.focus()
    this.refreshList()
    return null
  }

  async show(reply) {
    this.serveId = reply.serve_id
    this.ratingCurrent = reply.rating ?? null // his latest rating of this exercise, for the box that opens when it is over (D-365)
    this.hideRating()
    this.itemKey = reply.exercise?.item ?? null // the exercise on the page keeps its place in the list when it is answered and closed
    // "Commenta" (D-304): a comment on this exercise names the serve; the server checks it is this student's.
    this.itemBoxTarget.dataset.commentServeId = String(reply.serve_id)
    this.itemFormat = reply.item?.answer_format_it
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
    this.showReminder(reply)
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
    this.drafting = true
    this.lastSaved = ""
    this.restoreDraft(reply.draft)
    this.refreshList()
    return null
  }

  // What the student had typed on this exercise, put back with a word about it.
  restoreDraft(draft) {
    if (!draft || typeof draft.raw !== "string" || draft.raw === "") return
    try {
      this.handle.restore(draft.raw)
    } catch (error) {
      console.error(error)
      return
    }
    this.lastSaved = draft.raw
    this.say(this.labels.draft_restored)
  }

  // The state pill, the three dots (corrections without help, while the skill is "in studio") and the sentence of why.
  showSkill(skill) {
    this.skillStateTarget.textContent = skill.state_it
    this.skillStateTarget.className = `pill ${STATE_TONES[skill.state] || "muted"}`
    this.skillWhyTarget.textContent = skill.why_it
    this.skillMissingTarget.textContent = skill.missing_it || ""
    this.skillMissingTarget.hidden = !skill.missing_it
    const clean = skill.clean
    this.dotsTarget.hidden = clean === null || clean === undefined
    if (!this.dotsTarget.hidden) {
      this.dotsTarget.setAttribute("aria-label", this.labels.clean_of.replace("%{n}", clean))
      Array.from(this.dotsTarget.children).forEach((dot, i) => dot.classList.toggle("on", i < clean))
    }
  }

  showReason(reply) {
    const text = reply.reason_it
    this.reasonTarget.hidden = !text
    this.reasonTarget.querySelector(".notice-body").textContent = text || ""
    this.reasonText = text
  }

  // D-358: «Ricorda: …», one quiet line above the answer when the server sent one (the item's own message for a typical error made lately).
  // Not a hint: it is not counted and not listed with the hints.
  showReminder(reply) {
    const text = reply.reminder_it
    this.reminderTarget.hidden = !text
    this.reminderTarget.textContent = ""
    if (!text) return
    const label = document.createElement("span")
    label.className = "reminder-label"
    label.textContent = this.labels.reminder_label
    this.reminderTarget.append(label, ` ${text}`)
  }

  setQuestionServe() {
    const question = this.element.querySelector("[data-controller~=question]")
    if (question) question.dataset.questionServeIdValue = String(this.serveId)
  }

  // ---- answering -----------------------------------------------------------------------------------

  async check() {
    if (!this.handle || this.busy || this.refusals.cooling(Date.now())) return
    if (this.handle.isEmpty()) return this.say(this.labels.empty)
    // «Fai controllare» may be showing: the "saving" line below wipes it, so remember it for a refusal (see `answered`).
    const hadContest = !!this.feedbackTarget.querySelector("#contest-button")
    this.setControls(false)
    this.say(this.labels.saving)
    clearTimeout(this.draftTimer)
    const entry = this.outbox.add({ serve_id: this.serveId, client_attempt_id: newId(), raw: this.handle.raw(), source: this.handle.source() })
    const reply = await this.deliver(entry)
    if (!reply) return this.serve({ advance: true })
    // The try is on the server: what stays in the box goes up as a newer draft when the student leaves it.
    this.lastSaved = null
    this.answered(reply, hadContest)
    this.refreshList()
    return null
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

  answered(reply, hadContest = false) {
    if (reply.status === "same_answer") {
      // D-353: the same answer as a try of this serve (nothing stored): said plainly, not a verdict; the box keeps the text
      const serve = this.serveId
      this.refusals.cool(Date.now())
      this.say(reply.message_it)
      this.offerContest(reply.actions)
      this.handle.focus()
      setTimeout(() => { if (this.serveId === serve && this.handle) this.setControls(true) }, this.refusals.cooldownMs)
      return null
    }
    if (reply.status === "invalid") {
      // D-298: inert for a moment, the focus stays in the box, the answer format from the second refusal of the serve
      const serve = this.serveId
      // A refusal is not a verdict: «Fai controllare» stays if it was showing (the server's message points at it).
      const keepContest = hadContest
      this.refusals.record(serve, Date.now())
      if (this.refusals.showFormat(serve)) {
        this.say("")
        showRefusalNotice(this.handle, { message: reply.message_it, format: this.itemFormat })
      } else {
        this.say(reply.message_it)
      }
      this.offerContest(keepContest ? ["contest"] : reply.actions)
      this.handle.focus()
      // A matching with a row left empty marks the row (the other templates have nothing to mark).
      this.handle.showMissing?.()
      setTimeout(() => { if (this.serveId === serve && this.handle) this.setControls(true) }, this.refusals.cooldownMs)
      return null
    }
    if (reply.status === "closed" || reply.status === "not_found") {
      this.close()
      this.say(reply.message_it || this.labels.closed)
      this.showActions(["next", "back"])
      return null
    }
    const extra = []
    if (reply.skill) {
      this.showSkill(reply.skill)
      if (reply.skill.changed) extra.push(this.labels.skill_now.replace("%{state}", reply.skill.state_it.toLowerCase()))
    }
    this.sayOutcome(reply, extra)
    if (reply.hint) this.addHint(reply.hint.n, reply.hint.hint_it)
    this.offerContest(reply.actions)
    if (reply.solution) this.showSolution(reply.solution)
    this.applyActions(reply.actions)
    return null
  }

  // The verdict as a notice: the tone follows the outcome; a right answer with a note (D-301's pair, the accents) is "nearly".
  sayOutcome(reply, extra) {
    const right = reply.outcome === "correct" || reply.outcome === "correct_aided"
    let tone = TONES[reply.outcome] || "info"
    if (right && reply.note_it) tone = "nearly"
    const title = tone === "nearly" && !right ? this.labels.nearly : null
    const note = [reply.note_it, reply.count_it, ...extra].filter(Boolean).join(" ") // count_it (D-363): «Giuste: N su M.» after a try that is not right
    this.say(reply.message_it, { tone, title, note })
  }

  // ---- hints and solution --------------------------------------------------------------------------

  async hint() {
    if (!this.serveId || this.busy) return
    const n = this.hintsShown + 1
    this.setControls(false)
    const { status, body } = await this.post(this.urls.hint(this.serveId), { n })
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
    const { status, body } = await this.post(this.urls.solution(this.serveId), {})
    if (status === 200 && body?.solution) {
      this.say("")
      this.showSolution(body.solution)
      this.offerContest(body.actions)
      this.applyActions(body.actions)
      this.refreshList()
    } else if (status === 409) {
      this.close()
      this.say(body?.message_it || this.labels.closed)
      this.showActions(["next", "back"])
    } else {
      this.say(this.labels.error)
      this.setControls(true)
    }
  }

  // ---- «Fai controllare» ---------------------------------------------------------------------------

  // Under the feedback: a smaller line and a text button, when the server says this answer may go to the teacher. They live
  // inside the feedback element, so the next `say` takes them away; a refusal puts them back when they were showing (see `answered`).
  offerContest(actions) {
    if (!Array.isArray(actions) || !actions.includes("contest")) return
    const inside = this.feedbackTarget.querySelector(".notice-body") || this.feedbackTarget
    const box = document.createElement("div")
    box.className = "contest"
    const note = document.createElement("p")
    note.className = "contest-note"
    note.textContent = this.labels.contest_note
    const button = document.createElement("button")
    button.type = "button"
    button.id = "contest-button"
    button.className = "button text small contest-button"
    button.textContent = this.labels.contest_button
    button.addEventListener("click", () => this.contest(button))
    box.append(note, button)
    inside.appendChild(box)
  }

  // The answer goes to the teacher: the exercise is closed, the solution and the way on are shown, the list is drawn again.
  async contest(button) {
    if (!this.serveId || this.contesting) return
    const serve = this.serveId
    this.contesting = true
    button.disabled = true
    this.setControls(false)
    try {
      const { status, body } = await this.post(this.urls.contest(serve), {})
      if (serve !== this.serveId) return
      if (status === 200 && body?.status === "contested") {
        this.close()
        this.say(body.message_it, { tone: "info" })
        if (body.solution) this.showSolution(body.solution)
        this.showActions(body.actions || ["next", "back"])
        this.refreshList()
      } else if (status === 409) {
        this.close()
        this.say(this.labels.closed)
        this.showActions(["next", "back"])
      } else {
        this.setControls(true)
        this.say(this.labels.error)
        this.offerContest(["contest"])
      }
    } finally {
      this.contesting = false
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
    this.busy = false
    this.drafting = false
    clearTimeout(this.draftTimer)
    this.itemBoxTarget.inert = true
    this.controlsTarget.hidden = true
    this.hintButtonTarget.hidden = true
    this.showRating()
  }

  // «Ti è piaciuto questo esercizio?» (D-365): the box under the exercise opens once it is over (right, solution shown, tries used up, sent
  // to the teacher) and goes away with the exercise. Opened once per serve: a second close of the same serve (a contest after the
  // verdict) leaves it as the student has it. The server checks again that the serve is his and over. Not on the preview's page.
  ratingBox() { return this.element.querySelector("#rating-box") }

  hideRating() {
    const box = this.ratingBox()
    if (box) box.hidden = true
  }

  showRating() {
    const box = this.ratingBox()
    if (!box || !box.hidden || !this.serveId) return
    box.dataset.ratingCurrentValue = JSON.stringify(this.ratingCurrent || {})
    box.dataset.ratingServeValue = String(this.serveId)
    box.hidden = false
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
    const follow = (kind) => () => this.serve({ follow: { serve_id: this.serveId, kind } })
    let first = null
    const keep = (b) => { first ||= b }
    for (const action of actions) {
      if (action === "prova_questo") keep(make(this.labels.try_this, follow("prova_questo"), true))
      else if (action === "after_solution") keep(make(this.labels.after_solution, follow("after_solution"), true))
      else if (action === "next") keep(make(this.labels.next, () => this.serve({ advance: true }), !actions.includes("prova_questo") && !actions.includes("after_solution")))
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

  // ---- skipping and the half-typed answer (D-337) --------------------------------------------------

  // «Salta»: the draft is saved, the exercise stays open on the server, the next one is served.
  skip() {
    if (!this.serveId || this.busy) return null
    return this.serve({ advance: true })
  }

  // Any change of the answer (the items send a bubbling item-change): saved after a pause.
  changed() {
    if (!this.drafting) return
    clearTimeout(this.draftTimer)
    this.draftTimer = setTimeout(() => this.saveDraft(), DRAFT_WAIT_MS)
  }

  // Sends the draft when it differs from what the server holds. A page that is going away sends it with keepalive and cannot wait.
  saveDraft({ keepalive = false } = {}) {
    clearTimeout(this.draftTimer)
    if (!this.drafting || !this.handle || !this.serveId) return Promise.resolve()
    const raw = this.handle.draft()
    if (typeof raw !== "string" || raw === this.lastSaved || (this.lastSaved === null && raw === "")) return Promise.resolve()
    const serve = this.serveId
    const payload = { raw, source: this.handle.source() }
    const send = async () => {
      const { status, body } = await this.post(this.urls.draft(serve), payload, keepalive ? { keepalive: true } : { timeout: DRAFT_TIMEOUT_MS })
      if (serve !== this.serveId) return
      if (status === 200 && (body?.status === "saved" || body?.status === "unchanged")) this.lastSaved = raw
      else if (status === 409) this.drafting = false
    }
    if (keepalive) {
      send()
      return Promise.resolve()
    }
    this.draftChain = this.draftChain.then(send, send)
    return this.draftChain
  }

  // ---- the list of exercises -----------------------------------------------------------------------

  // Fetched again after every serve, answer, solution and skip; a failed or late reply leaves the list as it is.
  async refreshList() {
    const seq = ++this.listSeq
    let body
    try {
      const response = await fetch(this.urls.exercises(this.topicValue), { credentials: "same-origin", headers: { Accept: "application/json" } })
      if (!response.ok) return
      body = await response.json()
    } catch (_error) {
      return
    }
    if (seq !== this.listSeq || !Array.isArray(body?.skills)) return
    this.drawList(body.skills)
  }

  drawList(skills) {
    const body = this.listBodyTarget
    const focused = body.contains(document.activeElement) ? document.activeElement.closest("li")?.dataset : null
    body.textContent = ""
    let total = 0
    let done = 0
    for (const skill of skills) {
      const exercises = skill.exercises || []
      if (exercises.length === 0) continue
      const group = document.createElement("section")
      group.className = "exercise-group"
      if (skills.length > 1) {
        const heading = document.createElement("h3")
        heading.className = "exercise-skill"
        heading.textContent = skill.label_it
        group.appendChild(heading)
      }
      // D-353: what is still to do comes first; what is done or finished goes into one closed «Già fatti (N)» at the end, still clickable.
      // The exercise on the page stays up with the first ones whatever its status, answered and closed included.
      const first = []
      const finished = []
      for (const exercise of exercises) {
        total += 1
        if (exercise.status === "done") done += 1
        const onPage = skill.key === this.skillValue && this.serveId != null && exercise.item === this.itemKey
        ;(!onPage && FINISHED_STATUSES.includes(exercise.status) ? finished : first).push(exercise)
      }
      if (first.length > 0) group.appendChild(this.entries(skill, first))
      if (finished.length > 0) group.appendChild(this.doneGroup(skill, finished))
      body.appendChild(group)
    }
    this.listTarget.hidden = total === 0
    const count = done === 1 ? this.labels.exercises_count_one : this.labels.exercises_count
    this.listCountTarget.textContent = count.replace("%{done}", done).replace("%{total}", total)
    if (focused) {
      const again = Array.from(body.querySelectorAll("li")).find((li) => li.dataset.skill === focused.skill && li.dataset.item === focused.item)
      again?.querySelector(".exercise-link")?.focus()
    }
  }

  entries(skill, exercises) {
    const list = document.createElement("ol")
    list.className = "exercise-entries"
    for (const exercise of exercises) list.appendChild(this.entry(skill, exercise))
    return list
  }

  // The closed group of the exercises already done or finished; it stays open or closed as the student left it while the list is drawn again.
  doneGroup(skill, exercises) {
    const details = document.createElement("details")
    details.className = "disclosure exercise-done"
    details.dataset.skill = skill.key
    details.open = this.doneOpen.has(skill.key)
    const summary = document.createElement("summary")
    summary.textContent = this.labels.done_group.replace("%{n}", exercises.length)
    details.appendChild(summary)
    details.appendChild(this.entries(skill, exercises))
    details.addEventListener("toggle", () => {
      if (details.open) this.doneOpen.add(skill.key)
      else this.doneOpen.delete(skill.key)
    })
    return details
  }

  // One exercise: a button on this skill, a link to the page of another; the status as an icon and a word.
  entry(skill, exercise) {
    const same = skill.key === this.skillValue
    const current = same && exercise.open_serve_id != null && exercise.open_serve_id === this.serveId
    const status = current ? "now" : (ENTRY_STATUS[exercise.status] ? exercise.status : "todo")
    const look = ENTRY_STATUS[status]
    const li = document.createElement("li")
    li.className = "exercise-entry"
    li.dataset.skill = skill.key
    li.dataset.item = exercise.item
    li.dataset.status = exercise.status
    let link
    if (same) {
      link = document.createElement("button")
      link.type = "button"
    } else {
      link = document.createElement("a")
      const query = new URLSearchParams({ item: exercise.item })
      link.href = `${skill.url}${skill.url.includes("?") ? "&" : "?"}${query}`
    }
    link.className = "exercise-link"
    if (current) link.setAttribute("aria-current", "true")
    const text = document.createElement("span")
    text.className = "exercise-text"
    const name = document.createElement("span")
    name.className = "exercise-n"
    name.textContent = this.labels.exercise_n.replace("%{n}", exercise.n)
    text.appendChild(name)
    if (exercise.title_it) {
      const title = document.createElement("span")
      title.className = "exercise-title"
      renderInline(exercise.title_it, title)
      text.appendChild(title)
    }
    const pill = document.createElement("span")
    pill.className = `pill exercise-status ${look.tone}`
    pill.innerHTML = `<svg class="ic" aria-hidden="true" focusable="false"><use href="${SPRITE}#${look.icon}"></use></svg>`
    pill.appendChild(document.createTextNode(status === "now" ? this.labels.now : this.labels[`status_${status}`]))
    link.append(text, pill)
    if (!current && (exercise.status === "done" || exercise.status === "finished" || exercise.status === "finished_solution")) {
      const redo = document.createElement("span")
      redo.className = "exercise-act"
      redo.textContent = this.labels.redo
      link.appendChild(redo)
    }
    link.addEventListener("click", (event) => this.pick(event, link, same, exercise, current))
    li.appendChild(link)
    return li
  }

  // A click in the list. On this skill: the exercise opens here (the draft of the one being left goes up first). On another
  // skill: the link goes to its page, after the draft is saved; a click with a modifier keeps the browser's own way.
  pick(event, link, same, exercise, current) {
    if (same) {
      if (current || this.serving || this.busy) return
      if (!this.wideLayout()) this.listPanelTarget.open = false
      this.serve({ item: exercise.item })
      return
    }
    if (event.defaultPrevented || event.button !== 0) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
      this.saveDraft({ keepalive: true })
      return
    }
    event.preventDefault()
    this.saveDraft().then(() => { window.location.assign(link.href) })
  }

  // ---- helpers -------------------------------------------------------------------------------------

  setControls(enabled) {
    this.busy = !enabled
    this.checkTarget.disabled = !enabled
    this.hintButtonTarget.disabled = !enabled
    this.solutionButtonTarget.disabled = !enabled
    this.skipTarget.disabled = !enabled
  }

  // A plain status line (loading, saving, a refusal) or, with a tone, a notice: icon, an optional short title, the sentence
  // and an optional note. The element stays the one polite live region of the page.
  say(text, { tone = null, title = null, note = null } = {}) {
    const box = this.feedbackTarget
    box.textContent = ""
    box.className = tone ? `feedback notice ${tone}` : "feedback"
    if (!tone) {
      box.textContent = text || ""
      return
    }
    const holder = document.createElement("template")
    holder.innerHTML = `<svg class="ic" aria-hidden="true" focusable="false"><use href="${SPRITE}#${TONE_ICONS[tone] || "info"}"></use></svg>`
    const icon = holder.content.firstElementChild
    const body = document.createElement("div")
    body.className = "notice-body"
    if (title) body.appendChild(Object.assign(document.createElement("span"), { className: "notice-title", textContent: title }))
    if (text) body.appendChild(Object.assign(document.createElement("span"), { className: "feedback-text", textContent: text }))
    if (note) body.appendChild(Object.assign(document.createElement("span"), { className: "feedback-note", textContent: ` ${note}` }))
    box.append(icon, body)
  }

  // POST JSON; {status, body} with body null when the reply is not JSON, is a redirect or the network is down.
  async post(url, payload, { keepalive = false, timeout = null } = {}) {
    try {
      const response = await fetch(url, {
        method: "POST", redirect: "manual", credentials: "same-origin", keepalive,
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": this.csrf() },
        body: JSON.stringify(payload),
        ...(timeout ? { signal: AbortSignal.timeout(timeout) } : {})
      })
      if (response.type === "opaqueredirect") return { status: 0, body: null }
      if (!(response.headers.get("content-type") || "").includes("json")) return { status: response.status, body: null }
      return { status: response.status, body: await response.json() }
    } catch (_error) {
      return { status: 0, body: null }
    }
  }
}
