import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import { canonical, compare, parse, format, make, add, mul, div, sub, toNumber } from "../num.js"

const vectors = JSON.parse(readFileSync(new URL("../../../../test/fixtures/lesson2/numbers.json", import.meta.url), "utf8"))

for (const c of vectors.parse) {
  test(`parse ${JSON.stringify(c.input)}`, () => {
    const got = parse(c.input, { allowInf: c.allow_inf === true })
    if (c.refused) assert.equal(got, null)
    else assert.equal(canonical(got), c.canonical)
  })
}

for (const c of vectors.compare) {
  test(`compare ${c.a} ${c.b}`, () => {
    assert.equal(compare(parse(c.a, { allowInf: c.allow_inf }), parse(c.b, { allowInf: c.allow_inf })), c.cmp)
  })
}

test("infinity is parsed only when allowed", () => {
  assert.equal(parse("+inf"), null)
  assert.equal(canonical(parse("-inf", { allowInf: true })), "-inf")
})

test("arithmetic is exact", () => {
  const third = make(1n, 3n)
  assert.equal(canonical(add(third, third)), "2/3")
  assert.equal(canonical(sub(third, make(1n, 2n))), "-1/6")
  assert.equal(canonical(mul(make(2n, 3n), make(3n, 4n))), "1/2")
  assert.equal(canonical(div(make(1n), make(-4n))), "-1/4")
  assert.equal(toNumber(make(5n, 2n)), 2.5)
})

test("format reads the Italian way", () => {
  assert.equal(format(parse("5/2")), "2,5")
  assert.equal(format(parse("-3")), "−3")
  assert.equal(format(parse("1/3")), "1/3")
  assert.equal(format(parse("-1/4")), "−0,25")
})
