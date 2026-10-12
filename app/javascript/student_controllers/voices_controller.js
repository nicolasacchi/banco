import { Controller } from "@hotwired/stimulus"

// "Prova le voci" (D-282, the operator's Q1): on the student's own Mac or iPad, with Safari, each local voice of the device says a fixed sentence
// with its name beside it. The operator listens once and tells which voices are good; their names go into config/banco/voices.yml and only then do
// the lessons show a speaker. Nothing is recorded and nothing is sent: the page only plays.
export default class extends Controller {
  static targets = ["list"]
  static values = { labels: Object }

  async connect() {
    this.speech = await import("lesson/speech")
    this.device = await import("lesson/speech_device")
    this.stopWatching = this.device.onChange(() => this.draw())
    this.draw()
  }

  disconnect() {
    this.stopWatching?.()
    this.speech?.stopAll()
  }

  draw() {
    const t = this.labelsValue
    const voices = this.device.localVoices()
    this.listTarget.replaceChildren()
    if (voices.length === 0) {
      const p = document.createElement("p")
      p.className = "hint"
      p.textContent = t.none
      this.listTarget.appendChild(p)
      return
    }
    for (const language of ["it", "en", "es"]) {
      const mine = voices.filter((v) => v.language === language)
      if (mine.length === 0) continue
      const group = document.createElement("section")
      group.className = "voice-group"
      const h = document.createElement("h3")
      h.textContent = t[`language_${language}`]
      const ul = document.createElement("ul")
      ul.className = "voice-list"
      for (const v of mine) ul.appendChild(this.row(v, t, language))
      group.append(h, ul)
      this.listTarget.appendChild(group)
    }
  }

  row(v, t, language) {
    const li = document.createElement("li")
    li.className = "voice-row"
    const name = document.createElement("span")
    name.className = "voice-name"
    name.textContent = `${v.name} (${v.lang})`
    const status = document.createElement("span")
    status.className = "voice-status"
    status.textContent = v.accepted ? t.accepted : t.not_accepted
    const button = document.createElement("button")
    button.type = "button"
    button.className = "button secondary small"
    button.setAttribute("aria-pressed", "false")
    button.textContent = t.try
    button.addEventListener("click", () => {
      if (button.getAttribute("aria-pressed") === "true") {
        this.speech.stopAll()
        return
      }
      button.setAttribute("aria-pressed", "true")
      button.textContent = t.stop
      const done = () => {
        button.setAttribute("aria-pressed", "false")
        button.textContent = t.try
      }
      this.speech.speak([{ lang: language, text: t.sentences[language] }], { voice: v.voice, onEnd: done })
    })
    li.append(name, status, button)
    return li
  }
}
