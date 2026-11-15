// A mark that follows a formula (or an opening one that precedes it) shares a span.nowrap with it, so that it is never alone at the start of a
// line on a phone (D-335). The pure grouping (items/formula_punct.js), the lesson renderer and the items renderer on a minimal DOM, the plain
// text and the voice unchanged.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { glueFormulas } = await import("items/formula_punct")
const { parse } = await import("items/markup_parser")
const { renderRich, plainText } = await import("lesson/text")
const markup = await import("items/markup")
const speech = await import("lesson/speech")

const inline = (text) => parse(text, { lists: "v2", roles: true })[0].children
const shape = (nodes) => nodes.map((n) => (n.t === "nowrap" ? `[${shape(n.children)}]` : n.t === "math" ? `$${n.v}$` : JSON.stringify(n.v)))

test("a full stop, «?)» and a comma after a formula go into its group; a word after it does not", () => {
  assert.deepEqual(shape(glueFormulas(inline("Vale $x$."))), ['"Vale "', '[$x$,"."]'])
  assert.deepEqual(shape(glueFormulas(inline("Quanto vale $x$?) Poi"))), ['"Quanto vale "', '[$x$,"?)"]', '" Poi"'])
  assert.deepEqual(shape(glueFormulas(inline("Se $a$, allora $b$."))), ['"Se "', '[$a$,","]', '" allora "', '[$b$,"."]'])
  assert.deepEqual(shape(glueFormulas(inline("Vale $x$ e basta."))), ['"Vale "', "$x$", '" e basta."'])
  assert.deepEqual(shape(glueFormulas(inline("Vale $x$ ."))), ['"Vale "', "$x$", '" ."'])
})

test("an opening bracket or quote before a formula joins it, with the closing mark after it", () => {
  assert.deepEqual(shape(glueFormulas(inline("sono due («$x$») e ($y$), ok"))), ['"sono due "', '["(«",$x$,"»)"]', '" e "', '["(",$y$,"),"]', '" ok"'])
  assert.deepEqual(shape(glueFormulas(inline("($x$)"))), ['["(",$x$,")"]'])
})

test("a text without a formula is returned as it is; the reader's tree is not changed", () => {
  const nodes = inline("Solo testo.")
  assert.equal(glueFormulas(nodes), nodes)
  const withMath = inline("Vale $x$.")
  const copy = JSON.stringify(withMath)
  glueFormulas(withMath)
  assert.equal(JSON.stringify(withMath), copy)
})

// ---- a minimal DOM -------------------------------------------------------------------------------------------------------------------

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
const wrappers = (root) => root.all((n) => n.getAttribute("class") === "nowrap")
const ctx = { subject: "math", t: {} }

test("the lesson renderer draws span.nowrap around «$x$.» and «$x$?)», and not around «$x$ e»", () => {
  withDom(() => {
    for (const [text, mark] of [["Vale $x$.", "."], ["Quanto vale $x$?)", "?)"]]) {
      const [box] = wrappers(renderRich(text, ctx))
      assert.ok(box, text)
      assert.equal(box.all((n) => n.getAttribute("class") === "math").length, 1)
      assert.equal(box.children.at(-1).textContent, mark)
    }
    assert.equal(wrappers(renderRich("Vale $x$ e basta.", ctx)).length, 0)
    assert.equal(wrappers(renderRich("$x$", ctx)).length, 0)
    assert.equal(wrappers(renderRich("Solo testo.", ctx)).length, 0)
  })
})

test("a formula alone in a block is a display and takes no wrapper; chemistry takes one like any formula", () => {
  withDom(() => {
    assert.equal(wrappers(renderRich("$x+1$", ctx)).length, 0)
    assert.equal(wrappers(renderRich("Scrivi $\\ce{H2O}$.", ctx)).length, 1)
  })
})

test("the items renderer draws the same wrapper", () => {
  withDom(() => {
    const kind = (text) => { const p = new Fake("p"); markup.renderInline(text, p); return wrappers(p).length }
    assert.equal(kind("Vale $x$."), 1)
    assert.equal(kind("Quanto vale $x$?)"), 1)
    assert.equal(kind("Vale $x$ e basta."), 0)
  })
})

test("the plain text of a text is the same with the wrapper in the way", () => {
  assert.equal(plainText("Vale $x$. E $y$?"), "Vale x. E y?")
})

// the voice: speech.js walks the DOM and joins the pieces; a span around a formula and its mark says the same words
function text(value) { return { nodeType: 3, nodeValue: value } }
function el(tag, attrs = {}, ...kids) {
  const node = { nodeType: 1, tagName: tag.toUpperCase(), attrs, childNodes: kids.map((k) => (typeof k === "string" ? text(k) : k)), getAttribute(n) { return n in attrs ? String(attrs[n]) : null } }
  for (const kid of node.childNodes) kid.parentNode = node
  node.textContent = node.childNodes.map((k) => k.nodeValue ?? k.textContent).join("")
  return node
}
function katex(tex) {
  const annotation = el("annotation", { encoding: "application/x-tex" }, tex)
  const node = el("span", { class: "katex" }, el("span", { class: "katex-html" }, tex))
  node.querySelector = () => annotation
  return node
}
test("the voice says the same words with and without the wrapper", () => {
  const said = (card) => speech.speechOf(card).map((s) => s.text)
  const plain = el("p", {}, "Vale ", katex("x + 1"), ".")
  const wrapped = el("p", {}, "Vale ", el("span", { class: "nowrap" }, el("span", { class: "math" }, katex("x + 1")), "."))
  const opened = el("p", {}, "Vale ", el("span", { class: "nowrap" }, "(", el("span", { class: "math" }, katex("x + 1")), ")"), " sempre.")
  assert.deepEqual(said(wrapped), said(plain))
  assert.deepEqual(said(opened), said(el("p", {}, "Vale (", katex("x + 1"), ") sempre.")))
})
