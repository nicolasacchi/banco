// The state of the speaker, shared by lesson/speech.js (the frozen contract: gate, walker, player) and lesson/speech_device.js (the device, the
// student's switches, "Prova le voci"). Its own file so that the contract file exports exactly its frozen functions.
import voices from "lesson/voices"

export const state = { accepted: voices.accepted, synth: null, listeners: new Set(), watching: null, listen: true, slower: false, current: null, audio: null }

// The speechSynthesis of the device (or the one configure() put there for a test); null where there is none.
export const device = () => state.synth ?? globalThis.speechSynthesis ?? null

// The one <audio> that plays the server clips (made on first use, kept: Safari lets an element that a tap started play the next clip), or null where
// the browser has no Audio. Nothing is loaded into it until a clip is played.
export function audio() {
  if (!state.audio && typeof globalThis.Audio === "function") state.audio = new globalThis.Audio()
  return state.audio
}

// Whether server clips can be played here.
export const canPlayClips = () => state.audio !== null || typeof globalThis.Audio === "function"

export function notify() {
  for (const callback of [...state.listeners]) callback()
}

export function voicesList() {
  try {
    return Array.from(device()?.getVoices?.() ?? [])
  } catch (_error) {
    return []
  }
}
