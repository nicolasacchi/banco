// lesson/lib/words.js against the shared vectors of Lessons::Words (test/fixtures/lesson2/spanish_words.json and split.json; test/lib/lessons/words_test.rb).
import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const read = (name) => JSON.parse(readFileSync(new URL(`../../../../test/fixtures/lesson2/${name}`, import.meta.url), "utf8"))
const doc = read("spanish_words.json")
const notation = read("split.json")
const words = await import("lesson/lib/words")
const { NotBuilt } = await import("lesson/lib/not_built")

const calls = { split: words.split, syllables_es: words.syllablesEs, stress_es: words.stressEs, tilde_ok: words.tildeOk }

test("the signatures are those of the vector file", () => {
  assert.deepEqual(Object.keys(words.SIGNATURES).sort(), Object.keys(doc.functions).sort())
  for (const [name, spec] of Object.entries(doc.functions)) assert.equal(words.SIGNATURES[name], spec.js)
})

test("every vector case gives its result, and a refused case throws Refused", () => {
  for (const [fn, call] of Object.entries(calls)) {
    const cases = doc.functions[fn].cases
    assert.ok(cases.length >= 10, `${fn} has cases`)
    for (const c of cases) {
      if (c.refused) assert.throws(() => call(...c.args), words.Refused, `${fn} ${JSON.stringify(c.args)}`)
      else assert.deepEqual(call(...c.args), c.result, `${fn} ${JSON.stringify(c.args)}`)
    }
  }
})

test("split.json holds the same cases in the notation file's shape", () => {
  for (const c of notation.cases) {
    if (c.refused) assert.throws(() => words.split(c.input), words.Refused, c.input)
    else {
      const got = words.split(c.input)
      assert.deepEqual(got.pieces, c.pieces, c.input)
      assert.equal(got.word, c.word, c.input)
    }
  }
})

test("present is the W2-2 half", () => {
  assert.throws(() => words.present("poder", "o-ue"), NotBuilt)
})
