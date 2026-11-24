// D-402: a `sentence` figure of a bilingual lesson, as the server serves it (test/fixtures/lang/served_sentence_{en,es}.json, checked by
// test/lib/lessons/bilingual_figures_test.rb): the sentence and every part keep `text_<lang>` (never folded into text_it), the alt and the part
// labels are folded into `_it` with their Italian in the figure's own `tr`. The renderer must draw it with no error, the text in the language it is written in.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const { layout, describe } = await import("lesson/diagrams/registry")
const { semantic, textOf, keyOf, langOf } = await import("lesson/diagrams/sentence")
const dir = new URL("../../../../test/fixtures/lang/", import.meta.url)
const measure = (text, px) => ({ w: Math.ceil(String(text).length * px * 0.5), h: Math.ceil(px * 1.4) })
const SUBJECT = { en: "english", es: "spanish" }

for (const lang of ["en", "es"]) {
  const served = JSON.parse(readFileSync(new URL(`served_sentence_${lang}.json`, dir), "utf8"))
  for (const where of ["hero", "block"]) {
    const figure = served[where]
    for (const layoutName of ["line", "centre"]) {
      test(`${lang}: the bilingual sentence figure of the ${where} is drawn in layout ${layoutName}, the text in text_${lang}`, () => {
        assert.equal(keyOf(figure), `text_${lang}`)
        assert.equal(langOf(figure), lang)
        assert.equal(semantic(figure), null, "the sentence and its parts are in the same key: no semantic error")
        const scene = layout({ ...figure, layout: layoutName }, { width: 900, fontPx: 20, subject: SUBJECT[lang], measure, state: 0 })
        assert.ok(!scene.error, scene.error?.message)
        const parts = scene.labels.filter((l) => l.key?.endsWith(":text"))
        assert.deepEqual(parts.map((l) => l.text_it).sort(), figure.parts.map((p) => textOf(p)).sort(), "each part is drawn with its own text (the centre layout reorders them)")
        assert.ok(parts.every((l) => l.lang === lang), "and in its language")
        const names = scene.labels.filter((l) => l.key?.endsWith(":label")).map((l) => l.text_it)
        assert.deepEqual(names.sort(), figure.parts.map((p) => p.label_it).sort(), "the part labels are the folded target names")
        assert.ok(names.every((n) => figure.tr[n]), "each of them has its Italian in the figure's tr")
      })
    }
  }
  test(`${lang}: the description reads the sentence and the parts of the served figure`, () => {
    const text = describe(served.hero, { subject: SUBJECT[lang] })
    for (const part of served.hero.parts) assert.match(text, new RegExp(`«${textOf(part)}»`))
  })
}

test("a sentence written in text_it beside a part in text_es is refused: the sentence and its parts are one language", () => {
  const bad = { type: "sentence", alt_it: "x", text_it: "Lei legge", parts: [{ id: "v", text_es: "lee", role: "verb" }] }
  assert.match(semantic(bad)?.message ?? "", /language of its sentence/)
})

// D-402: a part with no label of its own is named by its role; in a bilingual lesson the name is the palette's `label_en|es`, target text, and the figure's panel says the
// Italian one; a legacy lesson (no lang) keeps the Italian name.
test("the role name of a part with no label is drawn in the language of a bilingual lesson, and its Italian is in the panel; a legacy lesson keeps the Italian name", async () => {
  const { roleNamePairs } = await import("lesson/diagrams/sentence")
  const figure = { type: "sentence", alt_it: "Una frase con un verbo e un complemento.", text_es: "Ella lee", parts: [{ id: "s", text_es: "Ella", role: "verb" }, { id: "v", text_es: "lee", role: "od" }] }
  const draw = (lang) => layout(figure, { width: 900, fontPx: 20, subject: "spanish", measure, state: 0, lang })
  const names = (scene) => scene.labels.filter((l) => l.key?.endsWith(":label"))
  assert.deepEqual(names(draw("es")).map((l) => l.text_it), ["verbo", "complemento directo"])
  assert.ok(names(draw("es")).every((l) => l.lang === "es"), "target text: it carries its language")
  assert.deepEqual(names(draw(undefined)).map((l) => l.text_it), ["verbo", "complemento diretto"])
  assert.ok(names(draw(undefined)).every((l) => l.lang === undefined), "a legacy lesson is drawn as it was")
  assert.deepEqual(roleNamePairs(figure, "spanish", "es"), [["verbo", "verbo"], ["complemento directo", "complemento diretto"]])
  assert.deepEqual(roleNamePairs(figure, "spanish", undefined), [])
  assert.deepEqual(roleNamePairs({ ...figure, parts: [{ ...figure.parts[0], label_it: "mine" }] }, "spanish", "es"), [], "a part with its own label has none")
})
