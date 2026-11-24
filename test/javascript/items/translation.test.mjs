// The translation state machine (D-402) over a small stand-in document: scopes, the nearest one wins, a scope button opens every block inside it,
// «Sempre visibile», the node and the buttons it builds, and the one post per target.
import assert from "node:assert/strict"
import { test, beforeEach } from "node:test"

class Node {
  constructor(tag) { this.tag = tag; this.attrs = new Map(); this.children = []; this.parentNode = null; this.own = ""; this.listeners = {} }
  setAttribute(name, value) { this.attrs.set(name, String(value)) }
  getAttribute(name) { return this.attrs.has(name) ? this.attrs.get(name) : null }
  removeAttribute(name) { this.attrs.delete(name) }
  appendChild(child) { child.parentNode = this; this.children.push(child); return child }
  addEventListener(name, fn) { (this.listeners[name] ??= []).push(fn) }
  click() { (this.listeners.click ?? []).forEach((fn) => fn()) }
  set textContent(text) { this.own = String(text) }
  get textContent() { return this.own + this.children.map((c) => c.textContent).join("") }
}

const html = new Node("html")
globalThis.document = {
  documentElement: html,
  createElement: (tag) => new Node(tag),
  querySelector: (selector) => (selector === "meta[name=csrf-token]" ? { content: "tok" } : null)
}

const T = await import("../../../app/javascript/items/translation.js")

const el = (tag, attrs = {}, ...kids) => {
  const node = new Node(tag)
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v)
  kids.forEach((kid) => node.appendChild(kid))
  return node
}

// <article data-tr-scope=card data-translation=off> <head><button/></head> <div block1 data-tr-scope=block> text, .tr, unit button </div> <div block2 ...> </article>
function lesson({ url = "/translations" } = {}) {
  const cardButton = T.toggleButton({ text: "Traduzione" })
  const unit1 = T.toggleButton({ unit: true, ariaLabel: "Mostra la traduzione: After a modal" })
  const unit2 = T.toggleButton({ unit: true, ariaLabel: "Mostra la traduzione: My sister" })
  const tr1 = T.node("Dopo un verbo modale.")
  const tr2 = T.node("Mia sorella sa suonare.", { tag: "span" })
  const block1 = el("div", { "data-tr-scope": "block", "data-tr-block": "1" }, el("p"), tr1, unit1)
  const block2 = el("div", { "data-tr-scope": "block", "data-tr-block": "2" }, el("p"), tr2, unit2)
  const attrs = { "data-tr-scope": "card", "data-translation": "off", "data-tr-card": "3", "data-tr-surface": "lesson", "data-tr-topic": "lezione.english.can" }
  if (url) attrs["data-tr-url"] = url
  const card = el("article", attrs, el("header", {}, cardButton), block1, block2)
  const root = el("main", {}, card)
  T.refresh(root)
  return { root, card, cardButton, block1, block2, unit1, unit2, tr1, tr2 }
}

function recorder() {
  const calls = []
  const fetchImpl = (url, init) => { calls.push({ url, ...init, body: JSON.parse(init.body) }); return Promise.resolve({ ok: true }) }
  return { calls, fetchImpl }
}

beforeEach(() => { html.removeAttribute("data-translation") })

test("node builds a translation node: class tr, lang it, no speech, text as text", () => {
  const n = T.node("Dopo <can>")
  assert.equal(n.tag, "p")
  assert.equal(n.getAttribute("class"), "tr")
  assert.equal(n.getAttribute("lang"), "it")
  assert.equal(n.getAttribute("data-nospeech"), "")
  assert.equal(n.textContent, "Dopo <can>")
  assert.equal(T.node("x", { tag: "span" }).tag, "span")
  const rich = el("em")
  assert.equal(T.node(rich).children[0], rich, "a node the caller drew goes in as it is")
})

test("toggleButton builds a real button, not pressed, with the label and the unit's name", () => {
  const b = T.toggleButton({ text: "Traduzione" })
  assert.equal(b.tag, "button")
  assert.equal(b.getAttribute("type"), "button")
  assert.equal(b.getAttribute("class"), "tr-toggle")
  assert.equal(b.getAttribute("aria-pressed"), "false")
  assert.equal(b.textContent, "Traduzione")
  const unit = T.toggleButton({ unit: true, ariaLabel: "Mostra la traduzione: Ciao", icon: el("svg") })
  assert.equal(unit.getAttribute("class"), "tr-toggle tr-toggle-unit")
  assert.equal(unit.getAttribute("aria-label"), "Mostra la traduzione: Ciao")
})

test("a scope starts closed; the card button opens it and aria-pressed follows, the second click closes it", () => {
  const { card, cardButton, unit1 } = lesson({ url: null })
  assert.equal(T.state(card), "off")
  assert.equal(cardButton.getAttribute("aria-pressed"), "false")
  cardButton.click()
  assert.equal(card.getAttribute("data-translation"), "on")
  assert.equal(cardButton.getAttribute("aria-pressed"), "true")
  assert.equal(unit1.getAttribute("aria-pressed"), "true", "a block follows its card")
  cardButton.click()
  assert.equal(card.getAttribute("data-translation"), "off")
  assert.equal(unit1.getAttribute("aria-pressed"), "false")
})

test("a unit button flips its block only, and the nearest scope wins", () => {
  const { card, block1, block2, unit1, unit2, tr1, tr2 } = lesson({ url: null })
  unit1.click()
  assert.equal(block1.getAttribute("data-translation"), "on")
  assert.equal(card.getAttribute("data-translation"), "off")
  assert.equal(T.isOpen(tr1), true)
  assert.equal(T.isOpen(tr2), false)
  assert.equal(unit1.getAttribute("aria-pressed"), "true")
  assert.equal(unit2.getAttribute("aria-pressed"), "false")
  unit1.click()
  assert.equal(T.isOpen(tr1), false)
})

test("a block closed by hand inside an open card stays closed; the card button then takes every block back to the card", () => {
  const { card, cardButton, block1, block2, unit1, tr1, tr2 } = lesson({ url: null })
  cardButton.click()
  unit1.click()
  assert.equal(block1.getAttribute("data-translation"), "off")
  assert.equal(T.isOpen(tr1), false)
  assert.equal(T.isOpen(tr2), true)
  cardButton.click()
  assert.equal(card.getAttribute("data-translation"), "off")
  assert.equal(block1.getAttribute("data-translation"), null, "the block follows its card again")
  cardButton.click()
  assert.equal(T.isOpen(tr1), true, "opened again: every block of the card, the one closed by hand too")
})

test("a block added after the card was opened follows it", () => {
  const { card, cardButton } = lesson({ url: null })
  cardButton.click()
  const late = T.node("Una riga arrivata dopo.")
  card.appendChild(late)
  assert.equal(T.isOpen(late), true)
})

test("«Sempre visibile»: every scope is open, the buttons are pressed and do nothing", () => {
  html.setAttribute("data-translation", "always")
  const { card, cardButton, unit1, tr1 } = lesson({ url: "/translations" })
  assert.equal(T.state(card), "always")
  assert.equal(T.isOpen(tr1), true)
  assert.equal(cardButton.getAttribute("aria-pressed"), "true")
  assert.equal(unit1.getAttribute("aria-pressed"), "true")
  const { calls, fetchImpl } = recorder()
  assert.equal(T.toggle(cardButton, { fetchImpl }), null)
  assert.equal(card.getAttribute("data-translation"), "off", "the scope is as it was")
  assert.equal(calls.length, 0)
})

test("opening posts translation_opened once with the context; closing and opening again post nothing more", async () => {
  const { cardButton, card } = lesson()
  const { calls, fetchImpl } = recorder()
  assert.equal(T.toggle(cardButton, { fetchImpl }), true)
  await Promise.resolve()
  assert.equal(calls.length, 1)
  assert.equal(calls[0].url, "/translations")
  assert.equal(calls[0].method, "POST")
  assert.equal(calls[0].headers["X-CSRF-Token"], "tok")
  assert.equal(calls[0].headers["Content-Type"], "application/json")
  assert.deepEqual(calls[0].body, { surface: "lesson", scope: "card", topic: "lezione.english.can", card: 3 })
  assert.equal(T.toggle(cardButton, { fetchImpl }), false, "close")
  assert.equal(T.toggle(cardButton, { fetchImpl }), true, "open again")
  assert.equal(calls.length, 1, "once per target per page load")
  assert.equal(card.getAttribute("data-translation"), "on")
})

test("a block posts its own target: the card of its ancestor and its own number", () => {
  const { unit2 } = lesson()
  const { calls, fetchImpl } = recorder()
  T.toggle(unit2, { fetchImpl })
  assert.deepEqual(calls[0].body, { surface: "lesson", scope: "block", topic: "lezione.english.can", card: 3, block: 2 })
})

test("a practice exercise posts the serve id as a number; a context that is missing is left out", () => {
  const button = T.toggleButton({ text: "Traduzione" })
  const section = el("section", { "data-tr-scope": "item", "data-translation": "off", "data-tr-url": "/practice/translations", "data-tr-surface": "practice", "data-tr-serve": "75" }, el("div", {}, button))
  T.refresh(section)
  const { calls, fetchImpl } = recorder()
  T.toggle(button, { fetchImpl })
  assert.deepEqual(calls[0].body, { surface: "practice", scope: "item", serve_id: 75 })
  assert.equal(calls[0].url, "/practice/translations")
})

test("no address, no post: the teacher and the preview write nothing", () => {
  const { cardButton, card } = lesson({ url: null })
  const { calls, fetchImpl } = recorder()
  assert.equal(T.toggle(cardButton, { fetchImpl }), true)
  assert.equal(calls.length, 0)
  assert.equal(card.getAttribute("data-translation"), "on", "it still opens")
})

test("a refused post is ignored", async () => {
  const { cardButton } = lesson({ url: "/translations?x=1" })
  const refused = () => Promise.reject(new Error("offline"))
  assert.equal(T.toggle(cardButton, { fetchImpl: refused }), true)
  await new Promise((resolve) => setImmediate(resolve))
})

test("a button with no scope around it does nothing", () => {
  const stray = T.toggleButton({ text: "Traduzione" })
  assert.equal(T.toggle(stray), null)
})

test("firstWords and unitLabel: markup out, six words, an ellipsis when cut", () => {
  assert.equal(T.firstWords("After a **modal** verb the next verb does not change"), "After a modal verb the next…")
  assert.equal(T.firstWords("My [[en:sister]] can"), "My sister can")
  assert.equal(T.firstWords("Short one"), "Short one")
  assert.equal(T.unitLabel("Mostra la traduzione: %{words}", "My sister can play the guitar well"), "Mostra la traduzione: My sister can play the guitar…")
})
