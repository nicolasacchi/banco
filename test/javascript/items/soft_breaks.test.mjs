// Soft break points in the long words of a table cell (D-335). Run with: node --test 'test/javascript/**/*.test.mjs'
import assert from "node:assert/strict"
import { test } from "node:test"
import { pieces, SOFT_MIN } from "../../../app/javascript/items/soft_breaks.js"

test("a long program line breaks after a dot, a bracket or a comma, never inside a name", () => {
  assert.deepEqual(pieces("CInt(Console.ReadLine())"), ["CInt(", "Console.", "ReadLine(", "))"])
  assert.deepEqual(pieces('Console.WriteLine("Livello'), ["Console.", "WriteLine(", '"Livello'])
  assert.deepEqual(pieces("funzione(alfa,beta,gamma)"), ["funzione(", "alfa,", "beta,", "gamma)"])
})

test("a break goes before = and &, not after", () => {
  assert.deepEqual(pieces("risultato=totale&resto"), ["risultato", "=totale", "&resto"])
  assert.deepEqual(pieces("campo_lungo.==valore"), ["campo_lungo.", "=", "=valore"])
})

test("a word of SOFT_MIN characters or fewer is left whole, and the pieces always join to the word", () => {
  assert.equal(SOFT_MIN, 12)
  assert.deepEqual(pieces("ReadLine()"), ["ReadLine()"])
  assert.deepEqual(pieces("123456789012"), ["123456789012"])
  for (const word of ["CInt(Console.ReadLine())", "a.b.c.d.e.f.g.h.i.j.k", "x=y&z=w&quota=100", "((((((((((((((("]) {
    assert.equal(pieces(word).join(""), word)
  }
})
