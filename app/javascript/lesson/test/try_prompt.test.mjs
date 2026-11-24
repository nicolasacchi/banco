// The question of a «Prova tu» number or fraction check is always on the page (revision 1051, exercises 3, 6, 7): the request in
// the check's prompt_it was hidden (sr-only) whenever the check had text before the box (input_before), leaving a phone with the
// three vertices and «2p =» and no «perimetro». The text around the box only labels the box. A small stand-in for the document.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { render } = await import("lesson/blocks/try")

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
  insertBefore(child, ref) {
    this.appendChild(child)
    this.children.splice(this.children.indexOf(child), 1)
    this.children.splice(this.children.indexOf(ref), 0, child)
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
  querySelector(sel) {
    const [tag, cls] = sel.replace(":scope > ", "").split(".")
    return this.all((n) => (!tag || n.tag === tag) && (!cls || n.classList.contains(cls)))[0] ?? null
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


const t = {
  exercise: "Esercizio", on_notebook: "sul quaderno", exercises: "Esercizi", exercise_of: "Esercizio %{n} di %{total}", prev_exercise: "Precedente", next_exercise: "Successivo",
  show_solution: "Mostra la soluzione", check_button: "Controlla", fraction_line_hint: "Scrivi 3 o 5/2"
}
const ctx = { subject: "math", t, items: { number_label: "Scrivi il numero", helper_keys: "Tasti", key_minus: "meno", key_bar: "barra", key_comma: "virgola" }, safe: false, pager: true }

const exercise = (check) => ({ n: 1, text_it: "Il triangolo $ABC$ ha i vertici $A(0; 0)$, $B(6; 0)$ e $C(6; 8)$.", check })
const prompts = (root) => root.byClass("check-prompt")
const hidden = (node) => node.classList.contains("sr-only") || node.parent?.classList.contains("sr-only")
const spoken = (node) => node.textContent

test("a number check with text before the box shows its request, not only «2p =»", async () => {
  await withDom(() => {
    const root = render({ type: "try", exercises: [exercise({ component: "number", prompt_it: "Quanto vale il perimetro?", input_before: "2p =", answer: "24" })] }, ctx, { card: 10, block: 1 })
    const [prompt] = prompts(root)
    assert.equal(prompts(root).length, 1)
    assert.match(spoken(prompt), /perimetro/)
    assert.equal(hidden(prompt), false)
    assert.match(spoken(root.byClass("check-before")[0]), /2p =/)
  })
})

test("a fraction check with text before the box shows its request", async () => {
  await withDom(() => {
    const root = render({ type: "try", exercises: [exercise({ component: "fraction", prompt_it: "Quanto vale l'ordinata di M?", input_before: "y_M =", answer: "9/2" })] }, ctx, { card: 10, block: 1 })
    assert.match(spoken(prompts(root)[0]), /ordinata/)
    assert.equal(hidden(prompts(root)[0]), false)
  })
})

test("a number check with text before and after the box shows its request, the box between the two", async () => {
  await withDom(() => {
    const root = render({ type: "try", exercises: [exercise({ component: "number", prompt_it: "Quanto vale il perimetro?", input_before: "2p =", input_after: "cm", answer: "24" })] }, ctx, { card: 10, block: 1 })
    const [prompt] = prompts(root)
    assert.equal(hidden(prompt), false)
    const row = root.byClass("check-row")[0]
    const names = row.children.map((c) => c.className.split(" ")[0])
    assert.ok(names.indexOf("check-before") < names.indexOf("answer") && names.indexOf("answer") < names.indexOf("check-after"), names.join(" "))
    assert.match(spoken(row.byClass("check-after")[0]), /cm/)
  })
})

// D-335: the helper keys of a typed answer are drawn once, by the shared items/helper_keys module (a number's own, the fraction line's «−» and «/»).
test("a number check and a one-line fraction check draw one row of helper keys", async () => {
  await withDom(() => {
    const keys = (component) => {
      const root = render({ type: "try", exercises: [exercise({ component, prompt_it: "Quanto vale?", answer: "3" })] }, ctx, { card: 10, block: 1 })
      return { rows: root.byClass("helper-keys").length, labels: root.byClass("helper-key").map((k) => k.textContent) }
    }
    assert.deepEqual(keys("number"), { rows: 1, labels: ["\u2212", ","] })
    assert.deepEqual(keys("fraction"), { rows: 1, labels: ["\u2212", "/"] })
  })
})

// D-402: the accent keyboard of a typed gap with text around the box sits below the sentence (before, box, after), not between the box and its `input_after`.
test("a typed gap with input_before and input_after keeps the sentence whole: the accent keyboard is below the row, not inside it", async () => {
  await withDom(() => {
    const spanish = { ...ctx, subject: "spanish", items: { ...ctx.items, text_label: "Scrivi", accents_label: "Lettere con l'accento" } }
    const root = render({ type: "try", exercises: [exercise({ component: "normalized_text", accents: "es", prompt_it: "Scrivi la parola.", input_before: "—¿", input_after: "vive tu tía?", answer: "Dónde" })] }, spanish, { card: 10, block: 1 })
    const row = root.byClass("check-row")[0]
    assert.equal(row.byClass("accent-keys").length, 0, "no keys between the box and input_after")
    assert.deepEqual(row.children.map((c) => c.className.split(" ")[0]), ["check-before", "answer", "check-after"])
    const form = row.parent
    assert.equal(form.children[form.children.indexOf(row) + 1].className, "accent-keys", "the keyboard comes right under the sentence")
  })
})

test("the text around the box of a typed gap is inline: «14. cm» after the box is text, not a list", async () => {
  await withDom(() => {
    const spanish = { ...ctx, subject: "spanish", items: { ...ctx.items, text_label: "Scrivi", accents_label: "Lettere" } }
    const root = render({ type: "try", exercises: [exercise({ component: "normalized_text", prompt_it: "Scrivi.", input_before: "Hay", input_after: "14. cm", answer: "x" })] }, spanish, { card: 10, block: 1 })
    const after = root.byClass("check-after")[0]
    assert.equal(after.all((n) => n.tag === "ol" || n.tag === "ul").length, 0)
    assert.match(after.textContent, /14\. cm/)
  })
})
