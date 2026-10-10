// Markup v2 (lessons only): the browser parser against the fixture the Ruby mirror also runs
// (test/fixtures/markup/v2.json). Refused inputs are Ruby's business; the browser is lenient.
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import { parse, Refused } from "../../../app/javascript/items/markup_parser.js"

const cases = JSON.parse(readFileSync(new URL("../../fixtures/markup/v2.json", import.meta.url), "utf8"))

// Cases with options ({ roles: true }) belong to the lesson/2 parser of the browser (R2).
cases.filter((c) => c.blocks && !c.options).forEach((c, i) => {
  test(`v2 case ${i}: ${JSON.stringify(c.input).slice(0, 50)}`, () => {
    assert.deepEqual(parse(c.input, { lists: "v2" }), c.blocks)
  })
})

test("without the option a dash list stays a paragraph (items keep markup v1)", () => {
  const [block] = parse("- uno\n- due")
  assert.equal(block.type, "p")
})

// The lesson/2 additions (A5): role spans, links, and the formula commands the browser refuses.
const withRoles = { lists: "v2", roles: true }
cases.filter((c) => c.options?.roles && c.blocks).forEach((c, i) => {
  test(`roles case ${i}: ${JSON.stringify(c.input).slice(0, 50)}`, () => {
    assert.deepEqual(parse(c.input, withRoles), c.blocks)
  })
})
cases.filter((c) => c.options?.roles && c.js_refuses).forEach((c, i) => {
  test(`roles refused ${i}: ${JSON.stringify(c.input).slice(0, 50)}`, () => {
    assert.throws(() => parse(c.input, withRoles), Refused)
  })
})

test("without the roles option brackets and links are plain text and formulas are not checked", () => {
  const [block] = parse("[[subject:Il treno]] $\\htmlClass{x}{y}$", { lists: "v2" })
  assert.equal(block.children[0].t, "text")
})
