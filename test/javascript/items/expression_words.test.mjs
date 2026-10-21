// Words typed into an expression field (D-318): which values of the field make the page show the hint.
import assert from "node:assert/strict"
import { test } from "node:test"
import { hasTypedWords, itemLetters } from "../../../app/javascript/items/expression_words.js"

test("words typed through MathLive's shortcuts or as a run of letters trigger the hint", () => {
  assert.equal(hasTypedWords("\\operatorname{\\mathrm{th}}ereisnovaluefura"), true)
  assert.equal(hasTypedWords("\\text{novalue}"), true)
  assert.equal(hasTypedWords("\\mathrm{missing}"), true)
  assert.equal(hasTypedWords("\\operatorname{nessuno}"), true)
  assert.equal(hasTypedWords("nonesiste"), true)
})

test("expressions do not trigger it", () => {
  for (const latex of ["24a^3", "\\sqrt{x}", "\\sin x", "2ab", "", "\\frac{-29}{3x}", "\\operatorname{lcm}(a,b)", "\\sin\\left(x\\right)", "x^{2}+3x", "\\cos x \\tan y", "2^{-5}"]) {
    assert.equal(hasTypedWords(latex), false, latex)
  }
})

test("a run made only of the item's own letters is a product, not words", () => {
  const own = itemLetters({ stem_it: "Semplifica $a b c + 2abc$." })
  assert.equal(hasTypedWords("3abc", own), false)
  assert.equal(hasTypedWords("3abc"), true)
  assert.equal(hasTypedWords("abcd", own), true)
})

test("the item's letters come from its formulas only", () => {
  const own = itemLetters({ stem_it: "Il numero $x$ e la parte $\\frac{y}{2}$ del testo", options: [ { text: "con $\\sqrt{k}$" } ] })
  assert.deepEqual([ ...own ].sort(), [ "k", "x", "y" ])
})
