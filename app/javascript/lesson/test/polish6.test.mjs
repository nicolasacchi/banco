// Polish after the wave 3 authors' reports (D-310): markup that reached the page as text, the short name of a title, the texts inside a
// control, the neutral words of tiles, the bar labels that keep their formula, a mirror piece whose word does not fit beside its icon.
// The visual half is test/validation/lesson_polish_gallery_test.rb (Chrome, the galleries polish-spanish.md and polish-math.md).
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { rawMarkup } = await import("lesson/raw_markup")
const { insideControl, oneWord, plainText, shortTitle } = await import("lesson/text")
const { tilesTexts, nameOf } = await import("lesson/checks/tiles")
const { howtoKey } = await import("lesson/checks/howto")
const barModel = await import("lesson/diagrams/chart/bar_model")
const mirror = await import("lesson/diagrams/words/mirror")
const { estimate } = await import("lesson/diagrams/common")

test("raw markup: a span or a formula printed as written is found; money, an escaped dollar and plain words are not", () => {
  assert.equal(rawMarkup("[[es:hablar]]: hablo"), "[[es:hablar]]")
  assert.equal(rawMarkup("-er: [[es:comer]]"), "[[es:comer]]")
  assert.equal(rawMarkup("[[time|it:momento]] e basta"), "[[time|it:momento]]")
  assert.equal(rawMarkup("fattori di $a^7$: 7"), "$a^7$")
  assert.equal(rawMarkup("Prodotto di $a^2 \\cdot a^3$"), "$a^2 \\cdot a^3$")
  assert.equal(rawMarkup("x^2: 4"), null) // TeX without dollars is a plain-text label, written that way on purpose
  assert.equal(rawMarkup("It costs $5 and $6 in total."), null)
  assert.equal(rawMarkup("Il prezzo è \\$4, non \\$5."), null)
  assert.equal(rawMarkup("hablar: hablo"), null)
  assert.equal(rawMarkup("a[[1, 2]]"), null)
})

test("a title's short name stops at the first colon followed by a space, never at one inside a formula", () => {
  assert.equal(shortTitle("Esempio A: risolvi"), "Esempio A")
  assert.equal(shortTitle("La funzione $f: A \\to B$: che cos'è"), "La funzione $f: A \\to B$")
  assert.equal(shortTitle("[[es:Lo]] è la cosa"), "[[es:Lo]] è la cosa")
  assert.equal(shortTitle("Senza due punti"), "Senza due punti")
})

test("text inside a control keeps its markup but carries no control of its own: no speaker, no glossary bubble, no link", () => {
  const ctx = { subject: "spanish", glossary: new Map([["tilde", {}]]), noSpeech: false, t: {} }
  const inside = insideControl(ctx)
  assert.equal(inside.noSpeech, true)
  assert.equal(inside.glossary, null)
  assert.equal(inside.noLinks, true)
  assert.equal(inside.subject, "spanish")
  assert.equal(ctx.noSpeech, false, "the card's own context is unchanged")
})

test("a language span of one short word never breaks; a phrase may", () => {
  assert.equal(oneWord("-emos"), true)
  assert.equal(oneWord("hablar"), true)
  assert.equal(oneWord("Lucía se despierta"), false)
  assert.equal(oneWord("supercalifragilisticexpialidocious"), false)
})

const TEXTS = {
  tiles_line: "La tua risposta", tiles_bank: "Le tessere", tiles_empty: "Tocca le tessere qui sotto.", tile_used: "%{text}, già nella risposta.", tile_placed: "La tua risposta: %{text}.",
  tiles_sentence: { line: "La tua frase", bank: "Le parole", empty: "Tocca le parole qui sotto.", used: "%{text}, già nella frase.", placed: "La tua frase: %{text}." }
}

test("tiles: the fixed words are neutral, and those of a sentence when the check builds one", () => {
  assert.deepEqual(tilesTexts({ component: "tiles" }, TEXTS), { line: "La tua risposta", bank: "Le tessere", empty: "Tocca le tessere qui sotto.", used: "%{text}, già nella risposta.", placed: "La tua risposta: %{text}." })
  assert.equal(tilesTexts({ component: "tiles", builds: "sentence" }, TEXTS).line, "La tua frase")
  assert.equal(tilesTexts({ component: "tiles", builds: "sentence" }, TEXTS).bank, "Le parole")
  assert.equal(howtoKey({ component: "tiles" }), "tiles")
  assert.equal(howtoKey({ component: "tiles", builds: "sentence" }), "tiles_sentence")
})

test("tiles: a tile is named by its words, never by its markup", () => {
  assert.equal(nameOf({ id: "a", text_it: "**Lucía** impara lo spagnolo." }), "Lucía impara lo spagnolo.")
  assert.equal(nameOf({ id: "b", text_it: "[[highlight:Va]] in Spagna" }), "Va in Spagna")
  assert.equal(nameOf({ id: "c", text_it: "$3 \\cdot 4$ volte" }), "3 · 4 volte")
  assert.equal(nameOf({ id: "d", text_es: "Yo" }), "Yo")
  assert.equal(nameOf({ id: "e", text_it: "[[time-mark|it:Poi]] parte" }), "Poi parte")
})

test("plain words of a text: what a screen reader is told of a mistakes group, a button, a region, never markup printed as text", () => {
  const cases = [
    ["La persona noi di [[es:vivir]]", "La persona noi di vivir"],
    ["Con [[es:ser]] o con [[es:estar]]", "Con ser o con estar"],
    ["**Segni** e [[en:signs]]", "Segni e signs"],
    ["[[verb|it:essere]] e [[time-mark:ora]]", "essere e ora"],
    ["Potenze di $a^2 \\cdot a^3$", "Potenze di a^2 · a^3"],
    ["$\\role{unknown}{x}$ da trovare", "x da trovare"],
    ["[[g:tilde]] e [la scheda](scheda:intro)", "tilde e la scheda"],
    ["[[code:x = 1]] in Python", "x = 1 in Python"],
    ["Dividere", "Dividere"],
    ["", ""]
  ]
  for (const [text, words] of cases) {
    assert.equal(plainText(text), words, text)
    assert.equal(rawMarkup(plainText(text)), null, text)
  }
  assert.equal(plainText(null), "")
  assert.equal(plainText("$\\htmlClass{x}{y}$"), "$\\htmlClass{x}{y}$", "a text the reader refuses is returned as written")
})

const BAR = {
  type: "bar_model", alt_it: "Una barra di 7 fattori: 3 e 4.", view: "parts",
  bars: [{ label_it: "$a^3 \\cdot a^4$", parts: [{ value: "3", label_it: "$a^3$" }, { value: "4", label_it: "$a^4$" }] }],
  total: { value: "7", label_it: "fattori di $a^7$" }
}

test("bar_model: the part and total labels keep their formula, as the bar's label does (the page draws it with KaTeX)", () => {
  for (const width of [390, 1280]) {
    const scene = barModel.layout(BAR, { width, fontPx: 20, subject: "math" })
    assert.ok(!scene.error, JSON.stringify(scene.error))
    const texts = scene.labels.map((l) => l.text_it)
    assert.ok(texts.includes("fattori di $a^7$: 7"), texts.join(" | "))
    assert.ok(texts.includes("$a^3$") && texts.includes("$a^4$"), texts.join(" | "))
    assert.ok(texts.includes("$a^3 \\cdot a^4$"), texts.join(" | "))
    assert.ok(!texts.some((t) => /(^|[^$])a\^/.test(t.replace(/\$[^$]*\$/g, ""))), "no TeX outside its dollars")
  }
  assert.ok(!/\$/.test(barModel.describe(BAR, { state: 0 })), "the description stays plain")
})

const MIRROR = {
  type: "mirror", alt_it: "Ci laviamo le mani e nos lavamos las manos: i verbi si corrispondono, l'articolo cambia.",
  rows: [{
    pieces_it: ["Ci", "laviamo", "le mani"], pieces_es: ["Nos", "lavamos", "las manos"],
    links: [[0, 0, "same"], [1, 1, "same"], [2, 2, "shift"]],
    notes: [{ side: "es", piece: 2, note_it: "l'articolo è las" }],
    roles: [{ side: "it", piece: 1, role: "verb" }, { side: "es", piece: 1, role: "verb" }]
  }]
}

test("mirror on a phone: a word wider than the room beside its role icon puts the icon above it; wider than a column, the pair stacks", () => {
  const parts = (scene, key) => ({
    box: scene.shapes.find((s) => s.kind === "rect" && s.key === key),
    ic: scene.shapes.find((s) => s.kind === "icon" && s.key === `${key}:icon`),
    text: scene.labels.find((l) => l.key === `${key}:t`)
  })
  for (const fontPx of [18, 20, 26, 28]) {
    const scene = mirror.layout(MIRROR, { width: 300, fontPx, subject: "spanish" })
    assert.ok(!scene.error, JSON.stringify(scene.error))
    for (const key of ["r1i1:0", "r1t1:0", "r1i2:1", "r1t2:1", "r1i3:2", "r1t3:2"]) {
      const { box, text } = parts(scene, key)
      assert.ok(box && text, `${key} at ${fontPx}`)
      const word = Math.max(...text.text_it.split(/\s+/).map((w) => estimate(w, fontPx).w))
      assert.ok(text.x >= box.x && text.x + word <= box.x + box.w, `${key}: the word (${word} px) is inside its box at ${fontPx}`)
      assert.ok(text.y >= box.y && text.y + text.h <= box.y + box.h, `${key}: the word is inside its box at ${fontPx}`)
    }
  }
  // 20 px: two columns, the verb's icon above the verb
  const narrow = mirror.layout(MIRROR, { width: 300, fontPx: 20, subject: "spanish" })
  for (const key of ["r1i2:1", "r1t2:1"]) {
    const { box, ic, text } = parts(narrow, key)
    assert.ok(ic.y + ic.size <= text.y, `${key}: the icon is above the word`)
    assert.ok(ic.x >= box.x && ic.x + ic.size <= box.x + box.w, `${key}: the icon is inside its box`)
  }
  assert.equal(parts(narrow, "r1i2:1").box.y, parts(narrow, "r1t2:1").box.y, "the two pieces of a pair side by side")
  // 28 px: the pair is one piece under the other
  const big = mirror.layout(MIRROR, { width: 300, fontPx: 28, subject: "spanish" })
  const it = parts(big, "r1i2:1").box
  const es = parts(big, "r1t2:1").box
  assert.ok(it.y + it.h <= es.y, "the Spanish piece under the Italian one")
  // wide, the icon stays beside the word
  const wide = mirror.layout(MIRROR, { width: 1000, fontPx: 20, subject: "spanish" })
  const ic = wide.shapes.find((s) => s.kind === "icon" && s.key === "r1t2:icon")
  const text = wide.labels.find((l) => l.key === "r1t2:t")
  assert.ok(ic.x + ic.size <= text.x, "beside the word on a wide screen")
})
