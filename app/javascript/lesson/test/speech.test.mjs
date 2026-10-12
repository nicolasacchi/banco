// "Ascolta" (T2, D-282): the walker reads what is visible, the player switches voice per language and stops, the maths and the chemistry sound as
// they should. A tiny DOM stands in for the browser (Node has none); the goldens of the gallery cards are read from Chrome by the system test.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const speech = { ...(await import("lesson/speech")), ...(await import("lesson/speech_device")) }
const { texToSpeech, chemToSpeech, codeToSpeech, bitsToSpeech, plainToSpeech } = await import("lesson/speech_math")

// a minimal DOM: elements with attributes and children, text nodes
function text(value) { return { nodeType: 3, nodeValue: value } }
function el(tag, attrs = {}, ...kids) {
  const node = { nodeType: 1, tagName: tag.toUpperCase(), attrs, childNodes: kids.map((k) => (typeof k === "string" ? text(k) : k)), getAttribute(n) { return n in attrs ? String(attrs[n]) : null } }
  if ("hidden" in attrs) node.hidden = true
  for (const kid of node.childNodes) kid.parentNode = node
  node.textContent = node.childNodes.map((k) => k.nodeValue ?? k.textContent).join("")
  return node
}
function katex(tex, shown) {
  const annotation = el("annotation", { encoding: "application/x-tex" }, tex)
  const node = el("span", { class: "katex" }, el("span", { class: "katex-mathml" }, annotation), el("span", { class: "katex-html" }, shown ?? tex))
  node.querySelector = () => annotation
  return node
}
const said = (card) => speech.speechOf(card).map((s) => `${s.lang}: ${s.text}`)

test("the walker reads titles, paragraphs and lists in order, one segment per block, and switches at a language span", () => {
  const card = el("article", {},
    el("h2", {}, "Il futuro dopo when"),
    el("p", {}, "Dì ", el("span", { lang: "en", class: "lang" }, "When I arrive, I'll call you."), " a Luca."),
    el("ul", {}, el("li", {}, "uno"), el("li", {}, "due")))
  assert.deepEqual(said(card), ["it: Il futuro dopo when", "it: Dì", "en: When I arrive, I'll call you.", "it: a Luca.", "it: uno", "it: due"])
})

test("the walker leaves out what is not visible: hidden, aria-hidden, a closed details, buttons, svg, data-nospeech", () => {
  const card = el("article", {},
    el("p", {}, "Visibile."),
    el("p", { hidden: "" }, "Nascosto."),
    el("p", { "aria-hidden": "true" }, "Solo per i lettori di schermo."),
    el("details", {}, el("summary", {}, "Soluzione"), el("p", {}, "x = 5")),
    el("details", { open: "" }, el("summary", {}, "Aperta"), el("p", {}, "Dentro.")),
    el("button", {}, "Controlla"),
    el("svg", {}, "etichette"),
    el("p", { "data-nospeech": "" }, "Spiegazione dopo la risposta."))
  assert.deepEqual(said(card), ["it: Visibile.", "it: Soluzione", "it: Aperta", "it: Dentro."])
})

test("an unopened gloss and an unflipped back are not read; once they are open they are, after the word", () => {
  const pop = (hidden) => el("span", { class: "gloss-pop", ...(hidden ? { hidden: "" } : {}) }, "La firma che rende valida la legge.")
  const card = (hidden) => el("article", {}, el("p", {}, "La ", el("span", { class: "gloss" }, el("span", { class: "gloss-word" }, "promulgazione"), el("button", {}, "?"), pop(hidden)), " chiude l'iter."))
  assert.deepEqual(said(card(true)), ["it: La promulgazione chiude l'iter."])
  assert.deepEqual(said(card(false)), ["it: La promulgazione La firma che rende valida la legge. chiude l'iter."])
})

test("a formula is read from its TeX source, a chemical formula by its atoms, a code span by its symbols", () => {
  const card = el("article", {}, el("p", {}, "Risolvi ", katex("2x + 3 = 7"), "."), el("p", {}, "Scrivi ", katex("\\ce{3H2O}"), "."), el("p", {}, "Poi ", el("span", { class: "code-span" }, "k < 40"), "."))
  assert.deepEqual(said(card), ["it: Risolvi 2 x più 3 uguale 7 .", "it: Scrivi tre molecole: 6 atomi di idrogeno e 3 di ossigeno .", "it: Poi k minore di 40 ."])
})

test("a figure speaks for itself, from the state it shows now; data-speech-text and data-speech-bits say what they say", () => {
  const figure = el("figure", {}, el("p", {}, "etichetta del disegno"))
  figure.speechSegments = () => [{ lang: "it", text: "Bilancia in equilibrio: due x più tre pesi da uno pari a sette." }]
  const card = el("article", {}, el("p", {}, "Prima."), figure, el("span", { "data-speech-bits": "01101011" }), el("span", { "data-speech-text": "Hello", "data-speech-lang": "en" }))
  assert.deepEqual(said(card), ["it: Prima.", "it: Bilancia in equilibrio: due x più tre pesi da uno pari a sette.", "it: zero uno uno zero, uno zero uno uno", "en: Hello"])
})

test("the speech of maths: operators, fractions, powers, roots, roles", () => {
  assert.equal(texToSpeech("2x + 3 = 7"), "2 x più 3 uguale 7")
  assert.equal(texToSpeech("\\frac{3}{4}"), "3 fratto 4")
  assert.equal(texToSpeech("\\frac{x + 1}{2}"), "frazione con numeratore x più 1 e denominatore 2")
  assert.equal(texToSpeech("x^2 + y^3 - a^{n}"), "x al quadrato più y al cubo meno a alla n")
  assert.equal(texToSpeech("\\sqrt{9} = 3"), "radice quadrata di 9 uguale 3")
  assert.equal(texToSpeech("\\role{unknown}{x} \\neq 3,5"), "x diverso da 3,5")
  assert.equal(texToSpeech("(x - 1)^2"), "apri parentesi x meno 1 chiudi parentesi al quadrato")
  assert.equal(texToSpeech("a \\cdot b \\leftarrow 5"), "a per b prende 5")
})

test("the speech of chemistry, code and bits", () => {
  assert.equal(chemToSpeech("3H2O"), "tre molecole: 6 atomi di idrogeno e 3 di ossigeno")
  assert.equal(chemToSpeech("Ca(OH)2"), "1 atomo di calcio, 2 di ossigeno e 2 di idrogeno")
  assert.equal(chemToSpeech("2H2 + O2 -> 2H2O"), "due molecole: 4 atomi di idrogeno, più, 2 atomi di ossigeno, dà, due molecole: 4 atomi di idrogeno e 2 di ossigeno")
  assert.equal(codeToSpeech("soldi = soldi + 8"), "soldi uguale soldi più 8")
  assert.equal(codeToSpeech("k <= 40"), "k minore o uguale a 40")
  assert.equal(bitsToSpeech("01101011"), "zero uno uno zero, uno zero uno uno")
  assert.equal(bitsToSpeech("101"), "uno zero uno")
  assert.equal(plainToSpeech("k ← 5 e 35%"), "k prende 5 e 35 per cento")
})

// a fake speechSynthesis: records what is spoken and lets the test end each utterance
function fakeSynth(list) {
  const synth = { spoken: [], cancelled: 0, getVoices: () => list, cancel() { synth.cancelled += 1 }, speak(u) { synth.spoken.push(u) }, listeners: {}, addEventListener(n, f) { synth.listeners[n] = f }, removeEventListener() {} }
  return synth
}
class FakeUtterance { constructor(text) { this.text = text } }
globalThis.SpeechSynthesisUtterance = FakeUtterance
const voice = (name, lang, localService = true) => ({ name, lang, localService })

test("the player says each segment with the voice of its language, in turn, and skips a language without an accepted voice", () => {
  const synth = fakeSynth([voice("Daniel", "en-GB"), voice("Alice", "it-IT"), voice("Monica", "es-ES")])
  speech.configure({ synth, accepted: { it: ["Alice"], en: ["Daniel"], es: [] } })
  speech.setPreferences({ listen: true, slower: false })
  const ends = []
  const begun = []
  speech.speak([{ lang: "it", text: "Dì" }, { lang: "en", text: "When I arrive" }, { lang: "es", text: "Hola" }, { lang: "it", text: "a Luca" }], { onEnd: (e) => ends.push(e), onSegment: (i) => begun.push(i) })
  assert.equal(synth.spoken.length, 1)
  assert.deepEqual([synth.spoken[0].text, synth.spoken[0].voice.name, synth.spoken[0].rate], ["Dì", "Alice", 1])
  synth.spoken[0].onstart()
  synth.spoken[0].onend()
  assert.deepEqual([synth.spoken[1].text, synth.spoken[1].voice.name, synth.spoken[1].lang], ["When I arrive", "Daniel", "en-GB"])
  synth.spoken[1].onend()
  assert.equal(synth.spoken[2].text, "a Luca", "Spanish has no accepted voice: skipped")
  synth.spoken[2].onend()
  assert.deepEqual(ends, [{ stopped: false }])
  assert.deepEqual(begun, [0])
})

test("slower uses 0.8, English 0.75, Spanish 0.7; another speaker or stopAll stops the one before and the end is told once", () => {
  const synth = fakeSynth([voice("Daniel", "en-GB"), voice("Paulina", "es-MX")])
  speech.configure({ synth, accepted: { it: [], en: ["Daniel"], es: ["Paulina"] } })
  const ends = []
  speech.speak([{ lang: "en", text: "Hello" }], { slower: true, onEnd: (e) => ends.push(["first", e.stopped]) })
  assert.equal(synth.spoken[0].rate, 0.75)
  speech.speak([{ lang: "es", text: "Hola" }], { slower: true, onEnd: (e) => ends.push(["second", e.stopped]) })
  assert.equal(synth.spoken[1].rate, 0.7)
  assert.deepEqual(ends, [["first", true]], "starting another speaker stopped the first")
  assert.ok(synth.cancelled >= 1)
  speech.stopAll()
  assert.deepEqual(ends, [["first", true], ["second", true]])
  speech.stopAll()
  assert.equal(ends.length, 2, "stopping twice tells nothing twice")
  assert.equal(speech.playing(), false)
})

test("a speaker is shown only when the switch is on and a voice passes the gate; a network voice never does", () => {
  const synth = fakeSynth([voice("Daniel", "en-GB"), voice("Google UK English", "en-GB", false)])
  speech.configure({ synth, accepted: { it: [], en: ["Google UK English"], es: [] } })
  speech.setPreferences({ listen: true })
  assert.equal(speech.hasVoice("en"), false, "the only accepted voice is a network voice")
  assert.equal(speech.hasVoice("en", { preview: true }), true, "the teacher's preview may try a local voice")
  speech.configure({ accepted: { it: [], en: ["Daniel"], es: [] } })
  assert.equal(speech.hasVoice("en"), true)
  assert.equal(speech.hasVoice("it"), false)
  speech.setPreferences({ listen: false })
  assert.equal(speech.hasVoice("en"), false, "the Ascolta switch is off")
  speech.setPreferences({ listen: true })
  let calls = 0
  const stop = speech.onChange(() => { calls += 1 })
  synth.listeners.voiceschanged()
  assert.equal(calls, 1, "a late voice list (Safari) tells the speakers")
  stop()
})

test("Prova le voci lists the local voices of it, en and es, with whether each is accepted", () => {
  const synth = fakeSynth([voice("Daniel", "en-GB"), voice("Alice", "it-IT"), voice("Amelie", "fr-FR"), voice("Net", "es-ES", false)])
  speech.configure({ synth, accepted: { it: [], en: ["Daniel"], es: [] } })
  assert.deepEqual(speech.localVoices().map((v) => [v.name, v.language, v.accepted]), [["Daniel", "en", true], ["Alice", "it", false]])
  assert.ok(speech.TRY_SENTENCES.it && speech.TRY_SENTENCES.en && speech.TRY_SENTENCES.es)
})
