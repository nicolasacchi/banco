// The restricted markup of agent text: bold, $latex$, paragraphs, numbered lists, and
// nothing else. Run with: node --test 'test/javascript/**/*.test.mjs'
import assert from "node:assert/strict"
import { test } from "node:test"
import { inline, parse } from "../../../app/javascript/items/markup_parser.js"

test("plain text is one paragraph", () => {
  assert.deepEqual(parse("Quanto fa tre più due?"), [{ type: "p", children: [{ t: "text", v: "Quanto fa tre più due?" }] }])
})

test("an empty text has no blocks", () => {
  assert.deepEqual(parse(""), [])
  assert.deepEqual(parse(null), [])
  assert.deepEqual(parse("  \n  "), [])
})

test("**bold** marks a keyword", () => {
  assert.deepEqual(inline("scrivi **casa** ora"), [
    { t: "text", v: "scrivi " },
    { t: "bold", children: [{ t: "text", v: "casa" }] },
    { t: "text", v: " ora" }
  ])
})

test("an unclosed ** stays as text", () => {
  assert.deepEqual(inline("a ** b"), [{ t: "text", v: "a ** b" }])
})

test("$latex$ is a formula, and \\$ is a dollar sign", () => {
  assert.deepEqual(inline("$\\frac{1}{2}$ e basta"), [{ t: "math", v: "\\frac{1}{2}" }, { t: "text", v: " e basta" }])
  assert.deepEqual(inline("costa 5\\$ e 6\\$"), [{ t: "text", v: "costa 5$ e 6$" }])
  assert.deepEqual(inline("un $ solo"), [{ t: "text", v: "un $ solo" }])
})

test("a formula may hold an escaped dollar", () => {
  assert.deepEqual(inline("$a\\$b$"), [{ t: "math", v: "a$b" }])
})

test("a blank line starts a new paragraph", () => {
  const blocks = parse("Prima.\n\nSeconda riga\ncontinua.")
  assert.equal(blocks.length, 2)
  assert.equal(blocks[1].children[0].v, "Seconda riga continua.")
})

test("lines that all begin with a number make a numbered list", () => {
  const [list] = parse("1. uno\n2. due\n3) tre")
  assert.equal(list.type, "ol")
  assert.deepEqual(list.items.map((item) => item[0].v), ["uno", "due", "tre"])
})

test("one line without a number keeps the block a paragraph", () => {
  assert.equal(parse("1. uno\ndue")[0].type, "p")
})

test("HTML is only text: nothing here can become an element", () => {
  const nodes = inline('<img src=x onerror=alert(1)> <script>alert(1)</script>')
  assert.deepEqual(nodes, [{ t: "text", v: '<img src=x onerror=alert(1)> <script>alert(1)</script>' }])
  const blocks = parse('<b>x</b>\n\n<a href="javascript:alert(1)">y</a>')
  for (const block of blocks) for (const node of block.children) assert.equal(node.t, "text")
})

test("bold and formulas nest only one way: bold may hold a formula", () => {
  const [node] = inline("**vale $x$**")
  assert.equal(node.t, "bold")
  assert.deepEqual(node.children, [{ t: "text", v: "vale " }, { t: "math", v: "x" }])
})
