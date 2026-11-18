import { Controller } from "@hotwired/stimulus"

// "Prova le voci" (D-283, the operator's Q1): each voice of the server (D-359) says the first sentence of the fixed sample of its language, and, on the
// student's own Mac or iPad, with Safari, each local voice of the device says the whole sentence, with its name beside it. The operator listens once and tells which voices are good; their names go into config/banco/voices.yml and only then do
// the lessons show a speaker. Nothing is recorded and nothing is sent: the page only plays.
export default class extends Controller {
  static targets = ["list"]
  static values = { labels: Object }

  async connect() {
    this.speech = await import("lesson/speech")
    this.device = await import("lesson/speech_device")
    this.state = await import("lesson/speech_state")
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
    const samples = this.state.canPlayClips() ? this.device.serverSamples(t.sentences) : []
    this.listTarget.replaceChildren()
    if (voices.length === 0 && samples.length === 0) {
      const p = document.createElement("p")
      p.className = "hint"
      p.textContent = t.none
      this.listTarget.appendChild(p)
      return
    }
    for (const language of ["it", "en", "es"]) {
      const mine = voices.filter((v) => v.language === language)
      const server = samples.filter((v) => v.lang === language)
      if (mine.length === 0 && server.length === 0) continue
      const group = document.createElement("section")
      group.className = "voice-group"
      const h = document.createElement("h3")
      h.textContent = t[`language_${language}`]
      const ul = document.createElement("ul")
      ul.className = "voice-list"
      for (const s of server) ul.appendChild(this.serverRow(s, t))
      for (const v of mine) ul.appendChild(this.row(v, t, language))
      group.append(h, ul)
      this.listTarget.appendChild(group)
    }
  }

  // A voice of the server: its sample is a clip generated ahead of time, played like the lessons' own (nothing is fetched until the tap).
  serverRow(sample, t) {
    const li = document.createElement("li")
    li.className = "voice-row voice-server"
    const name = document.createElement("span")
    name.className = "voice-name"
    name.textContent = sample.name
    const status = document.createElement("span")
    status.className = "voice-status"
    status.textContent = t.server_voice
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
      status.textContent = t.server_voice
      let played = false
      this.speech.speak([{ lang: sample.lang, text: sample.text, voice: sample.voice }], {
        device: false, // the sample of a server voice is that voice or nothing
        onSegment: () => { played = true },
        onEnd: ({ stopped }) => {
          button.setAttribute("aria-pressed", "false")
          button.textContent = t.try
          if (!played && !stopped) status.textContent = t.server_missing
        }
      })
    })
    li.append(name, status, button)
    return li
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
