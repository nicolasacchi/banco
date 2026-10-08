// Markup v2 (lessons only): the browser parser against the fixture the Ruby mirror also runs
// (test/fixtures/markup/v2.json). Refused inputs are Ruby's business; the browser is lenient.
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import { parse } from "../../../app/javascript/items/markup_parser.js"

const cases = JSON.parse(readFileSync(new URL("../../fixtures/markup/v2.json", import.meta.url), "utf8"))

cases.filter((c) => c.blocks).forEach((c, i) => {
  test(`v2 case ${i}: ${JSON.stringify(c.input).slice(0, 50)}`, () => {
    assert.deepEqual(parse(c.input, { lists: "v2" }), c.blocks)
  })
})

test("without the option a dash list stays a paragraph (items keep markup v1)", () => {
  const [block] = parse("- uno\n- due")
  assert.equal(block.type, "p")
})
