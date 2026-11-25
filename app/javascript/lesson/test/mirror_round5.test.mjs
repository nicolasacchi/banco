// mirror, round 5 of the bilingual tooling: a piece with no partner keeps its place in a narrow row, `meaning` is its own link kind, and a bilingual lesson's
// figure draws its chrome words in the language of the lesson with their Italian in its panel. Markup in a note or an alt is refused.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const mirror = await import("lesson/diagrams/words/mirror")
const awaitedRun = await import("lesson/diagrams/run")
const { estimate } = await import("lesson/diagrams/common")
const { TEXT, TARGET_TEXT, mirrorChromePairs } = await import("lesson/diagrams/words/texts")
const measure = (text, px, maxW) => estimate(text, px, maxW)

const ALT = "Una frase italiana sopra la stessa frase nell'altra lingua, pezzo per pezzo, con le coppie."
const MIEI = {
  type: "mirror", alt_it: ALT,
  rows: [{
    pieces_it: ["I", "miei", "cugini"], pieces_es: ["mis", "primos"],
    links: [[1, 0, "meaning"], [2, 1, "same"]],
    notes: [{ side: "it", piece: 0, note_it: "l'articolo non c'è in spagnolo" }]
  }]
}
const layout = (data, extra = {}) => mirror.layout(data, { width: 390, fontPx: 20, subject: "spanish", measure, forceNarrow: true, ...extra })

test("narrow: the pairs follow the Italian sentence; a piece with no partner keeps its place, the other side empty (never at the end of the row)", () => {
  const row = MIEI.rows[0]
  assert.deepEqual(mirror.pairsOf(row, "pieces_es", row.links).map((p) => [p.a, p.b]), [[0, null], [1, 0], [2, 1]])
  // a piece of the other language with no link stands after the pair of the piece before it
  const extra = { pieces_it: ["Io", "mangio"], pieces_es: ["Yo", "me", "como"], links: [[0, 0, "same"], [1, 2, "same"]] }
  assert.deepEqual(mirror.pairsOf(extra, "pieces_es", extra.links).map((p) => [p.a, p.b]), [[0, 0], [null, 1], [1, 2]])
  const first = { pieces_it: ["Io"], pieces_es: ["Yo", "mismo"], links: [[0, 1, "same"]] }
  assert.deepEqual(mirror.pairsOf(first, "pieces_es", first.links).map((p) => [p.a, p.b]), [[null, 0], [0, 1]])
  const scene = layout(MIEI)
  assert.ok(!scene.error, scene.error?.message)
  const order = scene.labels.filter((l) => /^r1:i\d+|^r1:t\d+/.test(l.key ?? "") || /^r1[it]\d+:\d+:t$/.test(l.key ?? "")).sort((a, b) => a.y - b.y || a.x - b.x).map((l) => l.text_it)
  assert.deepEqual(order, ["I", "miei", "mis", "cugini", "primos"])
})

test("meaning is drawn with its own word, line and mark; same stays «uguale»", () => {
  assert.equal(TEXT.link_meaning, "stesso significato")
  const scene = layout(MIEI, { width: 1280, forceNarrow: false })
  assert.ok(!scene.error, scene.error?.message)
  const words = scene.labels.filter((l) => /^key:/.test(l.key ?? "")).map((l) => l.text_it)
  assert.deepEqual(words.sort(), ["stesso significato", "uguale"])
  assert.ok(scene.shapes.some((s) => s.cls === "dg-mr-link dg-mr-meaning"))
  assert.ok(scene.shapes.some((s) => s.kind === "marker" && s.key === "key:meaning:m"), "a mark, never the line alone")
  assert.ok(!scene.shapes.some((s) => s.kind === "marker" && s.key === "key:same:m"))
  assert.equal(mirror.semantic(MIEI, { subject: "spanish" }), null, "a meaning link needs no note")
})

test("in a bilingual lesson the chrome words are the lesson's language, labelled with it; the Italian is in the panel's pairs; a legacy lesson stays Italian", () => {
  for (const [lang, subject, key, side] of [["es", "spanish", "pieces_es", "español"], ["en", "english", "pieces_en", "English"]]) {
    const { pieces_es: pieces, ...rest } = MIEI.rows[0]
    const data = { ...MIEI, rows: [{ ...rest, [key]: pieces }] }
    for (const [width, forceNarrow] of [[1280, false], [390, true], [320, true]]) {
      const scene = mirror.layout(data, { width, fontPx: 20, subject, lang, measure, forceNarrow })
      assert.ok(!scene.error, scene.error?.message)
      const chrome = scene.labels.filter((l) => /(?::side-|:k\d|:none|^key:|:title)/.test(l.key ?? ""))
      assert.ok(chrome.length >= 2, `${lang} ${width}: chrome is drawn`)
      for (const l of chrome) {
        assert.equal(l.lang, lang, `${l.text_it} carries the language of the lesson`)
        assert.ok(!Object.values(TEXT).includes(l.text_it) || Object.values(TARGET_TEXT[lang]).includes(l.text_it), `${l.text_it} is not Italian`)
      }
      if (width === 1280) assert.ok(chrome.some((l) => l.text_it === side))
    }
    const pairs = mirrorChromePairs(data, lang)
    assert.ok(pairs.some(([t, it]) => t === TARGET_TEXT[lang].link_meaning && it === "stesso significato"))
    assert.ok(pairs.some(([t, it]) => t === TARGET_TEXT[lang].link_same && it === "uguale"))
    assert.ok(pairs.some(([t, it]) => t === TARGET_TEXT[lang].link_none && it === "senza coppia"))
    assert.ok(pairs.some(([, it]) => it === "Italiano"))
    const legacy = mirror.layout(data, { width: 390, fontPx: 20, subject, measure, forceNarrow: true })
    assert.ok(legacy.labels.filter((l) => /(?::side-|:k\d|:none)/.test(l.key ?? "")).every((l) => l.lang === undefined && Object.values(TEXT).includes(l.text_it)), "legacy: Italian, no language")
    assert.deepEqual(mirrorChromePairs(data, null), [])
  }
})

test("markup in a mirror note or in an alt is refused: plain text, a quoted word is written in «…»", () => {
  const note = { ...MIEI, rows: [{ ...MIEI.rows[0], notes: [{ side: "it", piece: 0, note_it: "scrivi [[es:los]], non l'articolo" }] }] }
  const found = layout(note)
  assert.equal(found.error.code, "E-LESSON-DIAGRAM")
  assert.equal(found.error.path, "/rows/0/notes/0/note_it")
  assert.match(found.error.message, /«…»/)
  const alt = layout({ ...MIEI, alt_it: "Una frase italiana sopra la stessa frase in [[es:español]], pezzo per pezzo, con le coppie." })
  assert.equal(alt.error.code, "E-LESSON-ALT")
  assert.equal(alt.error.path, "/alt_it")
})

test("the plain-text rule is the same for every language and every figure: note_es, note_en, alt_en and a nested question are refused with their pointer (round 6)", () => {
  const { plainTextBreach } = awaitedRun
  assert.deepEqual(plainTextBreach({ rows: [{ notes: [{ note_es: "mira [[es:el]]" }] }] }), { path: "/rows/0/notes/0/note_es", message: "note_es is plain text: use «…» for a quoted word, not [[..]] markup", code: "E-LESSON-DIAGRAM" })
  assert.equal(plainTextBreach({ states: [{ question_en: "[[en:who]]?" }] }).path, "/states/0/question_en")
  assert.equal(plainTextBreach({ alt_en: "a [[en:b]]" }).code, "E-LESSON-ALT")
  assert.equal(plainTextBreach({ label_it: "a [[es:el]] label", caption_it: "[[es:x]]" }), null, "labels and captions are rich text")
})
