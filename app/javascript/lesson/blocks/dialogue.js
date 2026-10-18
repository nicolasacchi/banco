// dialogue (WAVE2 2.6, T3): a scripted exchange in the target language, one speaker's line after another, chat-like. Every line has its own "IT"
// button that opens its Italian gloss in place (one tap, one line: never a block of glosses). "Ascolta tutto" reads the exchange with a voice for
// each speaker and marks the line being read; a tap on the speaker button of a line reads that line; "Più lento" slows the voices. All of it needs a
// voice the operator accepted on the device (the voice gate of lesson/speech): with none, the transcript is open and the card works by reading.
// Glosses are teaching content, served whole (L8): the closed ones are `hidden`, so neither a screen reader nor "Ascolta" meets them before they
// are opened (L10). In print, in the teacher's view and in safe mode everything is open.
import { button, el, icon, uid } from "lesson/dom"
import { insideControl, plainText, renderInlineRich } from "lesson/text"
import * as speech from "lesson/speech"

export const type = "dialogue"

const LANGS = { text_en: "en", text_es: "es" }
const textKeyOf = (line) => Object.keys(LANGS).find((k) => line[k] != null)
export const langOf = (block) => LANGS[textKeyOf(block.lines[0])]
export const textOf = (line) => line[textKeyOf(line)]
const initialOf = (name) => [...name][0]?.toUpperCase() ?? "?"

// The segments "Ascolta tutto" plays: each line in the language of the dialogue, with the speaker's voice number (1 to 3) for the voice or pitch.
export function segmentsOf(block, speakers = new Map(block.speakers.map((s, i) => [s.id, { ...s, voice: s.voice ?? i + 1 }]))) {
  return block.lines.map((line) => ({ lang: LANGS[textKeyOf(line)], text: textOf(line), voice: speakers.get(line.speaker)?.voice ?? 1 }))
}

// Whether a voice for this language may be used on this device (accepted, local): none when there is no speech synthesis at all.
function hasVoice(lang) {
  try {
    const synth = typeof speechSynthesis !== "undefined" ? speechSynthesis : null
    return !!(synth && speech.voiceFor(lang, synth.getVoices()))
  } catch (_error) {
    return false
  }
}

const safely = (fn) => {
  try {
    return fn()
  } catch (_error) {
    return null // the speech layer is not there (or refused): the card still works by reading
  }
}

export function render(block, ctx) {
  const t = ctx.t.words.dialogue
  const lang = langOf(block)
  const open = !!ctx.openAll
  const speakers = new Map(block.speakers.map((s, i) => [s.id, { ...s, side: i % 2 === 0 ? "a" : "b", n: i + 1 }]))
  const root = el("section", { class: "block dialogue", "aria-label": block.title_it ? plainText(block.title_it) : null, "data-lang": lang })
  root.appendChild(el("header", { class: "dialogue-head" }, icon("languages", "dialogue-ic"), renderInlineRich(block.title_it ?? "", el("strong", { class: "dialogue-title" }), insideControl(ctx))))
  const voice = !open && hasVoice(lang)
  let transcript = open || !voice ? "shown" : block.transcript ?? "shown"
  let slower = false
  let playing = null
  const bar = el("div", { class: "dialogue-bar", role: "group", "aria-label": block.title_it ? plainText(block.title_it) : null })
  const listen = button(t.listen_all, { class: "button secondary small dialogue-listen", "aria-pressed": "false" })
  const slow = button(t.slower, { class: "button secondary small dialogue-slow", "aria-pressed": "false" })
  const toggle = button(transcript === "shown" ? t.transcript_hide : t.transcript_show, { class: "button secondary small dialogue-transcript", "aria-pressed": String(transcript === "shown") })
  for (const b of [listen, slow, toggle]) b.hidden = !voice
  bar.append(listen, slow, toggle)
  root.appendChild(bar)

  const list = el("ol", { class: "dialogue-lines", role: "list" })
  const rows = block.lines.map((line, i) => {
    const sp = speakers.get(line.speaker)
    const n = i + 1
    const glossId = uid("gloss")
    const textNode = el("p", { class: "dialogue-text", lang, text: textOf(line) })
    const hiddenNote = el("p", { class: "dialogue-hidden-text", text: t.hidden_line.replace("%{n}", n) })
    const gloss = el("p", { class: "dialogue-gloss", id: glossId, lang: "it" })
    renderInlineRich(line.gloss_it, gloss, ctx)
    const it = button(t.gloss_open, { class: "dialogue-it", "aria-expanded": "false", "aria-controls": glossId, "aria-label": t.gloss_open_label })
    const say = button(icon("listen", "dialogue-say-ic"), { class: "dialogue-say", "aria-label": `${t.speak_line} ${n}` })
    say.hidden = !voice
    const bubble = el("div", { class: "dialogue-bubble" },
      el("span", { class: "dialogue-name", text: sp.name }), textNode, hiddenNote, el("div", { class: "dialogue-tools" }, say, it), gloss)
    const li = el("li", { class: `dialogue-line dialogue-side-${sp.side}`, "data-line": String(i), "data-speaker": line.speaker },
      el("span", { class: "dialogue-initial", "aria-hidden": "true", text: initialOf(sp.name) }), bubble)
    const setGloss = (shown) => {
      gloss.hidden = !shown
      it.setAttribute("aria-expanded", String(shown))
      it.textContent = shown ? t.gloss_hide : t.gloss_open
      it.setAttribute("aria-label", shown ? t.gloss_hide_label : t.gloss_open_label)
    }
    setGloss(open)
    it.addEventListener("click", () => setGloss(gloss.hidden))
    say.addEventListener("click", () => play([i]))
    list.appendChild(li)
    return { li, textNode, hiddenNote }
  })
  root.appendChild(list)

  const paint = () => {
    for (const r of rows) {
      r.textNode.hidden = transcript !== "shown"
      r.hiddenNote.hidden = transcript === "shown"
    }
    toggle.textContent = transcript === "shown" ? t.transcript_hide : t.transcript_show
    toggle.setAttribute("aria-pressed", String(transcript === "shown"))
  }
  const mark = (index) => rows.forEach((r, i) => {
    r.li.classList.toggle("is-reading", i === index)
    if (i === index) r.li.setAttribute("aria-current", "true")
    else r.li.removeAttribute("aria-current")
  })
  const stop = () => {
    safely(() => speech.stopAll())
    playing = null
    mark(-1)
    listen.setAttribute("aria-pressed", "false")
    listen.textContent = t.listen_all
  }
  // play the lines (their numbers from 0) one after the other, marking the one being read
  function play(indexes) {
    if (playing) stop()
    const all = segmentsOf(block, new Map([...speakers].map(([id, s]) => [id, { ...s, voice: s.voice ?? s.n }])))
    const segments = indexes.map((i) => all[i])
    const started = safely(() => speech.speak(segments, {
      rate: speech.rateFor(lang, slower),
      onSegment: (k) => mark(indexes[k]),
      onEnd: () => stop()
    }))
    if (started === null) return
    playing = started
    if (indexes.length > 1) {
      listen.setAttribute("aria-pressed", "true")
      listen.textContent = t.stop
    }
  }
  listen.addEventListener("click", () => (playing ? stop() : play(block.lines.map((_, i) => i))))
  slow.addEventListener("click", () => {
    slower = !slower
    slow.setAttribute("aria-pressed", String(slower))
  })
  toggle.addEventListener("click", () => {
    transcript = transcript === "shown" ? "hidden" : "shown"
    paint()
  })
  // the voices of a device can arrive after the page: show the controls when one turns up
  if (!open && !voice && typeof speechSynthesis !== "undefined" && speechSynthesis.addEventListener) {
    speechSynthesis.addEventListener("voiceschanged", () => {
      if (!hasVoice(lang)) return
      for (const b of [listen, slow, toggle]) b.hidden = false
      root.querySelectorAll(".dialogue-say").forEach((b) => { b.hidden = false })
      transcript = block.transcript ?? "shown"
      paint()
    })
  }
  root.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && playing) stop()
  })
  paint()
  return root
}
