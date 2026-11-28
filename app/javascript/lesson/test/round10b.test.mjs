// Round 10b (D-409): the narrow mirror draws a row with crossing links as two whole sentences, each in its own order, and names its languages in every narrow form;
// a bilingual lesson's Italian gloss in a word_parts figure follows the translation toggle; an English lesson's bar_model prints a decimal point.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const mirror = await import("lesson/diagrams/words/mirror")
const wordParts = await import("lesson/diagrams/words/word_parts")
const barModel = await import("lesson/diagrams/chart/bar_model")
const { localNumber } = await import("lesson/diagrams/chart/format")
const { estimate } = await import("lesson/diagrams/common")
const measure = (text, px, maxW) => estimate(text, px, maxW)

const ALT = "Una frase italiana sopra la stessa frase nell'altra lingua, pezzo per pezzo, con le coppie."
// «Tom gioca spesso a tennis» / «Tom often plays tennis»: the adverb comes before the verb in English
const ORDER = { pieces_it: ["Tom", "gioca", "spesso", "a tennis"], pieces_en: ["Tom", "often", "plays", "tennis"], links: [[0, 0, "same"], [1, 2, "meaning"], [2, 1, "meaning"], [3, 3, "meaning"]] }
const data = (...rows) => ({ type: "mirror", alt_it: ALT, rows })
const narrow = (d, extra = {}) => mirror.layout(d, { width: 390, fontPx: 20, subject: "english", measure, forceNarrow: true, ...extra })
const labelOf = (scene, key) => scene.labels.find((l) => l.key === key)

test("crosses: the links of two sentences in another order cross; the same order, a piece linked twice and no links do not", () => {
  assert.equal(mirror.crosses(ORDER.links), true)
  assert.equal(mirror.crosses([[0, 0, "same"], [1, 1, "same"], [2, 2, "same"]]), false)
  assert.equal(mirror.crosses([[0, 0, "same"], [0, 1, "same"], [1, 2, "same"]]), false)
  assert.equal(mirror.crosses([]), false)
})

test("390 px, links that cross: each sentence is whole in its own order, the English column reads «Tom often plays tennis»", () => {
  const scene = narrow(data(ORDER))
  assert.ok(!scene.error, scene.error?.message)
  const ys = (letter, n) => Array.from({ length: n }, (_, k) => labelOf(scene, `r1${letter}${k + 1}:t`))
  const it = ys("i", 4)
  const en = ys("t", 4)
  assert.deepEqual(it.map((l) => l.text_it), ["Tom", "gioca", "spesso", "a tennis"])
  assert.deepEqual(en.map((l) => l.text_it), ["Tom", "often", "plays", "tennis"])
  for (const col of [it, en]) assert.ok(col.every((l, k) => k === 0 || l.y > col[k - 1].y), "one under the other, in the order of the sentence")
  assert.ok(Math.max(...it.map((l) => l.y)) < Math.min(...en.map((l) => l.y)), "the Italian sentence first, the other under it")
  // the pair numbers say what goes with what: «gioca» is 2 and so is «plays»
  const number = (key) => labelOf(scene, key).text_it
  assert.equal(number("r1:n1:it:t"), "2")
  assert.equal(number("r1:n1:tg:t"), "2")
  assert.equal(number("r1:n2:it:t"), "3")
  assert.equal(number("r1:n2:tg:t"), "3")
  const plates = scene.shapes.filter((s) => /^r1:n\d:(it|tg)$/.test(s.key ?? ""))
  assert.equal(plates.length, 8, "a plate on every piece (every piece is linked)")
  assert.ok(scene.shapes.some((s) => s.key === "r1:l1:tg" && /dg-mr-meaning/.test(s.cls)), "the line of a link in the style of its kind")
  assert.ok(scene.labels.some((l) => l.key === "key:meaning:t"), "the legend of the kinds is drawn once")
})

test("390 px, links that cross: the two languages are named over their sentences, in the language of a bilingual lesson too", () => {
  const scene = narrow(data(ORDER))
  const [it, en] = ["r1:side-it", "r1:side-tg"].map((k) => labelOf(scene, k))
  assert.deepEqual([it.text_it, en.text_it], ["Italiano", "Inglese"])
  assert.ok(it.y < labelOf(scene, "r1i1:t").y && en.y < labelOf(scene, "r1t1:t").y && it.y < en.y)
  const bilingual = narrow(data(ORDER), { lang: "en" })
  assert.deepEqual(["r1:side-it", "r1:side-tg"].map((k) => [labelOf(bilingual, k).text_it, labelOf(bilingual, k).lang]), [["Italian", "en"], ["English", "en"]])
})

test("390 px: in a crossed row a piece with two links has a plate for each, and a piece with none says «senza coppia»; an uncrossed row keeps its pairs", () => {
  const plain = { pieces_it: ["Ho", "fame"], pieces_en: ["I", "am", "hungry"], links: [[0, 0, "meaning"], [0, 1, "meaning"], [1, 2, "meaning"]] }
  const list = narrow(data(plain))
  assert.equal(list.shapes.filter((s) => /^r1:n\d:(it|tg)$/.test(s.key ?? "")).length, 0, "uncrossed: the numbered pairs, not the whole sentences")
  assert.equal(list.shapes.filter((s) => /^r1:n\d$/.test(s.key ?? "")).length, 3)
  const crossed = { pieces_it: ["Ho", "fame", "oggi"], pieces_en: ["Today", "I", "am", "hungry"], links: [[0, 1, "meaning"], [0, 2, "meaning"], [1, 3, "meaning"], [2, 0, "meaning"]] }
  const scene = narrow(data(crossed))
  assert.ok(!scene.error, scene.error?.message)
  assert.equal(scene.shapes.filter((s) => /^r1:n\d:it$/.test(s.key ?? "")).length, 4)
  assert.equal(scene.shapes.filter((s) => /^r1:n\d:tg$/.test(s.key ?? "")).length, 4)
  const ho = scene.shapes.find((s) => s.key === "r1i1")
  const plates = scene.shapes.filter((s) => /^r1:n[01]:it$/.test(s.key ?? ""))
  assert.equal(plates.length, 2)
  assert.ok(plates.every((p) => p.cy > ho.y && p.cy < ho.y + ho.h), "both plates of «Ho» sit at its box")
  const lone = { pieces_it: ["Ieri", "mangio", "pesce"], pieces_en: ["I", "ate", "fish", "yesterday"], links: [[0, 3, "meaning"], [2, 2, "same"], [1, 1, "meaning"]], notes: [{ side: "en", piece: 0, note_it: "il pronome si scrive sempre" }] }
  const unlinked = narrow(data(lone))
  assert.ok(!unlinked.error, unlinked.error?.message)
  assert.deepEqual(unlinked.labels.filter((l) => /^r1:none/.test(l.key ?? "")).map((l) => l.text_it), ["senza coppia"])
})

test("the narrowest layout (each pair stacked) names the two languages over the first pair", () => {
  const row = { pieces_it: ["I", "miei", "cugini"], pieces_es: ["mis", "primos", "viven"], links: [[0, 0, "same"], [1, 1, "same"], [2, 2, "same"]] }
  const same = (d) => ({ ...d, same_ok: true })
  const scene = mirror.layout(same(data(row)), { width: 320, fontPx: 34, subject: "spanish", measure, forceNarrow: true })
  assert.ok(!scene.error, scene.error?.message)
  assert.ok(scene.shapes.some((s) => /^r1:l\d$/.test(s.key ?? "") && s.x1 === s.x2), "stacked: the upright links")
  const [it, tg] = ["r1:side-it", "r1:side-tg"].map((k) => labelOf(scene, k))
  assert.deepEqual([it.text_it, tg.text_it], ["Italiano", "Spagnolo"])
  const first = (key) => scene.shapes.find((s) => s.key === key)
  assert.ok(it.y + it.h <= first("r1i1:0").y, "the Italian name is over the first Italian piece")
  assert.ok(tg.y + tg.h <= first("r1t1:0").y && tg.y > first("r1i1:0").y, "the other name is over the first piece of the other language, under the Italian one")
  assert.equal(scene.labels.filter((l) => /:side-/.test(l.key ?? "")).length, 2, "once for the row, not for every pair")
  const bilingual = mirror.layout(same(data(row)), { width: 320, fontPx: 34, subject: "spanish", measure, forceNarrow: true, lang: "es" })
  assert.deepEqual(["r1:side-it", "r1:side-tg"].map((k) => labelOf(bilingual, k).text_it), ["italiano", "español"])
})

// ---- word_parts: the Italian gloss follows the translation toggle ----------------------------------------------------------------------

const WORD = { form_en: "banana", syllables: "ba-na-na", stress: 2 }
const GLOSS = { type: "word_parts", alt_it: "Una parola divisa in pezzi e in sillabe, con la sillaba forte segnata.", view: "syllables", words: [{ ...WORD, label_it: "una banana" }] }
const DECODE = { type: "word_parts", alt_it: "Una parola divisa in pezzi, con il significato di ogni pezzo e della parola intera.", view: "decode", words: [{ form_en: "un|happy", parts_it: ["non", "felice"], meaning_it: "infelice" }] }
const draw = (d, extra = {}) => wordParts.layout(d, { width: 390, fontPx: 20, subject: "english", measure, ...extra })
const glossed = (scene) => scene.labels.filter((l) => /dg-gloss/.test(l.cls)).map((l) => l.text_it)

test("word_parts: in a bilingual lesson the Italian caption, the meanings of the pieces and the whole meaning carry dg-gloss, the toggle's class", () => {
  assert.deepEqual(glossed(draw(GLOSS, { lang: "en" })), ["una banana"])
  assert.deepEqual(glossed(draw(DECODE, { lang: "en" })), ["non", "felice", "Tutto insieme: infelice"])
  const note = draw(DECODE, { lang: "en" }).shapes.find((s) => /dg-wp-note/.test(s.cls ?? ""))
  assert.match(note.cls, /dg-gloss/, "the box of the whole meaning goes with its text")
})

test("word_parts: a legacy lesson has no toggle, so its Italian is always drawn; a gloss that the figure's tr translates is target text and stays", () => {
  assert.deepEqual(glossed(draw(GLOSS)), [])
  assert.deepEqual(glossed(draw(DECODE)), [])
  const paired = { ...GLOSS, words: [{ ...WORD, label_it: "a fruit" }], tr: { "a fruit": "un frutto" } }
  assert.deepEqual(glossed(draw(paired, { lang: "en" })), [])
  const arrow = { ...GLOSS, words: [WORD, { form_en: "bananas", syllables: "ba-na-nas", stress: 2 }], arrows: [{ from: 0, to: 1, label_it: "più di uno" }] }
  assert.deepEqual(glossed(draw(arrow, { lang: "en" })), ["più di uno"])
  assert.deepEqual(glossed(draw(arrow)), [])
})

// ---- bar_model: the decimal mark of the lesson's language --------------------------------------------------------------------------------

const PARTS = { type: "bar_model", alt_it: "Una barra del cento per cento con due parti, diciotto virgola otto e il resto.", view: "parts", total: { value: "100" }, bars: [{ label_it: "Young people", parts: [{ value: "18,8", label_it: "with a job" }, { value: "81,2", label_it: "the rest" }] }] }
const PERCENT = { type: "bar_model", alt_it: "Una scala doppia: i giovani con un lavoro sono il diciotto virgola otto per cento della base.", view: "percent", base: "1000", unit: "none", marks: [{ pct: "18,8", label_it: "with a job" }] }
const barTexts = (d, extra = {}) => barModel.layout(d, { width: 390, fontPx: 20, subject: "english", measure, ...extra }).labels.map((l) => l.text_it)

test("localNumber: an English lesson swaps the marks, Italian and Spanish print the number as written", () => {
  assert.equal(localNumber("18,8", "en"), "18.8")
  assert.equal(localNumber("1.860,5", "en"), "1,860.5")
  assert.equal(localNumber("1.860,5", "es"), "1.860,5")
  assert.equal(localNumber("18,8", undefined), "18,8")
})

test("bar_model: the values of an English lesson's figure are printed with a point, an Italian lesson's with a comma", () => {
  const en = barTexts(PARTS, { lang: "en" })
  assert.ok(en.includes("18.8") && en.includes("81.2"), en.join("|"))
  assert.ok(!en.some((t) => t.includes("18,8")))
  const it = barTexts(PARTS)
  assert.ok(it.includes("18,8") && it.includes("81,2"), it.join("|"))
  const es = barTexts(PARTS, { lang: "es", subject: "spanish" })
  assert.ok(es.includes("18,8"), es.join("|"))
  const pct = barTexts(PERCENT, { lang: "en" })
  assert.ok(pct.some((t) => t.startsWith("18.8%")), pct.join("|"))
  assert.ok(barTexts(PERCENT).some((t) => t.startsWith("18,8%")))
})
