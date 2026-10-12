// "Ascolta": the device's own voice (WAVE2 section 4; contract frozen in W2-0, built by T2). The Web Speech API's speechSynthesis with a voice
// of the device: no network, nothing generated, no recognition, no recording of the student (firm rule 1, D-260's sibling entry W2-D05).
// A voice is used only if it is local, speaks it, en or es, and is in config/banco/voices.yml (the voices the operator heard on the student's
// device and accepted). "Ascolta" never autoplays; it stops on card change, on Escape, when focus leaves the card and when another speaker
// starts (A10). Speech is built from the VISIBLE state of the card (4.3): a value not yet on screen is never read aloud.
import voices from "lesson/voices"
import { notBuilt } from "lesson/lib/not_built"

export const GATE = Object.freeze({ localService: true, languages: ["it", "en", "es"] })

// The rate of a language: 1.0, or when slowed 0.8 (English 0.75, Spanish 0.7).
export function rateFor(lang, slower = false, rates = voices.rates) {
  if (!slower) return rates.normal
  return rates[`slower_${lang}`] ?? rates.slower
}

// voiceFor(lang, available, { accepted, preview }) -> SpeechSynthesisVoice | null
//   the voice gate: local voices of the language whose name is accepted (any local voice when +preview+, the teacher's try-out), the
//   preference of voices.yml first (en-GB, then other English; es-ES; it-IT), else the first candidate; null when there is none, and
//   then no speaker is shown for the language.
export function voiceFor(lang, available, { accepted = voices.accepted, preview = false, preference = voices.preference } = {}) {
  if (!GATE.languages.includes(lang)) return null
  const tag = (v) => String(v.lang ?? "").replace("_", "-").toLowerCase()
  const candidates = (available ?? []).filter((v) => v.localService === GATE.localService && tag(v).startsWith(lang) && (preview || (accepted[lang] ?? []).includes(v.name)))
  for (const wanted of preference[lang] ?? []) {
    const hit = candidates.find((v) => (wanted.length === 2 ? tag(v).startsWith(wanted) : tag(v) === wanted.toLowerCase()))
    if (hit) return hit
  }
  return candidates[0] ?? null
}

// speechOf(cardElement) -> [{ lang, text, node }]
//   walks the RENDERED card in reading order and reads only what is visible: not `hidden`, not `aria-hidden`, not inside a closed `details`,
//   an unflipped flip card's back, an unopened gloss or tap-to-see cell, or a withheld follow-up; for each figure it calls
//   speak(served, { state, revealed }) (or describe) with the figure's current state and revealed set (L10). Math is read through the speech
//   form of the markup grammar, chemistry as "tre molecole d'acqua: ...", bits digit by digit, code spans with symbol names.
export const speechOf = notBuilt("speech.speechOf", "T2", "w2-1")

// speak(segments, { rate, onSegment, onEnd }) -> { stop() } : plays the segments one after the other, switching voice at each lang
export const speak = notBuilt("speech.speak", "T2", "w2-1")

// stopAll() : stops the current speaker (card change, Escape, focus leaving the card, another speaker)
export const stopAll = notBuilt("speech.stopAll", "T2", "w2-1")
