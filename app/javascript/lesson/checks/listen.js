// The `listen` option of a check (D-282, WAVE2 2.11, A8): the question is heard, not read. A speaker plays the English or Spanish text with the device's
// voice; the text itself stays behind "Mostra il testo" (served, but hidden), and an answer given after the text was shown is sent as text_shown
// (the ledger keeps it, so what S did without the text can be told from what S did with it). A device with no voice for the language says so, and the
// lesson works by reading: the same button shows the text.
import { button, el, icon } from "lesson/dom"
import { speak, stopAll } from "lesson/speech"
import { hasVoice, onChange, preferences } from "lesson/speech_device"

export const listenOf = (spec) => (spec.listen?.text_en ? { lang: "en", text: spec.listen.text_en } : spec.listen?.text_es ? { lang: "es", text: spec.listen.text_es } : null)

// -> { element, shown() }
export function listenBox(spec, ctx) {
  const heard = listenOf(spec)
  if (!heard) return null
  const t = ctx.t.speech
  let shown = false
  let handle = null
  const text = el("p", { class: `listen-text lang lang-${heard.lang}`, lang: heard.lang, hidden: "", text: heard.text })
  const play = el("button", { type: "button", class: "button secondary listen-play", "aria-pressed": "false", hidden: "" }, icon("listen", "speak-ic"), el("span", { text: t.listen_sentence }))
  const toggle = button(t.show_text, { class: "button secondary small listen-show", "aria-expanded": "false" }, () => {
    const open = text.hidden
    text.hidden = !open
    toggle.setAttribute("aria-expanded", String(open))
    toggle.textContent = open ? t.hide_text : t.show_text
    if (open) shown = true // once looked at, always counted
  })
  const note = el("p", { class: "hint listen-note", hidden: "", text: t.no_voice })
  const idle = () => {
    handle = null
    play.setAttribute("aria-pressed", "false")
    play.replaceChildren(icon("listen", "speak-ic"), el("span", { text: t.listen_sentence }))
  }
  play.addEventListener("click", () => {
    if (handle) { stopAll(); return }
    play.setAttribute("aria-pressed", "true")
    play.replaceChildren(icon("listen-stop", "speak-ic"), el("span", { text: t.stop }))
    handle = speak([heard], { preview: ctx.preview, slower: preferences().slower, onEnd: idle })
  })
  const box = el("div", { class: "check-listen", "data-nospeech": "" }, el("p", { class: "listen-lead", text: t.listen_check }), el("div", { class: "listen-buttons" }, play, toggle), note, text)
  let seen = false
  const refresh = () => {
    if (box.isConnected) seen = true
    else if (seen) { stop(); return }
    const approved = hasVoice(heard.lang)
    const tried = !approved && ctx.preview && hasVoice(heard.lang, { preview: true })
    play.hidden = !(approved || tried)
    note.hidden = approved || tried
  }
  const stop = onChange(refresh)
  refresh()
  return { element: box, shown: () => shown }
}
