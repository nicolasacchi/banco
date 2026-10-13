// lesson/lib/chem.js against the shared vectors of Lessons::Chem (test/fixtures/lesson2/chem_formulas.json; test/lib/lessons/chem_test.rb).
import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const doc = JSON.parse(readFileSync(new URL("../../../../test/fixtures/lesson2/chem_formulas.json", import.meta.url), "utf8"))
const chem = await import("lesson/lib/chem")

const calls = {
  parse: (a) => chem.parse(a[0]),
  count: (a) => chem.count(a[0]),
  classify: (a) => chem.classify(a[0]),
  same_composition: (a) => chem.sameComposition(a[0], a[1])
}

test("the signatures are those of the vector file", () => {
  assert.deepEqual(Object.keys(chem.SIGNATURES).sort(), Object.keys(doc.functions).sort())
  for (const [name, spec] of Object.entries(doc.functions)) assert.equal(chem.SIGNATURES[name], spec.js)
})

test("every vector case gives its result (null is a formula that does not parse)", () => {
  for (const [fn, spec] of Object.entries(doc.functions)) {
    assert.ok(spec.cases.length >= 10, `${fn} has cases`)
    for (const c of spec.cases) assert.deepEqual(calls[fn](c.args), c.result, `${fn} ${JSON.stringify(c.args)}`)
  }
})

test("the grammar is case-exact: all 118 symbols parse alone, a changed case never does", () => {
  assert.equal(chem.SYMBOLS.size, 118)
  for (const s of chem.SYMBOLS) {
    assert.ok(chem.parse(s), s)
    assert.equal(chem.classify(s), "element")
    // "SI" is sulphur and iodine, never silicon: the upper-case word never reads as the symbol itself
    if (s.length > 1) assert.ok(!(chem.parse(s.toUpperCase())?.groups ?? []).some((g) => g.symbol === s), s.toUpperCase())
    assert.equal(chem.parse(s.toLowerCase()), null, s.toLowerCase())
  }
})

test("the helpers", () => {
  assert.equal(chem.base("2 Ca(NO3)2(aq)"), "Ca(NO3)2")
  assert.equal(chem.base("CL2"), null)
  assert.equal(chem.unknownSymbol("Xx2"), "Xx")
  assert.equal(chem.unknownSymbol("H2O"), null)
  assert.equal(chem.element("Na").name_it, "sodio")
  assert.equal(chem.element("Xx"), null)
})
