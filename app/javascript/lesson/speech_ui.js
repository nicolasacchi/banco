// The buttons of "Ascolta" (D-282): a speaker for one piece of text (tap to hear), and the card's "Ascolta" with "Più lento". A speaker is hidden until
// the voice gate lets a voice through for its language and the student's switch is on (the device's voice list can arrive late), and the teacher's
// preview, which may try any local voice, says so. Nothing here plays by itself: every sound starts with a tap (Safari insists, and so does A10).
import { el, icon } from "lesson/dom"
import { speak, stopAll, speechOf } from "lesson/speech"
import { hasVoice, onChange, preferences, setPreferences } from "lesson/speech_device"

const clip = (text, n = 60) => (text.length > n ? `${text.slice(0, n - 1)}…` : text)

// Marks the node being read (a class the stylesheet turns into a calm highlight, never colour alone).
function mark(node, on) {
  node?.classList?.toggle("speaking", on)
}

// Keeps a button in step with the device: shown when a voice can be used, labelled when it is only the preview's.
function follow(button, lang, ctx, labelled) {
  let seen = false
  const refresh = () => {
    if (button.isConnected) seen = true
    else if (seen) { stop(); return }
    const approved = hasVoice(lang)
    const tried = !approved && ctx.preview && hasVoice(lang, { preview: true })
    button.hidden = !(approved || tried)
    button.classList.toggle("speak-unapproved", tried)
    labelled(tried)
  }
  const stop = onChange(refresh)
  refresh()
}

// speakerButton(ctx, { lang, text, node }) : a small speaker that reads +text+ in +lang+ and highlights +node+ while it does.
export function speakerButton(ctx, { lang, text, node }) {
  const t = ctx.t.speech
  const name = t.languages[lang] ?? lang
  const button = el("button", { type: "button", class: "speak speak-inline", hidden: "", "aria-pressed": "false" }, icon("listen", "speak-ic"))
  const label = (tried) => {
    button.setAttribute("aria-label", `${t.listen_text_in.replace("%{language}", name).replace("%{text}", clip(text))}${tried ? `. ${t.unapproved}` : ""}`)
    button.title = tried ? t.unapproved : ""
  }
  label(false)
  let handle = null
  const idle = () => {
    handle = null
    button.setAttribute("aria-pressed", "false")
    mark(node, false)
    button.replaceChildren(icon("listen", "speak-ic"))
  }
  button.addEventListener("click", () => {
    if (handle) { stopAll(); return }
    button.setAttribute("aria-pressed", "true")
    button.replaceChildren(icon("listen-stop", "speak-ic"))
    mark(node, true)
    handle = speak([{ lang, text }], { preview: ctx.preview, slower: preferences().slower, onEnd: idle })
  })
  follow(button, lang, ctx, label)
  return button
}

// cardListen(article, ctx) : the card's "Ascolta" (it reads the rendered card) and its "Più lento" switch. Hidden until Italian can be read.
export function cardListen(article, ctx) {
  const t = ctx.t.speech
  const play = el("button", { type: "button", class: "button secondary speak-card", "aria-pressed": "false" }, icon("listen", "speak-ic"), el("span", { text: t.listen }))
  const slower = el("button", { type: "button", class: "button secondary small speak-slower", "aria-pressed": String(preferences().slower) }, icon("slower", "speak-ic"), el("span", { text: t.slower }))
  const box = el("div", { class: "card-listen", hidden: "", "data-nospeech": "" }, play, slower)
  let handle = null
  let marked = null
  const idle = () => {
    handle = null
    play.setAttribute("aria-pressed", "false")
    play.replaceChildren(icon("listen", "speak-ic"), el("span", { text: t.listen }))
    mark(marked, false)
    marked = null
  }
  play.addEventListener("click", () => {
    if (handle) { stopAll(); return }
    const segments = speechOf(article)
    if (segments.length === 0) return
    play.setAttribute("aria-pressed", "true")
    play.replaceChildren(icon("listen-stop", "speak-ic"), el("span", { text: t.stop }))
    handle = speak(segments, {
      preview: ctx.preview,
      slower: preferences().slower,
      onSegment: (i, segment) => { mark(marked, false); marked = segment.node; mark(marked, true) },
      onEnd: idle
    })
  })
  slower.addEventListener("click", () => {
    const on = slower.getAttribute("aria-pressed") !== "true"
    slower.setAttribute("aria-pressed", String(on))
    setPreferences({ slower: on })
    ctx.savePreferences?.({ slower: on })
  })
  follow(box, "it", ctx, (tried) => { play.title = tried ? t.unapproved : "" }) // the teacher's preview may try a voice nobody accepted yet, and says so
  // it stops when the focus leaves the card
  article.addEventListener("focusout", (event) => {
    if (handle && event.relatedTarget && !article.contains(event.relatedTarget)) stopAll()
  })
  return box
}

// Escape stops the voice, wherever the focus is; one listener for the page.
let escapeBound = false
export function bindEscape() {
  if (escapeBound || typeof document === "undefined") return
  escapeBound = true
  document.addEventListener("keydown", (event) => { if (event.key === "Escape") stopAll() })
}
