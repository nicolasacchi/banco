// The minus key (D-335): an iPhone "decimal" or "numeric" keyboard shows no minus, so a negative number or fraction could not be typed.
// The number and fraction templates draw one key «−» (and the comma, for a number) that writes at the caret of the box. A small stand-in for the document.
import "../../../app/javascript/lesson/test/setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

class Node {
  constructor(tag) {
    this.tag = tag; this.attrs = {}; this.children = []; this.own = ""; this.listeners = {}
    this.value = ""; this.selectionStart = null; this.selectionEnd = null
  }
  set className(v) { this.attrs.class = v }
  get className() { return this.attrs.class ?? "" }
  set textContent(v) { this.children = []; this.own = String(v) }
  get textContent() { return this.own + this.children.map((c) => c.textContent).join("") }
  setAttribute(name, value) { this.attrs[name] = String(value) }
  getAttribute(name) { return this.attrs[name] ?? null }
  appendChild(child) { this.children.push(child); return child }
  addEventListener(name, fn) { (this.listeners[name] ??= []).push(fn) }
  fire(name, event = {}) { for (const fn of this.listeners[name] ?? []) fn({ preventDefault() {}, ...event }) }
  focus() { focused = this; this.fire("focus") }
  setSelectionRange(a, b) { this.selectionStart = a; this.selectionEnd = b }
  type(text) { this.value = text; this.selectionStart = this.selectionEnd = text.length }
  all(pred, out = []) {
    for (const child of this.children) if (child instanceof Node) { if (pred(child)) out.push(child); child.all(pred, out) }
    return out
  }
  byClass(cls) { return this.all((n) => n.className.split(/\s+/).includes(cls)) }
  inputs() { return this.all((n) => n.tag === "input") }
}

let focused = null
globalThis.document = {
  createElement: (tag) => new Node(tag),
  createTextNode: (text) => ({ nodeType: 3, textContent: String(text) })
}

const { render: number } = await import("items/number")
const { render: fraction } = await import("items/fraction")
const t = {
  number_label: "Numero", number_scientific_label: "Notazione scientifica", fraction_numerator: "Numeratore", fraction_denominator: "Denominatore", fraction_whole: "Parte intera",
  helper_keys: "Tasti per scrivere", key_minus: "Meno", key_comma: "Virgola"
}
const keysOf = (handle) => handle.element.byClass("helper-key")
const press = (key) => { key.fire("mousedown"); key.fire("click") }

test("a number has a minus key and a comma key, type=button, named in Italian", () => {
  const answer = number({ component: "number" }, { t })
  const keys = keysOf(answer)
  assert.deepEqual(keys.map((k) => k.textContent), ["\u2212", ","])
  assert.deepEqual(keys.map((k) => k.getAttribute("aria-label")), ["Meno", "Virgola"])
  assert.ok(keys.every((k) => k.getAttribute("type") === "button"))
  assert.equal(answer.element.byClass("helper-keys").length, 1)
  assert.equal(answer.element.byClass("helper-keys")[0].getAttribute("aria-label"), "Tasti per scrivere")
})

test("the minus key of a number inserts - at the caret and keeps the focus in the box", () => {
  const answer = number({ component: "number" }, { t })
  const [box] = answer.element.inputs()
  box.type("125")
  box.setSelectionRange(0, 0)
  press(keysOf(answer)[0])
  assert.equal(box.value, "-125")
  assert.equal(focused, box)
  assert.equal(box.selectionStart, 1)
  assert.equal(answer.raw(), "-125")
  box.setSelectionRange(2, 4)
  press(keysOf(answer)[1])
  assert.equal(box.value, "-1,")
})

test("a scientific number has the same keys", () => {
  const answer = number({ component: "number", scientific: true }, { t })
  assert.equal(keysOf(answer).length, 2)
})

test("a fraction has one minus key, which writes into the numerator", () => {
  const answer = fraction({ component: "fraction" }, { t })
  const keys = keysOf(answer)
  assert.equal(keys.length, 1)
  assert.equal(keys[0].getAttribute("aria-label"), "Meno")
  assert.equal(keys[0].getAttribute("type"), "button")
  const [numerator, denominator] = answer.element.inputs()
  numerator.type("3")
  numerator.setSelectionRange(0, 0)
  denominator.type("4")
  press(keys[0])
  assert.equal(numerator.value, "-3")
  assert.equal(denominator.value, "4")
  assert.equal(focused, numerator)
  assert.equal(answer.raw(), '{"n":"-3","d":"4"}')
})

test("the key of a mixed number writes into the whole box when it had the focus last, and never into the denominator", () => {
  const answer = fraction({ component: "fraction", mixed: true }, { t })
  assert.equal(keysOf(answer).length, 1)
  const [whole, numerator, denominator] = answer.element.inputs()
  whole.type("2")
  whole.setSelectionRange(0, 0)
  whole.focus()
  press(keysOf(answer)[0])
  assert.equal(whole.value, "-2")
  assert.equal(focused, whole)
  denominator.focus()
  press(keysOf(answer)[0])
  assert.equal(denominator.value, "")
  assert.equal(whole.value, "--2")
  numerator.type("1")
  numerator.focus()
  numerator.setSelectionRange(0, 0)
  press(keysOf(answer)[0])
  assert.equal(numerator.value, "-1")
})

test("the keys never submit a form: a pointer press does not take the focus from the box", () => {
  const answer = number({ component: "number" }, { t })
  let prevented = false
  keysOf(answer)[0].fire("mousedown", { preventDefault: () => { prevented = true } })
  assert.ok(prevented)
})
