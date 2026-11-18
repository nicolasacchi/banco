// The segments a lesson says aloud (D-359): what the render check's host collects while it draws every card in every state, so that the server can make
// a clip of each ahead of time (SpeakLessonRevisionJob). A segment is { lang, text, voice }: `text` exactly as the player is given it (the same walker
// and builders as "Ascolta": speechOf, the dialogue's segmentsOf, the figures' speechSegments through the walker, the speaker buttons, the `listen`
// check), `voice` the speaker's number (a dialogue's line has its speaker's, everything else 1). Nothing here plays or touches the voices of the device.
import { speechOf } from "lesson/speech"
import { segmentsOf } from "lesson/blocks/dialogue"
import { listenOf } from "lesson/checks/listen"

const segment = (lang, text, voice = 1) => ({ lang, text: String(text), voice })

// What "Ascolta" of the card says in the state it is in now (figures in their current state, open parts open, hidden ones left out); a segment
// that names its voice (a figure's) keeps it, the others are speaker 1.
export function heardIn(card) {
  return speechOf(card).filter((s) => s.text && String(s.text).trim()).map((s) => segment(s.lang, s.text, s.voice ?? 1))
}

// Every object under a piece of the lesson's data.
function* objectsIn(node) {
  if (Array.isArray(node)) {
    for (const item of node) yield* objectsIn(item)
  } else if (node && typeof node === "object") {
    yield node
    for (const value of Object.values(node)) yield* objectsIn(value)
  }
}

// What does not depend on the state: the lines of each dialogue with their speakers' voices, the text of each `listen` check, the speaker beside each
// [[en:..]] / [[es:..]] word of the card (the span before the button: its text is what the button says). `data` is the card's data, `card` its element.
export function fixedIn(data, card) {
  const out = []
  for (const object of objectsIn(data)) {
    if (object.type === "dialogue" && Array.isArray(object.lines) && Array.isArray(object.speakers)) {
      for (const s of segmentsOf(object)) if (s.text && String(s.text).trim()) out.push(segment(s.lang, s.text, s.voice))
    }
    const heard = object.listen && typeof object.listen === "object" ? listenOf(object) : null
    if (heard?.text) out.push(segment(heard.lang, heard.text))
  }
  for (const button of card?.querySelectorAll?.("button.speak-inline") ?? []) {
    const word = button.previousElementSibling
    const lang = word?.getAttribute("lang")
    if (lang && word.textContent) out.push(segment(lang, word.textContent))
  }
  return out
}
