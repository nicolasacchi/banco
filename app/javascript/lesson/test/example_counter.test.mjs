// The worked example's counter «passo N di M»: M is the example's whole number of steps from the start, also when the page
// serves only the steps up to the first blank (steps_total), and N is the step just shown. A small stand-in for the document.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { render } = await import("lesson/blocks/example")

class Fake {
  constructor(tag) { this.tag = tag; this.attrs = {}; this.children = []; this.own = ""; this.listeners = {}; this.dataset = {}; this.parent = null; this.disabled = false; this.firstChild = null }
  set className(v) { this.attrs.class = v }
  get className() { return this.attrs.class ?? "" }
  set textContent(v) { this.children = []; this.own = String(v) }
  get textContent() { return this.own + this.children.map((c) => c.textContent).join("") }
  set hidden(v) { if (v) this.attrs.hidden = ""; else delete this.attrs.hidden }
  get hidden() { return "hidden" in this.attrs }
  setAttribute(name, value) { this.attrs[name] = String(value) }
  getAttribute(name) { return this.attrs[name] ?? null }
  removeAttribute(name) { delete this.attrs[name] }
  appendChild(child) {
    if (child instanceof Fake && child.tag === "#fragment") { for (const c of child.children) this.appendChild(c); child.children = []; return child }
    if (child.parent) child.parent.children = child.parent.children.filter((c) => c !== child)
    child.parent = this
    this.children.push(child)
    this.firstChild = this.children[0]
    return child
  }
  append(...nodes) { for (const node of nodes) this.appendChild(node) }
  replaceChildren(...nodes) { this.children = []; this.firstChild = null; this.append(...nodes) }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter((c) => c !== this) }
  addEventListener(name, fn) { this.listeners[name] = fn }
  get classList() {
    const set = () => new Set(this.className.split(/\s+/).filter(Boolean))
    return {
      add: (c) => { const s = set(); s.add(c); this.className = [...s].join(" ") },
      remove: (c) => { const s = set(); s.delete(c); this.className = [...s].join(" ") },
      toggle: (c, on) => { const s = set(); if (on) s.add(c); else s.delete(c); this.className = [...s].join(" ") },
      contains: (c) => set().has(c)
    }
  }
  click() { if (!this.disabled) this.listeners.click?.({}) }
  all(pred, out = []) {
    for (const child of this.children) if (child instanceof Fake) { if (pred(child)) out.push(child); child.all(pred, out) }
    return out
  }
  byClass(cls) { return this.all((n) => n.classList.contains(cls)) }
}

function withDom(fn) {
  globalThis.document = {
    createElement: (tag) => new Fake(tag),
    createElementNS: (_ns, tag) => new Fake(tag),
    createDocumentFragment: () => new Fake("#fragment"),
    createTextNode: (text) => ({ nodeType: 3, textContent: String(text), parent: null })
  }
  globalThis.window = {}
  return Promise.resolve(fn()).finally(() => {
    delete globalThis.document
    delete globalThis.window
  })
}

const t = { problem: "Problema", step: "Passo", why: "Perché", right: "Sì.", your_turn: "Tocca a te", answer_first: "Prima rispondi", result: "Risultato", first_step: "Mostra il primo passo", next_step_example: "Mostra il passo successivo", all_steps: "Mostra tutto", steps_count: "passo %{n} di %{total}" }
const ctx = { subject: "math", t, showAll: false }
const steps = [1, 2, 3].map((n) => ({ do_it: `Fai il passo ${n}`, why_it: `Perché ${n}` }))

const counter = (root) => root.byClass("reveal-count")[0].textContent
const button = (root, label) => root.byClass("example-controls")[0].children.find((b) => b.firstChild?.textContent === label)

test("an example of 3 steps reads «passo 1 di 3» after the first step and «passo 3 di 3» after the last", async () => {
  await withDom(() => {
    const root = render({ type: "example", problem_it: "Calcola.", steps, steps_total: 3 }, ctx, {})
    const next = button(root, "Mostra il primo passo")
    next.click()
    assert.equal(counter(root), "passo 1 di 3")
    button(root, "Mostra il passo successivo").click()
    assert.equal(counter(root), "passo 2 di 3")
    button(root, "Mostra il passo successivo").click()
    assert.equal(counter(root), "passo 3 di 3")
  })
})

test("the page serves 1 of 3 steps (the rest waits behind a blank): the counter still counts all 3", async () => {
  await withDom(() => {
    const root = render({ type: "example", problem_it: "Calcola.", steps: steps.slice(0, 1), steps_total: 3 }, ctx, {})
    button(root, "Mostra il primo passo").click()
    assert.equal(counter(root), "passo 1 di 3")
  })
})
