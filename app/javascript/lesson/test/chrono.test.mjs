// lesson/lib/chrono.js against the shared vectors of Lessons::Chrono (test/fixtures/lesson2/chrono.json; test/lib/lessons/chrono_test.rb).
import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const doc = JSON.parse(readFileSync(new URL("../../../../test/fixtures/lesson2/chrono.json", import.meta.url), "utf8"))
const chrono = await import("lesson/lib/chrono")

const calls = {
  duration: (a) => chrono.duration(...a),
  century: (a) => chrono.century(...a),
  roman: (a) => chrono.roman(...a),
  parse_roman: (a) => chrono.parseRoman(...a),
  mutants: (a) => chrono.mutants(...a)
}

test("the signatures are those of the vector file", () => {
  assert.deepEqual(Object.keys(chrono.SIGNATURES).sort(), Object.keys(doc.functions).sort())
  for (const [name, spec] of Object.entries(doc.functions)) assert.equal(chrono.SIGNATURES[name], spec.js)
})

test("every vector case gives its result, and a refused case throws a RangeError or gives null", () => {
  for (const [fn, spec] of Object.entries(doc.functions)) {
    assert.ok(spec.cases.length >= 6, `${fn} has cases`)
    for (const c of spec.cases) {
      let got
      try {
        got = calls[fn](c.args)
      } catch (error) {
        assert.ok(error instanceof RangeError, `${fn} ${c.args}: ${error}`)
        got = "refused"
      }
      if (got === null && c.refused) got = "refused"
      if (c.refused) assert.equal(got, "refused", `${fn} ${JSON.stringify(c.args)} is refused`)
      else assert.deepEqual(typeof got === "object" ? got : String(got), c.result, `${fn} ${JSON.stringify(c.args)}`)
    }
  }
})

test("the year 0 is never counted, and roman and parseRoman are inverse", () => {
  assert.equal(chrono.duration("-27", "14"), 40)
  for (let a = -30; a <= 30; a++) {
    for (let b = -30; b <= 30; b++) {
      if (!a || !b) continue
      assert.equal(chrono.duration(a, b), a < 0 && b > 0 ? b - a - 1 : a > 0 && b < 0 ? b - a + 1 : b - a)
      assert.ok(!Object.values(chrono.mutants(a, b)).map(Number).includes(chrono.duration(a, b)))
    }
  }
  for (let n = 1; n <= 3999; n++) assert.equal(chrono.parseRoman(chrono.roman(n)), n)
})
