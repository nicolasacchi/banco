// lesson/lib/bits.js against the shared vectors of Lessons::Bits (test/fixtures/lesson2/bits.json; test/lib/lessons/bits_test.rb).
import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const doc = JSON.parse(readFileSync(new URL("../../../../test/fixtures/lesson2/bits.json", import.meta.url), "utf8"))
const bits = await import("lesson/lib/bits")

const num = (v, d) => (v === undefined ? d : Number(v))
const calls = {
  read: (a) => bits.read(a[0], num(a[1], 2), a[2] === "true"),
  write: (a) => bits.write(a[0], num(a[1]), num(a[2], 2), a[3] === "true"),
  add: (a) => bits.add(a[0], a[1], num(a[2]), num(a[3], 2)),
  sub: (a) => bits.sub(a[0], a[1], num(a[2]), num(a[3], 2)),
  mul: (a) => bits.mul(a[0], a[1], num(a[2]), num(a[3], 2)),
  repeated_division: (a) => bits.repeatedDivision(a[0], num(a[1]))
}

test("the signatures are those of the vector file", () => {
  assert.deepEqual(Object.keys(bits.SIGNATURES).sort(), Object.keys(doc.functions).sort())
  for (const [name, spec] of Object.entries(doc.functions)) assert.equal(bits.SIGNATURES[name], spec.js)
})

test("every vector case gives its result (a refused call is {error: argument})", () => {
  for (const [fn, spec] of Object.entries(doc.functions)) {
    assert.ok(spec.cases.length >= 4, `${fn} has cases`)
    for (const c of spec.cases) {
      let got
      try {
        got = calls[fn](c.args)
      } catch (error) {
        assert.ok(error instanceof RangeError, `${fn} ${c.args}: ${error}`)
        got = { error: "argument" }
      }
      const want = fn === "read" && typeof c.result === "string" ? Number(c.result) : c.result
      assert.deepEqual(got, want, `${fn} ${JSON.stringify(c.args)}`)
    }
  }
})

test("write then read is the identity on every value of a register, and the columns agree with the sum", () => {
  for (let v = -8; v <= 7; v++) assert.equal(bits.read(bits.write(v, 4, 2, true), 2, true), v)
  for (let a = 0; a < 16; a++) {
    for (let b = 0; b < 16; b++) {
      const x = bits.write(a, 4)
      const y = bits.write(b, 4)
      assert.equal(bits.read(bits.add(x, y, 4).digits), (a + b) % 16)
      assert.equal(bits.read(bits.sub(x, y, 4).digits), (((a - b) % 16) + 16) % 16)
      if (b < 8) assert.equal(bits.read(bits.mul(x, bits.write(b, 3), 4).full), a * b)
    }
  }
})
