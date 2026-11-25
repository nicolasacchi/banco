// The chrome words that two more figures draw themselves, in the language of a bilingual lesson with their Italian under the translation toggle (round 7 of
// the bilingual tooling, like the mirror's of round 5): the axis of a tense line (adesso, ← prima, dopo →) and the legend of word_parts (the marks, the
// strong syllable's key). A legacy lesson keeps its Italian.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"
import { install } from "./fake_dom.mjs"

const timeline = await import("lesson/diagrams/time/timeline")
const wordParts = await import("lesson/diagrams/words/word_parts")
const { TEXT: TIME, TARGET_TEXT: TIME_TARGET } = await import("lesson/diagrams/time/texts")
const { TEXT: WORDS, TARGET_TEXT: WORDS_TARGET } = await import("lesson/diagrams/words/texts")
const { estimate } = await import("lesson/diagrams/common")
const { translationPanel } = await import("lesson/diagrams/draw")
const { load } = await import("lesson/diagrams/registry")
const measure = (text, px, maxW) => estimate(text, px, maxW)

const TENSE = (key, text) => ({
  type: "timeline", alt_it: "Una linea dell'ordine: prima, adesso, dopo. Segna quando succede una frase di prova.", scale: "tense", window: ["-3", "3"],
  marks: [{ id: "a", at: "1", span: "point", [key]: text, label_it: "quando?" }]
})

test("the axis of a tense line is drawn in the language of a bilingual lesson, labelled with it; a legacy lesson draws Italian, no language", () => {
  for (const [lang, subject, key, text, now, before, after] of [["en", "english", "text_en", "I arrive", "now", "← before", "after →"], ["es", "spanish", "text_es", "llego", "ahora", "← antes", "después →"]]) {
    for (const width of [1280, 390, 320]) {
      const scene = timeline.layout(TENSE(key, text), { width, fontPx: 20, subject, lang, measure })
      assert.ok(!scene.error, scene.error?.message)
      const axis = Object.fromEntries(scene.labels.filter((l) => ["now", "before", "after"].includes(l.key)).map((l) => [l.key, l]))
      assert.deepEqual([axis.now.text_it, axis.before.text_it, axis.after.text_it], [now, before, after], `${lang} ${width}`)
      for (const l of Object.values(axis)) assert.equal(l.lang, lang, `${l.text_it} carries the language of the lesson`)
    }
    const legacy = timeline.layout(TENSE(key, text), { width: 390, fontPx: 20, subject, measure })
    const axis = legacy.labels.filter((l) => ["now", "before", "after"].includes(l.key))
    assert.deepEqual(axis.map((l) => l.text_it), [TIME.now, `← ${TIME.before}`, `${TIME.after} →`])
    assert.ok(axis.every((l) => l.lang === undefined), "legacy: Italian, no language")
    // the Italian is under the toggle: the figure's pairs
    assert.deepEqual(timeline.chromePairs(TENSE(key, text), lang), [[TIME_TARGET[lang].now, "adesso"], [TIME_TARGET[lang].before, "prima"], [TIME_TARGET[lang].after, "dopo"]])
    assert.deepEqual(timeline.chromePairs(TENSE(key, text), null), [])
  }
  assert.deepEqual(timeline.chromePairs({ type: "timeline", scale: "years" }, "es"), [], "a dated line has no such axis")
})

const SPANISH = { type: "word_parts", alt_it: "La parola puedo: la radice cambia dove batte la voce.", view: "syllables", words: [{ form_es: "p[ue]d|o", label_it: "yo" }] }

test("the legend of word_parts is drawn in the language of a bilingual lesson, with the strong-syllable key; a legacy lesson draws Italian", () => {
  for (const [lang, stem, ending, strong] of [["es", "raíz", "terminación", "Aquí va el acento"], ["en", "root", "ending", "Stress here"]]) {
    const scene = wordParts.layout(SPANISH, { width: 700, fontPx: 20, subject: "spanish", lang, measure })
    assert.ok(!scene.error, scene.error?.message)
    const key = scene.labels.filter((l) => /^key:/.test(l.key ?? ""))
    assert.ok(key.length >= 3, "the marks and the strong key are drawn")
    for (const l of key) {
      assert.equal(l.lang, lang, `${l.text_it} carries the language of the lesson`)
      assert.ok(!Object.values(WORDS).includes(l.text_it) || Object.values(WORDS_TARGET[lang]).includes(l.text_it), `${l.text_it} is not Italian`)
    }
    const texts = key.map((l) => l.text_it)
    assert.ok(texts.includes(WORDS_TARGET[lang].mark_stem) && texts.includes(WORDS_TARGET[lang].mark_ending) && texts.includes(strong))
    assert.equal(WORDS_TARGET[lang].mark_stem, stem)
    assert.equal(WORDS_TARGET[lang].mark_ending, ending)
    const pairs = wordParts.chromePairs(SPANISH, lang)
    assert.ok(pairs.some(([t, it]) => t === stem && it === "radice"))
    assert.ok(pairs.some(([t, it]) => t === ending && it === "desinenza"))
    assert.ok(pairs.some(([t, it]) => t === strong && it === "Qui batte la voce"))
    const legacy = wordParts.layout(SPANISH, { width: 700, fontPx: 20, subject: "spanish", measure })
    const italian = legacy.labels.filter((l) => /^key:/.test(l.key ?? ""))
    assert.ok(italian.length >= 3 && italian.every((l) => l.lang === undefined && Object.values(WORDS).includes(l.text_it)), "legacy: Italian, no language")
    assert.deepEqual(wordParts.chromePairs(SPANISH, null), [])
  }
  // a decode view has no legend, so nothing to say
  assert.deepEqual(wordParts.chromePairs({ ...SPANISH, view: "decode", words: [{ form_es: "p[ue]d|o", parts_it: ["a", "b"], meaning_it: "io posso" }] }, "es"), [])
})

test("the figure's translation panel lists the axis words and the legend words as «target → italiano»", async () => {
  await load("timeline")
  await load("word_parts")
  install()
  const ctx = { lang: "es", subject: "spanish", trScopes: [{ lang: "es", tr: {} }], t: {}, items: {}, noSpeech: true }
  const axis = translationPanel(TENSE("text_es", "llego"), ctx)
  assert.ok(axis, "a panel with the axis words")
  assert.deepEqual([...axis.querySelectorAll("li")].map((li) => li.textContent), ["ahora → adesso", "antes → prima", "después → dopo"])
  const legend = translationPanel(SPANISH, ctx)
  assert.ok([...legend.querySelectorAll("li")].some((li) => li.textContent === "Aquí va el acento → Qui batte la voce"))
})
