// Equations as the lesson draws them: the unknown and the numbers get their roles, a displayed equation its two member tiles.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { colourTokens, displayTex } = await import("lesson/eq")

test("the unknown and the numbers get their roles, exponents do not", () => {
  assert.equal(colourTokens("2x + 1"), "\\role{known}{2}\\role{unknown}{x} + \\role{known}{1}")
  assert.equal(colourTokens("x^2"), "\\role{unknown}{x}^2")
  assert.equal(colourTokens("\\text{con } b"), "\\text{con } b")
})

test("what the author already wrapped stays as it is", () => {
  assert.equal(colourTokens("\\role{highlight}{-2} + x"), "\\role{highlight}{-2} + \\role{unknown}{x}")
})

test("a displayed equation has two member tiles, an arrow separates two equations", () => {
  assert.equal(displayTex("x = 3"), "\\role{left}{\\role{unknown}{x}}\\,=\\,\\role{right}{\\role{known}{3}}")
  const chain = displayTex("2x = 6 \\to x = 3")
  assert.equal((chain.match(/\\role\{left\}/g) ?? []).length, 2)
  assert.match(chain, /\\to/)
})

test("without exactly one equals sign only the colours are added", () => {
  assert.equal(displayTex("a \\neq 0"), "a \\neq \\role{known}{0}")
  assert.doesNotMatch(displayTex("x = 1 = y"), /role\{left\}/)
})
