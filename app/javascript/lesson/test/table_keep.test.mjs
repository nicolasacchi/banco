// A narrow lesson table keeps its grid on a phone (D-331): keepsGrid estimates the width from each column's longest cell, header included,
// as plain text without its markup (9 px a character, 26 px a cell), and keeps a table of at most 5 columns and at most 310 px (D-335: the
// box of a card is 312 px at 390 px). The CSS
// (lesson.css, .dg-table:not(.dg-keep)) stacks only the others; render_host's E-LESSON-OVERFLOW still catches a misestimate. A compact table
// (every cell after a row's first at most 3 characters: a table of signs) keeps its grid up to 7 columns whatever the estimate (D-335), in a
// box that scrolls sideways (.dg-scroll).
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { keepsGrid } = await import("lesson/blocks/table")

test("small grids keep their grid: a Punnett square, two columns of short Spanish forms, a 3x3 table of short numbers", () => {
  assert.equal(keepsGrid({ header: ["", "T", "t"], rows: [["T", "TT", "Tt"], ["t", "Tt", "tt"]] }), true)
  const forms = [["yo", "hablé"], ["tú", "hablaste"], ["él", "habló"], ["nosotros", "hablamos"], ["vosotros", "hablasteis"], ["ellos", "hablaron"]]
  assert.equal(keepsGrid({ header: ["Persona", "Forma"], rows: forms }), true)
  assert.equal(keepsGrid({ header: ["n", "n²", "n³"], rows: [["2", "4", "8"], ["3", "9", "27"], ["4", "16", "64"]] }), true)
})

test("wide tables still stack: four columns of sentences, eight columns even of single digits", () => {
  const sentence = (n) => `La frase numero ${n} è lunga quaranta carat`
  assert.equal(sentence(1).length, 40)
  assert.equal(keepsGrid({ header: ["A", "B", "C", "D"], rows: [[1, 2, 3, 4].map(sentence), [5, 6, 7, 8].map(sentence)] }), false)
  const digits = ["1", "2", "3", "4", "5", "6", "7", "8"]
  assert.equal(keepsGrid({ header: digits, rows: [digits, digits] }), false)
})

test("a cell counts its words without their markup: [[en:chemist's]] is 9 characters", () => {
  // beside a column of 19 characters (19 × 9 + 26 = 197 px) a 9-character column (107 px) makes 304 px, kept; beside 20 (206 px), 313 px,
  // stacked: 8 characters would keep both, 10 neither
  const span = "[[en:chemist's]]"
  assert.equal(keepsGrid({ header: [span, "a".repeat(19)], rows: [] }), true)
  assert.equal(keepsGrid({ header: [span, "a".repeat(20)], rows: [] }), false)
  // a row's cell counts as the header's does
  assert.equal(keepsGrid({ header: ["x", "a".repeat(19)], rows: [[span, "b"]] }), true)
  // a formula counts its text, bold its words: 1 + 3 + 2 characters, 141 px
  assert.equal(keepsGrid({ header: ["$x$", "**TT**", "x"], rows: [["**Tt**", "$x^2$", "tt"]] }), true)
})

const SIGNS = {
  header: ["Fattore", "x < −4", "−4 < x < 2", "x > 2"],
  rows: [["x + 4", "−", "+", "+"], ["x − 2", "−", "−", "+"], ["quoziente", "+", "−", "+"]],
}

test("a table of signs keeps its grid though its header makes it wider than 280 px (D-335)", () => {
  // 9 + 6 + 10 + 5 characters, 374 px estimated: stacked before D-335
  assert.equal(keepsGrid(SIGNS), true)
  // up to 7 columns, a first column and a header of any length
  const row = ["una riga con un nome molto lungo", "0", "∄", "T", "+", "−", "12"]
  assert.equal(keepsGrid({ header: ["Intervallo molto lungo", "a", "b", "c", "d", "e", "f"], rows: [row] }), true)
  // markup does not count: a formula of 3 characters is a short cell
  assert.equal(keepsGrid({ header: ["Fattore molto lungo", "$x < 1$", "$x > 1$"], rows: [["$f(x) = 2x$", "$-$", "$+$"]] }), true)
})

test("a compact table has its limits: 8 columns, a 4-character cell, no rows, a 4-column table of sentences", () => {
  const eight = ["a", "b", "c", "d", "e", "f", "g", "h"]
  assert.equal(keepsGrid({ header: ["Fattore", ...eight], rows: [["x", ...eight.map(() => "+")]] }), false)
  assert.equal(keepsGrid({ header: ["Fattore molto lungo", "x < −4", "−4 < x < 2", "x > 2"], rows: [["quoziente", "+", "−", "+++"]] }), true)
  assert.equal(keepsGrid({ header: ["Fattore molto lungo", "x < −4", "−4 < x < 2", "x > 2"], rows: [["quoziente", "+", "−", "+ + +"]] }), false)
  assert.equal(keepsGrid({ header: ["Fattore molto lungo", "x < −4", "−4 < x < 2", "x > 2"], rows: [] }), false)
  // the first column is free, the others are not: a long word in the second column stacks the table
  assert.equal(keepsGrid({ header: ["Fattore molto lungo", "x < −4", "−4 < x < 2", "x > 2"], rows: [["quoziente", "positivo", "−", "+"]] }), false)
  const sentence = (n) => `La frase numero ${n} è lunga quaranta carat`
  assert.equal(keepsGrid({ header: ["A", "B", "C", "D"], rows: [[1, 2, 3, 4].map(sentence)] }), false)
})

const city = (name, shift, sales) => [name, shift, String(sales)]
const SALES = {
  header: ["Città", "Turno", "Vendite"],
  rows: [
    city("Milano", "mattina", 1250), city("Torino", "sera", 980), city("Bologna", "mattina", 1710), city("Campobasso", "sera", 640),
    city("Firenze", "mattina", 1320), city("Napoli", "sera", 2045), city("Genova", "mattina", 875), city("Palermo", "sera", 1560),
  ],
}

test("a 3-column table of a city, a shift and a number keeps its grid at 390 px (D-335)", () => {
  // 10 + 7 + 7 characters: 116 + 89 + 89 = 294 px estimated, inside the 312 px box (280 px stacked it before)
  assert.equal(keepsGrid(SALES), true)
})

test("a 3-column table that really does not fit still stacks", () => {
  // «Reggio Calabria» is 15 characters: 161 + 89 + 89 = 339 px
  assert.equal(keepsGrid({ ...SALES, rows: [...SALES.rows, city("Reggio Calabria", "sera", 410)] }), false)
  // a third column headed «Vendite settimanali» (19 characters): 80 + 89 + 197 = 366 px
  assert.equal(keepsGrid({ header: ["Città", "Turno", "Vendite settimanali"], rows: [["Milano", "mattina", "1250"]] }), false)
})
