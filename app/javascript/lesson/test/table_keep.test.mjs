// A narrow lesson table keeps its grid on a phone (D-331): keepsGrid estimates the width from each column's longest cell, header included,
// as plain text without its markup (9 px a character, 26 px a cell), and keeps a table of at most 5 columns and at most 280 px. The CSS
// (lesson.css, .dg-table:not(.dg-keep)) stacks only the others; render_host's E-LESSON-OVERFLOW still catches a misestimate.
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

test("wide tables still stack: four columns of sentences, six columns even of single digits", () => {
  const sentence = (n) => `La frase numero ${n} è lunga quaranta carat`
  assert.equal(sentence(1).length, 40)
  assert.equal(keepsGrid({ header: ["A", "B", "C", "D"], rows: [[1, 2, 3, 4].map(sentence), [5, 6, 7, 8].map(sentence)] }), false)
  const digits = ["1", "2", "3", "4", "5", "6"]
  assert.equal(keepsGrid({ header: digits, rows: [digits, digits] }), false)
})

test("a cell counts its words without their markup: [[en:chemist's]] is 9 characters", () => {
  // beside a column of 16 characters (16 × 9 + 26 = 170 px) a 9-character column (107 px) makes 277 px, kept; beside 17 (179 px), 286 px,
  // stacked: 8 characters would keep both, 10 neither
  const span = "[[en:chemist's]]"
  assert.equal(keepsGrid({ header: [span, "a".repeat(16)], rows: [] }), true)
  assert.equal(keepsGrid({ header: [span, "a".repeat(17)], rows: [] }), false)
  // a row's cell counts as the header's does
  assert.equal(keepsGrid({ header: ["x", "a".repeat(16)], rows: [[span, "b"]] }), true)
  // a formula counts its text, bold its words: 1 + 3 + 2 characters, 141 px
  assert.equal(keepsGrid({ header: ["$x$", "**TT**", "x"], rows: [["**Tt**", "$x^2$", "tt"]] }), true)
})
