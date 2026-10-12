import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const M = await import("lesson/lib/money")
const vectors = JSON.parse(readFileSync(new URL("../../../../test/fixtures/lesson2/money.json", import.meta.url), "utf8"))
const camel = { round_half_up: "roundHalfUp" }

for (const [fn, spec] of Object.entries(vectors.functions)) {
  spec.cases.forEach((c, i) => {
    test(`${fn} ${i}: ${JSON.stringify(c.args).slice(0, 60)}`, () => {
      const f = M[camel[fn] ?? fn]
      if (c.refused) assert.throws(() => f(...c.args), M.Refused)
      else assert.deepEqual(f(...c.args), c.result)
    })
  })
}

test("the closed list of invoice errors is the vectors' list and the signatures are frozen", () => {
  assert.deepEqual(M.ERROR_VARIANTS, vectors.functions.invoice.error_variants)
  assert.deepEqual(Object.keys(M.SIGNATURES), ["round_half_up", "vat", "row", "invoice"])
})

test("display adds the thousands dot", () => {
  assert.equal(M.display("2319,20"), "2.319,20")
  assert.equal(M.display("1240000,05"), "1.240.000,05")
  assert.equal(M.display("60,00"), "60,00")
  assert.equal(M.display("-1000,00"), "-1.000,00")
})
