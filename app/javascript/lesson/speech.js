// "Ascolta": the device's own voice (WAVE2 section 4; contract frozen in W2-0, built by T2, D-283). The Web Speech API's speechSynthesis with a
// voice of the device: no network, nothing generated, no recognition, no recording of the student (firm rule 1, D-267).
// A voice is used only if it is local, speaks it, en or es, and is in config/banco/voices.yml (the voices the operator heard on the student's
// device and accepted). "Ascolta" never autoplays; it stops on card change, on Escape, when focus leaves the card and when another speaker
// starts (A10). Speech is built from the VISIBLE state of the card (4.3): a value not yet on screen is never read aloud.
//
// This file is the core: the gate, the walker of a rendered card and the player. The buttons are lesson/speech_ui.js; how a formula, a chemical
// formula, a code span and a string of bits sound is lesson/speech_math.js. Nothing here touches the document at import time, so Node can load it.
import voices from "lesson/voices"
import { state, device, voicesList } from "lesson/speech_state"
import { texToSpeech, codeToSpeech, plainToSpeech, bitsToSpeech } from "lesson/speech_math"

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
export function voiceFor(lang, available, { accepted = state.accepted, preview = false, preference = voices.preference } = {}) {
  if (!GATE.languages.includes(lang)) return null
  const tag = (v) => String(v.lang ?? "").replace("_", "-").toLowerCase()
  const candidates = (available ?? []).filter((v) => v.localService === GATE.localService && tag(v).startsWith(lang) && (preview || (accepted[lang] ?? []).includes(v.name)))
  for (const wanted of preference[lang] ?? []) {
    const hit = candidates.find((v) => (wanted.length === 2 ? tag(v).startsWith(wanted) : tag(v) === wanted.toLowerCase()))
    if (hit) return hit
  }
  return candidates[0] ?? null
}

// The frozen signatures, one string per function (checked by lesson/test/contract.test.mjs against the exports). The per-figure hook is
// `speechSegments` (lesson/diagrams/contract.js), not `speak`: `speak` here plays segments.
export const SIGNATURES = {
  rateFor: "rateFor(lang, slower, rates)",
  voiceFor: "voiceFor(lang, available, { accepted, preview, preference })",
  speechOf: "speechOf(cardElement)",
  speak: "speak(segments, { rate, onSegment, onEnd })",
  stopAll: "stopAll()"
}

// ---- the walker: what the rendered card says ---------------------------------------------------------------------------------------------

const SKIP_TAGS = new Set(["INPUT", "SELECT", "TEXTAREA", "SVG", "SCRIPT", "STYLE", "NAV", "TEMPLATE", "DIALOG", "AUDIO", "VIDEO", "CANVAS", "IMG"])
const INLINE_TAGS = new Set(["SPAN", "A", "STRONG", "EM", "B", "I", "SMALL", "MARK", "CODE", "SUB", "SUP", "ABBR", "U"])
const LANGS = ["it", "en", "es", "la"]

const attr = (node, name) => (typeof node.getAttribute === "function" ? node.getAttribute(name) : (node.attrs?.[name] ?? null))
const hasAttr = (node, name) => attr(node, name) !== null && attr(node, name) !== undefined
const classes = (node) => String(attr(node, "class") ?? "").split(/\s+/)

// A button is a control, not text, except the ones whose face is the lesson's own words: the card that turns (`mistake-toggle`, `reveal-toggle`),
// the option of a crossroads, the span of a span_select and the tile of a tile check.
const CONTENT_BUTTON = /(^|\s)(?:[a-z]+-toggle|reveal-option|span-chip|tile)(\s|$)/

// Whether a node is out of the reading: hidden, aria-hidden, inert, marked as not spoken, for screen readers only, a control, or not drawn
// (checkVisibility where the browser has it, else the computed style: an unflipped back is `display: none`).
function isOut(node) {
  if (node.hidden === true || hasAttr(node, "hidden") || attr(node, "aria-hidden") === "true" || hasAttr(node, "inert") || hasAttr(node, "data-nospeech")) return true
  const tag = String(node.tagName).toUpperCase()
  if (SKIP_TAGS.has(tag)) return true
  const cls = String(attr(node, "class") ?? "")
  if (/(^|\s)sr-only(\s|$)/.test(cls)) return true
  if (tag === "BUTTON" && !CONTENT_BUTTON.test(cls)) return true
  if (typeof node.checkVisibility === "function") return node.checkVisibility() === false
  if (typeof globalThis.getComputedStyle === "function" && typeof node.nodeType === "number" && node.ownerDocument) {
    const style = globalThis.getComputedStyle(node)
    return style.display === "none" || style.visibility === "hidden"
  }
  return false
}

function langOf(node, inherited) {
  const l = String(attr(node, "lang") ?? "").slice(0, 2).toLowerCase()
  return LANGS.includes(l) ? l : inherited
}

// speechOf(cardElement) -> [{ lang, text, node }]
//   walks the RENDERED card in reading order and reads only what is visible: not `hidden`, not `aria-hidden`, not inside a closed `details`,
//   an unflipped flip card's back, an unopened gloss or tap-to-see cell, or a withheld follow-up; for each figure it calls
//   speechSegments(served, { state, revealed }) (or describe) with the figure's current state and revealed set (L10). Math is read through the speech
//   form of the markup grammar, chemistry as "tre molecole: ...", bits digit by digit, code spans with symbol names.
//   A figure answers for itself: an element with a `speechSegments()` function. An element with data-speech-text says what it says in
//   that attribute (and data-speech-lang its language); data-speech-bits is read digit by digit; data-nospeech is not read at all.
export function speechOf(root) {
  const out = []
  let current = null
  const flush = () => {
    // the pieces of an inline run are joined as the page has them (the text nodes keep their own spaces); a space never stands before a mark
    if (current && current.text.trim()) out.push({ lang: current.lang, text: current.text.replace(/\s+/g, " ").replace(/\s+([.,;:!?)»])/g, "$1").trim(), node: current.node })
    current = null
  }
  const add = (lang, text, node) => {
    if (!text) return
    if (current && current.lang !== lang) flush()
    if (!current) current = { lang, text: "", node }
    current.text += text
  }
  const walk = (node, lang) => {
    if (node.nodeType === 3) {
      add(lang, plainToSpeech(node.nodeValue ?? node.data ?? node.textContent ?? "", lang), node.parentNode)
      return
    }
    if (node.nodeType !== 1 || (node !== root && isOut(node))) return
    const own = langOf(node, lang)
    if (typeof node.speechSegments === "function") {
      flush()
      for (const seg of node.speechSegments() ?? []) if (seg?.text) out.push({ lang: seg.lang ?? "it", text: String(seg.text).replace(/\s+/g, " ").trim(), node })
      return
    }
    const cls = classes(node)
    if (hasAttr(node, "data-speech-text")) {
      flush()
      out.push({ lang: attr(node, "data-speech-lang") ?? own, text: String(attr(node, "data-speech-text")), node })
      return
    }
    if (hasAttr(node, "data-speech-bits")) {
      flush()
      out.push({ lang: "it", text: bitsToSpeech(attr(node, "data-speech-bits")), node })
      return
    }
    if (cls.includes("katex")) {
      const tex = node.querySelector?.('annotation[encoding="application/x-tex"]')?.textContent
      add("it", ` ${tex ? texToSpeech(tex) : (node.textContent ?? "")} `, node)
      return
    }
    if (cls.includes("code-span")) {
      add("it", ` ${codeToSpeech(node.textContent ?? "")} `, node)
      return
    }
    const tag = String(node.tagName).toUpperCase()
    const block = !INLINE_TAGS.has(tag)
    if (block || own !== lang) flush()
    if (tag === "DETAILS" && !node.open && !hasAttr(node, "open")) {
      // a closed details reads its summary only
      for (const child of node.childNodes ?? []) if (String(child.tagName).toUpperCase() === "SUMMARY") walk(child, own)
      flush()
      return
    }
    // a bubble that opens next to its word is read after it, as a separate breath
    const spaced = cls.includes("gloss-pop") || cls.includes("speak")
    if (spaced) add(own, " ", node)
    for (const child of node.childNodes ?? []) walk(child, own)
    if (spaced) add(own, " ", node)
    if (block || own !== lang) flush()
  }
  walk(root, langOf(root, "it"))
  flush()
  return out
}

// ---- the player ---------------------------------------------------------------------------------------------------------------------------

// speak(segments, { rate, slower, voice, preview, onSegment, onBoundary, onEnd }) -> { stop() } : plays the segments one after the other, switching
//   voice at each lang. A segment whose language has no accepted voice is skipped. Stops what was playing before (one speaker at a time).
//   onSegment(index, segment) when one starts; onBoundary(segment, charIndex, charLength) at each word where the device says it;
//   onEnd({ stopped }) once, when the last one ended or stop() was called.
export function speak(segments, { rate, slower, voice, preview = false, onSegment, onBoundary, onEnd } = {}) {
  stopAll()
  const synth = device()
  const queue = (segments ?? []).filter((s) => s?.text && String(s.text).trim())
  let done = false
  let index = 0
  const handle = {
    stopped: false,
    stop() {
      if (done) return
      handle.stopped = true
      finish(true)
    }
  }
  const finish = (stopped) => {
    if (done) return
    done = true
    if (state.current === handle) state.current = null
    if (stopped) { try { synth?.cancel?.() } catch (_error) { /* nothing to cancel */ } }
    onEnd?.({ stopped })
  }
  state.current = handle
  const Utterance = globalThis.SpeechSynthesisUtterance
  const next = () => {
    if (done || handle.stopped) return
    let chosen = null
    while (index < queue.length && !(chosen = voice ?? voiceFor(queue[index].lang, voicesList(), { preview }))) index += 1
    if (index >= queue.length || !synth || !Utterance) {
      finish(false)
      return
    }
    const segment = queue[index]
    const utterance = new Utterance(segment.text)
    utterance.voice = chosen
    utterance.lang = chosen.lang
    utterance.rate = rate ?? rateFor(segment.lang, slower ?? state.slower)
    utterance.onstart = () => onSegment?.(index, segment)
    utterance.onboundary = (event) => onBoundary?.(segment, event.charIndex, event.charLength)
    utterance.onend = () => { index += 1; next() }
    utterance.onerror = () => finish(false)
    handle.utterance = utterance // kept: a browser may collect an utterance that nobody holds before it ends
    synth.speak(utterance)
  }
  next()
  return handle
}

// stopAll() : stops the current speaker (card change, Escape, focus leaving the card, another speaker)
export function stopAll() {
  const handle = state.current
  state.current = null
  if (handle) handle.stop()
  else { try { device()?.cancel?.() } catch (_error) { /* nothing is playing */ } }
}

