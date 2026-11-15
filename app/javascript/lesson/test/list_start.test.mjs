// An ordered list keeps the number of its first line (D-335): a summary table whose cells read «1. Sillabe», «2. Sinalefe»,
// «3. Parola finale» drew every cell as «1.», because each cell is a one-item list. Markup parser, paragraph and table cell.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { renderRich } = await import("lesson/text")
const { tableNode } = await import("lesson/blocks/table")

class Fake {
  constructor(tag) { this.tag = tag; this.attrs = {}; this.children = []; this.own = "" }
  set className(v) { this.attrs.class = v }
  get className() { return this.attrs.class ?? "" }
  set textContent(v) { this.children = []; this.own = String(v) }
  get textContent() { return this.own + this.children.map((c) => c.textContent).join("") }
  setAttribute(name, value) { this.attrs[name] = String(value) }
  getAttribute(name) { return this.attrs[name] ?? null }
  appendChild(child) {
    if (child instanceof Fake && child.tag === "#fragment") { for (const c of child.children) this.appendChild(c); child.children = []; return child }
    this.children.push(child)
    return child
  }
  append(...nodes) { for (const node of nodes) this.appendChild(node) }
  all(pred, out = []) {
    for (const child of this.children) if (child instanceof Fake) { if (pred(child)) out.push(child); child.all(pred, out) }
    return out
  }
}

function withDom(fn) {
  globalThis.document = {
    createElement: (tag) => new Fake(tag),
    createElementNS: (_ns, tag) => new Fake(tag),
    createDocumentFragment: () => new Fake("#fragment"),
    createTextNode: (text) => ({ nodeType: 3, textContent: String(text) })
  }
  globalThis.window = {}
  try { return fn() } finally { delete globalThis.document; delete globalThis.window }
}

const ctx = { subject: "italian", t: {} }
const lists = (root) => root.all((n) => n.tag === "ol")

test("a paragraph «3. Parola finale» is a list that starts at 3; «1. Sillabe» has no start", () => {
  withDom(() => {
    const three = renderRich("3. Parola finale", ctx)
    assert.equal(lists(three)[0].getAttribute("start"), "3")
    const one = renderRich("1. Sillabe", ctx)
    assert.equal(lists(one)[0].getAttribute("start"), null)
  })
})

test("a list «2. due / 3. tre» starts at 2", () => {
  withDom(() => {
    const [ol] = lists(renderRich("2. due\n3. tre", ctx))
    assert.equal(ol.getAttribute("start"), "2")
    assert.equal(ol.children.length, 2)
  })
})

test("the cells of a table keep their own numbers", () => {
  withDom(() => {
    const table = { header: ["Passo", "Cosa"], rows: [["1. Sillabe", "a"], ["2. Sinalefe", "b"], ["3. Parola finale", "c"], ["4. Nome", "d"]] }
    const node = tableNode(table, ctx)
    const starts = lists(node).map((ol) => ol.getAttribute("start"))
    assert.deepEqual(starts, [null, "2", "3", "4"])
  })
})
