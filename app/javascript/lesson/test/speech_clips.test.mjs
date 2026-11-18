// "Ascolta" with the server's voices (D-359): the key of a clip (the same as Ruby's: test/fixtures/speech/keys.json), the voice of a speaker, the clip
// a segment plays, the fall back to the accepted device voice or the skip when a clip is missing, stopping, and the gate. A fake <audio> stands in
// for the browser's; nothing here touches the network.
import "./setup.mjs"
import assert from "node:assert/strict"
import { createHash, randomBytes } from "node:crypto"
import { readFileSync } from "node:fs"
import { test, beforeEach } from "node:test"

const voices = (await import("lesson/voices")).default
const speech = { ...(await import("lesson/speech")), ...(await import("lesson/speech_device")) }
const { sha256Hex, clipKey, clipFor, serverVoice } = await import("lesson/speech_clips")
const { segmentsOf } = await import("lesson/blocks/dialogue")

const SERVER = { engine: "kokoro-82m-v1.0", voices: { it: ["im_nicola"], en: ["af_heart", "af_bella"], es: ["ef_dora", "em_alex"] }, clip_path: "/speech/clips", format: "mp3" }
const sha = (text) => createHash("sha256").update(text, "utf8").digest("hex")
const urlOf = (voice, text) => `/speech/clips/${sha(`${SERVER.engine}|${voice}|${text}`)}.mp3`

// an <audio>: records what was loaded and played, lets the test end, fail or start a clip
class FakeAudio {
  constructor({ rejectPlay = false } = {}) { this.rejectPlay = rejectPlay; this.paused = true; this.src = ""; this.loaded = []; this.playbackRate = 1; this.defaultPlaybackRate = 1 }
  play() { this.loaded.push(this.src); this.paused = false; return this.rejectPlay ? Promise.reject(new Error("NotAllowedError")) : Promise.resolve() }
  pause() { this.paused = true }
  removeAttribute(name) { if (name === "src") this.src = "" }
}
function fakeSynth(list = []) {
  const synth = { spoken: [], cancelled: 0, getVoices: () => list, cancel() { synth.cancelled += 1 }, speak(u) { synth.spoken.push(u) }, addEventListener() {}, removeEventListener() {} }
  return synth
}
globalThis.SpeechSynthesisUtterance = class { constructor(text) { this.text = text } }
const voice = (name, lang, localService = true) => ({ name, lang, localService })

let audio
beforeEach(() => {
  voices.server = SERVER
  audio = new FakeAudio()
  speech.stopAll()
  speech.configure({ audio, synth: fakeSynth(), accepted: { it: [], en: [], es: [] } })
  speech.setPreferences({ listen: true, slower: false })
})

test("the key of a clip is the SHA-256 of engine|voice|text: JS equals the shared vectors, whatever the length and the accents", () => {
  const doc = JSON.parse(readFileSync(new URL("../../../../test/fixtures/speech/keys.json", import.meta.url), "utf8"))
  assert.ok(doc.vectors.length >= 3)
  for (const { voice: name, text, key } of doc.vectors) {
    assert.equal(clipKey(doc.engine, name, text), key, text)
    assert.match(key, /^[0-9a-f]{64}$/)
  }
  // the plain-JS hash is the real one: around the block boundaries (55, 56, 63, 64, 119, 120 bytes) and with multi-byte text
  for (const n of [0, 1, 54, 55, 56, 57, 63, 64, 65, 119, 120, 121, 1000]) {
    const text = randomBytes(n).toString("base64").slice(0, n)
    assert.equal(sha256Hex(text), sha(text), `${n} characters`)
  }
  for (const text of ["è", "¿Cuándo llegas? Sí — «mañana»", "日本語 😀 mixed"]) assert.equal(sha256Hex(text), sha(text), text)
})

test("the voice of a speaker: the first for speaker 1, the second for speaker 2, then in turn; one voice for Italian; none for Latin", () => {
  assert.deepEqual([1, 2, 3, 4].map((n) => serverVoice("en", n, SERVER)), ["af_heart", "af_bella", "af_heart", "af_bella"])
  assert.deepEqual([1, 2, 3].map((n) => serverVoice("es", n, SERVER)), ["ef_dora", "em_alex", "ef_dora"])
  assert.deepEqual([1, 2, 3].map((n) => serverVoice("it", n, SERVER)), ["im_nicola", "im_nicola", "im_nicola"])
  assert.equal(serverVoice("en", undefined, SERVER), "af_heart", "a segment with no speaker is voice 1")
  assert.equal(serverVoice("la", 1, SERVER), null)
  assert.equal(serverVoice("en", 1, null), null, "a build with no server voices")
  assert.equal(clipFor({ lang: "la", text: "Gallia est omnis divisa" }, SERVER), null)
  assert.equal(clipFor({ lang: "en", text: "Hello", voice: 2 }, SERVER).url, urlOf("af_bella", "Hello"))
})

test("speak plays the server clip of Italian, English and Spanish from its URL, one at a time, and tells the segments and the end", () => {
  const ends = []
  const begun = []
  const segments = [{ lang: "it", text: "Dì così:" }, { lang: "en", text: "When I arrive, I will call you." }, { lang: "es", text: "Hola, ¿cómo estás?" }]
  const handle = speech.speak(segments, { onEnd: (e) => ends.push(e), onSegment: (i, s) => begun.push([i, s.lang]) })
  assert.deepEqual(audio.loaded, [urlOf("im_nicola", "Dì così:")])
  assert.equal(speech.playing(), true)
  audio.onplaying()
  audio.onended()
  assert.deepEqual(audio.loaded.at(-1), urlOf("af_heart", "When I arrive, I will call you."))
  audio.onplaying()
  audio.onended()
  assert.equal(audio.loaded.at(-1), urlOf("ef_dora", "Hola, ¿cómo estás?"))
  audio.onplaying()
  assert.deepEqual(ends, [])
  audio.onended()
  assert.deepEqual(ends, [{ stopped: false }])
  assert.deepEqual(begun, [[0, "it"], [1, "en"], [2, "es"]])
  assert.equal(speech.playing(), false)
  assert.equal(handle.stopped, false)
  assert.equal(audio.loaded.length, 3, "nothing was loaded but the clips that were played")
})

test("a dialogue gives each speaker his voice: speaker 1 the first English voice, speaker 2 the second, then alternating", () => {
  const block = {
    type: "dialogue",
    speakers: [{ id: "t", name: "Tom" }, { id: "a", name: "Amy" }, { id: "k", name: "Kim" }],
    lines: [{ speaker: "t", text_en: "Are you coming?" }, { speaker: "a", text_en: "Yes, if it doesn't rain." }, { speaker: "k", text_en: "Me too." }]
  }
  speech.speak(segmentsOf(block), {})
  const heard = []
  for (let i = 0; i < 3; i += 1) {
    heard.push(audio.loaded.at(-1))
    audio.onended?.()
  }
  assert.deepEqual(heard, [urlOf("af_heart", "Are you coming?"), urlOf("af_bella", "Yes, if it doesn't rain."), urlOf("af_heart", "Me too.")])
})

test("the walker keeps the voice that a figure gives a segment", () => {
  const figure = { nodeType: 1, tagName: "FIGURE", childNodes: [], getAttribute: () => null, speechSegments: () => [{ lang: "en", text: "Hi", voice: 2 }, { lang: "en", text: "Hello" }] }
  const root = { nodeType: 1, tagName: "ARTICLE", childNodes: [figure], getAttribute: () => null }
  figure.parentNode = root
  assert.deepEqual(speech.speechOf(root).map((s) => [s.text, s.voice]), [["Hi", 2], ["Hello", undefined]])
})

test("Più lento: the clip plays at 0.8, English 0.75, Spanish 0.7; an explicit rate wins; the rate survives the load of the source", () => {
  speech.speak([{ lang: "it", text: "Ciao" }], { slower: true })
  assert.equal(audio.playbackRate, 0.8)
  speech.speak([{ lang: "en", text: "Hello" }], { slower: true })
  assert.deepEqual([audio.playbackRate, audio.defaultPlaybackRate], [0.75, 0.75])
  speech.speak([{ lang: "es", text: "Hola" }], { rate: speech.rateFor("es", true) })
  assert.equal(audio.playbackRate, 0.7)
  speech.speak([{ lang: "es", text: "Hola" }], {})
  assert.equal(audio.playbackRate, 1)
})

test("a clip that fails to load is said by the accepted device voice of the language, else skipped to the next segment", () => {
  const synth = fakeSynth([voice("Daniel", "en-GB"), voice("Alice", "it-IT")])
  speech.configure({ synth, accepted: { it: [], en: ["Daniel"], es: [] } })
  const ends = []
  const begun = []
  speech.speak([{ lang: "en", text: "When I arrive" }, { lang: "es", text: "Hola" }, { lang: "it", text: "a Luca" }], { onEnd: (e) => ends.push(e), onSegment: (i) => begun.push(i) })
  audio.onerror() // 404: the English clip is missing
  assert.deepEqual(synth.spoken.map((u) => [u.text, u.voice.name]), [["When I arrive", "Daniel"]])
  synth.spoken[0].onstart()
  synth.spoken[0].onend()
  assert.equal(audio.loaded.at(-1), urlOf("ef_dora", "Hola"), "the next segment is tried with its own clip")
  audio.onerror() // Spanish: no accepted device voice either: skipped
  assert.equal(synth.spoken.length, 1)
  assert.equal(audio.loaded.at(-1), urlOf("im_nicola", "a Luca"))
  audio.onerror() // Italian: Alice is not accepted: skipped, and that was the last
  assert.deepEqual(ends, [{ stopped: false }])
  assert.deepEqual(begun, [0])
})

test("a clip that cannot be played (the tap was lost, or the type is refused) falls back the same way, once", async () => {
  const synth = fakeSynth([voice("Daniel", "en-GB")])
  audio = new FakeAudio({ rejectPlay: true })
  speech.configure({ audio, synth, accepted: { it: [], en: ["Daniel"], es: [] } })
  const ends = []
  speech.speak([{ lang: "en", text: "Hello" }], { onEnd: (e) => ends.push(e) })
  await new Promise((resolve) => setTimeout(resolve, 0))
  audio.onerror?.() // the error event may come as well: a second report of the same failure
  assert.deepEqual(synth.spoken.map((u) => u.text), ["Hello"])
  synth.spoken[0].onend()
  assert.deepEqual(ends, [{ stopped: false }])
})

test("stopAll, another speaker and stop() stop the clip at once: paused, unloaded, the end told once as stopped", () => {
  const ends = []
  speech.speak([{ lang: "en", text: "One" }, { lang: "en", text: "Two" }], { onEnd: (e) => ends.push(["first", e.stopped]) })
  assert.equal(audio.paused, false)
  speech.stopAll()
  assert.equal(audio.paused, true)
  assert.equal(audio.src, "")
  assert.deepEqual(ends, [["first", true]])
  assert.equal(audio.onended, null, "a late `ended` of the stopped clip cannot start the next segment")
  assert.equal(audio.loaded.length, 1)
  speech.stopAll()
  assert.equal(ends.length, 1, "stopping twice tells nothing twice")
  const second = speech.speak([{ lang: "it", text: "Uno" }], { onEnd: (e) => ends.push(["second", e.stopped]) })
  speech.speak([{ lang: "it", text: "Due" }], {})
  assert.deepEqual(ends.slice(1), [["second", true]], "another speaker stopped the one before")
  assert.equal(second.stopped, true)
  audio.onended()
  assert.deepEqual(audio.loaded.slice(-1), [urlOf("im_nicola", "Due")])
  const third = speech.speak([{ lang: "it", text: "Tre" }], {})
  third.stop()
  assert.equal(audio.paused, true)
})

test("a language with no server voice (Latin) is not played from the server: the device voice, else skipped; a device voice given to speak() is used alone", () => {
  const synth = fakeSynth([voice("Alice", "it-IT")])
  speech.configure({ synth, accepted: { it: ["Alice"], en: [], es: [] } })
  const ends = []
  speech.speak([{ lang: "la", text: "Gallia est omnis divisa" }, { lang: "it", text: "Ciao" }], { onEnd: (e) => ends.push(e) })
  assert.deepEqual(audio.loaded, [urlOf("im_nicola", "Ciao")], "Latin is skipped, Italian plays its clip")
  audio.onended()
  assert.deepEqual(ends, [{ stopped: false }])
  speech.speak([{ lang: "it", text: "Ciao" }], { voice: voice("Alice", "it-IT") })
  assert.equal(audio.loaded.length, 1, "an explicit device voice does not load a clip")
  assert.equal(synth.spoken.at(-1).text, "Ciao")
  speech.speak([{ lang: "en", text: "Hello" }], { device: false })
  audio.onerror()
  assert.equal(synth.spoken.length, 1, "device: false: a missing clip is skipped, never said by the device")
})

test("nothing is loaded until a speaker is pressed: no source on the <audio>, no clip played by the gate or the settings", () => {
  speech.hasVoice("en")
  speech.hasVoice("it")
  speech.serverSamples({ it: "Ciao. Leggo.", en: "Hello. Bye.", es: "Hola. Adios." })
  assert.equal(audio.src, "")
  assert.deepEqual(audio.loaded, [])
})

test("the gate: a language with server voices shows its speakers with no device voice at all; Latin, the switch off and no Audio do not", () => {
  assert.equal(speech.hasVoice("it"), true)
  assert.equal(speech.hasVoice("en"), true)
  assert.equal(speech.hasVoice("es"), true)
  assert.equal(speech.hasVoice("la"), false, "Latin stays as it was")
  speech.setPreferences({ listen: false })
  assert.equal(speech.hasVoice("en"), false)
  speech.setPreferences({ listen: true })
  voices.server = { ...SERVER, voices: { en: ["af_heart"] } }
  assert.equal(speech.hasVoice("es"), false, "a language with no server voice and no accepted device voice")
  speech.configure({ synth: fakeSynth([voice("Monica", "es-ES")]), accepted: { it: [], en: [], es: ["Monica"] } })
  assert.equal(speech.hasVoice("es"), true, "an accepted device voice still opens the gate")
  voices.server = SERVER
  speech.configure({ audio: null })
  const Audio = globalThis.Audio
  globalThis.Audio = undefined
  assert.equal(speech.hasVoice("en"), false, "a browser with no Audio cannot play a clip")
  globalThis.Audio = Audio
})

test("«Prova le voci»: one sample per server voice, the first sentence of its language's sample, with the voice's place in the list", () => {
  const sentences = {
    it: "Ciao, questa è la mia voce. Leggo una frase molto semplice.",
    en: "Hello, this is my voice. When I arrive, I will call you.",
    es: "Hola, esta es mi voz. Cuando llegue, te llamaré."
  }
  assert.deepEqual(speech.serverSamples(sentences, SERVER), [
    { lang: "it", name: "im_nicola", text: "Ciao, questa è la mia voce.", voice: 1 },
    { lang: "en", name: "af_heart", text: "Hello, this is my voice.", voice: 1 },
    { lang: "en", name: "af_bella", text: "Hello, this is my voice.", voice: 2 },
    { lang: "es", name: "ef_dora", text: "Hola, esta es mi voz.", voice: 1 },
    { lang: "es", name: "em_alex", text: "Hola, esta es mi voz.", voice: 2 }
  ])
  assert.deepEqual(speech.serverSamples(sentences, null), [])
  const [, , bella] = speech.serverSamples(sentences, SERVER)
  speech.speak([{ lang: bella.lang, text: bella.text, voice: bella.voice }], { device: false })
  assert.equal(audio.loaded.at(-1), urlOf("af_bella", "Hello, this is my voice."))
})
