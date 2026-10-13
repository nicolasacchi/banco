// The device side of "Ascolta" (D-283): which voices the device has, whether a speaker may be shown, the student's two switches, and the sentences
// of "Prova le voci". The frozen contract (gate, walker, player) is lesson/speech.js.
import { GATE, voiceFor } from "lesson/speech"
import { state, device, notify, voicesList } from "lesson/speech_state"

export { voicesList }


// configure({ accepted, synth }): tests, and the settings page (which tries every local voice). synth: an object like speechSynthesis.
export function configure({ accepted, synth } = {}) {
  if (accepted) state.accepted = accepted
  if (synth !== undefined) {
    state.watching?.synth?.removeEventListener?.("voiceschanged", state.watching.fn)
    state.watching = null
    state.synth = synth
  }
  notify()
}

// setPreferences({ listen, slower }): the student's two switches (kept on the server as student_preference events by the page).
export function setPreferences({ listen, slower } = {}) {
  if (typeof listen === "boolean") state.listen = listen
  if (typeof slower === "boolean") state.slower = slower
  notify()
}
export const preferences = () => ({ listen: state.listen, slower: state.slower })

// Whether a speaker may be shown for +lang+: the switch is on and the gate lets a voice through.
export function hasVoice(lang, { preview = false } = {}) {
  return state.listen && voiceFor(lang, voicesList(), { preview }) !== null
}

// Called when the voice list or a switch changes (voiceschanged arrives late on Safari). Returns the function that stops listening.
export function onChange(callback) {
  state.listeners.add(callback)
  const synth = device()
  if (synth && !state.watching && typeof synth.addEventListener === "function") {
    state.watching = { synth, fn: () => notify() }
    synth.addEventListener("voiceschanged", state.watching.fn)
  }
  return () => state.listeners.delete(callback)
}


export const playing = () => state.current !== null

// ---- "Prova le voci" ----

// The fixed sentence each local voice says on the settings page, by language.
export const TRY_SENTENCES = {
  it: "Ciao, questa è la mia voce. Leggo una frase molto semplice.",
  en: "Hello, this is my voice. When I arrive, I will call you.",
  es: "Hola, esta es mi voz. Cuando llegue, te llamaré."
}

// Every local voice of a language we use, for the settings page: [{ name, lang, language, accepted }].
export function localVoices(available = voicesList()) {
  return available
    .filter((v) => v.localService === GATE.localService)
    .map((v) => ({ voice: v, name: v.name, lang: v.lang, language: GATE.languages.find((l) => String(v.lang ?? "").toLowerCase().replace("_", "-").startsWith(l)) }))
    .filter((v) => v.language)
    .map((v) => ({ ...v, accepted: (state.accepted[v.language] ?? []).includes(v.name) }))
}
