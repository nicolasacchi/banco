// The render check's findings about the Italian translation (D-402): «translation missing», «translation empty», «translation overflow», over a small
// stand-in for the document and cards drawn from the golden served lessons. What Chrome adds (layout, the closed `.tr` not drawn) is test/validation/lesson_render_translation_test.rb.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { beforeEach, test } from "node:test"
import { install } from "./fake_dom.mjs"

install()
const fixture = (name) => JSON.parse(readFileSync(new URL(`../../../../test/fixtures/lang/${name}`, import.meta.url), "utf8"))
const { translationEmpty, translationMissing, translationOverflow } = await import("lesson/translation_findings")
const { renderCard } = await import("lesson/cards")
const { renderRich } = await import("lesson/text")
const { el } = await import("lesson/dom")

const names = (path = "") => new Proxy(function () {}, {
  get: (_t, key) => (key === Symbol.toPrimitive ? () => path : key === "toString" ? () => path : typeof key === "symbol" ? undefined : names(path ? `${path}.${key}` : String(key))),
  apply: () => path
})
const t = new Proxy({ translation: { toggle: "Traduzione", unit: "Mostra la traduzione: %{words}" } }, { get: (target, key) => (key in target ? target[key] : names(String(key))) })
const contextOf = (body) => ({
  subject: body.subject, t, items: names("items"), lang: body.lang, trScopes: [body], glossary: new Map(), noSpeech: true, renderCheck: true, mount() {}, track() {}, firstUse: new Map(), topicHref: () => "#",
  rich(text) { return el("div", { class: "rich" }, renderRich(text, this)) }
})

beforeEach(() => install())

for (const file of ["served_lesson.json", "served_lesson_es.json"]) {
  test(`${file}: the golden cards have no missing, empty or overflowing translation`, () => {
    const body = fixture(file)
    for (const card of body.cards) {
      const article = renderCard(card, contextOf(body), { kicker: "", newRoles: [] })
      article.rect = { left: 0, right: 390 }
      const out = []
      translationMissing(article, out)
      translationEmpty(article, out)
      translationOverflow(article, out)
      assert.deepEqual(out, [], `card ${card.n}`)
    }
  })
}

test("a string that code built, in a target-language element with no translation unit, is «translation missing»", () => {
  const body = fixture("served_lesson.json")
  const card = el("article", {}, el("p", { lang: "en", text: "A sentence the page built by hand" }), el("p", { lang: "en", text: "ok" }), el("p", { lang: "it", text: "Una frase italiana normale" }))
  const out = []
  translationMissing(card, out)
  assert.equal(out.length, 1)
  assert.equal(out[0].code, "E-LESSON-RENDER")
  assert.match(out[0].message, /^translation missing: "A sentence the page built by hand" is en text/)
})

test("text in a translation unit, in a .tr, left out on purpose, in code or in SVG is not missing", () => {
  const card = el("article", {},
    el("p", { lang: "es", "data-translated": "" }, "Una frase con su traducción", el("span", { class: "tr", lang: "it", text: "Una frase con la sua traduzione" })),
    el("p", { lang: "es", "data-tr-exempt": "", text: "Un fragmento sin traducción" }),
    el("p", { lang: "es" }, el("code", { text: "print hello" })),
    el("svg", { lang: "es" }, el("text", { text: "etiqueta del dibujo" })))
  const out = []
  translationMissing(card, out)
  assert.deepEqual(out, [])
})

test("text of a language that is neither en nor es (the chrome, an Italian gloss) is never asked for a translation", () => {
  const card = el("article", {}, el("p", { text: "Tocca per girare la scheda" }), el("p", { lang: "it", text: "Questa è una glossa italiana" }))
  const out = []
  translationMissing(card, out)
  assert.deepEqual(out, [])
})

test("no more than five missing translations are reported for one card", () => {
  const card = el("article", {}, ...Array.from({ length: 9 }, (_v, i) => el("p", { lang: "en", text: `Sentence number ${i} here` })))
  const out = []
  translationMissing(card, out)
  assert.equal(out.length, 5)
})

test("a .tr with no text is «translation empty»", () => {
  const card = el("article", {}, el("p", { text: "Target" }), el("p", { class: "tr", lang: "it", text: "  " }))
  const out = []
  translationEmpty(card, out)
  assert.equal(out.length, 1)
  assert.match(out[0].message, /^translation empty/)
})

test("an open translation wider than its card or than the window is «translation overflow»; a closed one has no box", () => {
  const card = el("article", {})
  card.rect = { left: 0, right: 390 }
  const wide = el("p", { class: "tr", lang: "it", text: "Una riga" })
  wide.rect = { left: 0, right: 520, width: 520 }
  const fine = el("p", { class: "tr", lang: "it", text: "Una riga" })
  fine.rect = { left: 10, right: 380, width: 370 }
  const closed = el("p", { class: "tr", lang: "it", text: "Chiusa" })
  closed.noBox = true
  closed.rect = { left: 0, right: 900, width: 900 }
  const clipped = el("p", { class: "tr", lang: "it", text: "Tagliata" })
  clipped.rect = { left: 10, right: 380, width: 370 }
  clipped.scrollW = 500
  card.append(wide, fine, closed, clipped)
  const out = []
  translationOverflow(card, out)
  assert.equal(out.length, 2)
  assert.ok(out.every((f) => f.code === "E-LESSON-RENDER" && /^translation overflow/.test(f.message)))
})

test("a card drawn with one field the author did not pair shows up as «translation missing»", () => {
  const body = fixture("served_lesson.json")
  const card = JSON.parse(JSON.stringify(body.cards[0]))
  delete card.blocks[0].tr // the block's Italian is gone: the text is target text with no unit
  const article = renderCard(card, contextOf(body), { kicker: "", newRoles: [] })
  const out = []
  translationMissing(article, out)
  assert.ok(out.some((f) => /After a modal verb/.test(f.message)), JSON.stringify(out))
})
