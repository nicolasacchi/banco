// The half-typed answer of an exercise left open (practice/2): every handle of the item templates has draft() (a PARTIAL answer as text,
// "" when nothing is typed or chosen) and restore(draft) (silently ignores a broken or foreign draft), and every template announces a
// change of the answer with a bubbling "item-change" event. The templates run here on a small stand-in for the document (as in
// helper_keys.test.mjs). The MathLive field needs a real browser: its half of expression.js is not covered here, the text fallback is.
import "../../../app/javascript/lesson/test/setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

class Node {
  constructor(tag) {
    this.tag = tag; this.attrs = {}; this.children = []; this.own = ""; this.listeners = {}; this.parent = null
    this.value = ""; this.checked = false; this.selectionStart = null; this.selectionEnd = null; this.dataset = {}
    const node = this
    this.classList = {
      list: () => node.className.split(/\s+/).filter(Boolean),
      add: (name) => { if (!node.classList.contains(name)) node.className = [...node.classList.list(), name].join(" ") },
      remove: (name) => { node.className = node.classList.list().filter((n) => n !== name).join(" ") },
      toggle: (name, force) => (force ?? !node.classList.contains(name)) ? node.classList.add(name) : node.classList.remove(name),
      contains: (name) => node.classList.list().includes(name)
    }
  }
  set className(v) { this.attrs.class = v }
  get className() { return this.attrs.class ?? "" }
  set textContent(v) { this.children = []; this.own = String(v) }
  get textContent() { return this.own + this.children.map((c) => c.textContent).join("") }
  setAttribute(name, value) {
    this.attrs[name] = String(value)
    if (name === "value") this.value = String(value)
  }
  getAttribute(name) { return this.attrs[name] ?? null }
  hasAttribute(name) { return name in this.attrs }
  removeAttribute(name) { delete this.attrs[name] }
  appendChild(child) {
    if (child instanceof Node) {
      child.parent?.detach(child)
      child.parent = this
    }
    this.children.push(child)
    return child
  }
  detach(child) { this.children = this.children.filter((c) => c !== child) }
  insertBefore(child, ref) {
    child.parent?.detach(child)
    child.parent = this
    this.children.splice(this.children.indexOf(ref), 0, child)
    return child
  }
  addEventListener(name, fn) { (this.listeners[name] ??= []).push(fn) }
  // A click bubbles to the parents, as in the browser (the helper keys' row hears the key's click).
  fire(name, event = {}) {
    for (const fn of this.listeners[name] ?? []) fn({ preventDefault() {}, ...event })
    if (name === "click") this.parent?.fire(name, event)
  }
  dispatchEvent(event) {
    for (let node = this; node; node = node.parent) for (const fn of node.listeners[event.type] ?? []) fn(event)
    return true
  }
  focus() { focused = this; this.fire("focus") }
  scrollIntoView() { scrolled = this }
  setSelectionRange(a, b) { this.selectionStart = a; this.selectionEnd = b }
  type(text) { this.value = text; this.selectionStart = this.selectionEnd = text.length; this.fire("input") }
  all(pred, out = []) {
    for (const child of this.children) if (child instanceof Node) { if (pred(child)) out.push(child); child.all(pred, out) }
    return out
  }
  byClass(cls) { return this.all((n) => n.className.split(/\s+/).includes(cls)) }
  byTag(tag) { return this.all((n) => n.tag === tag) }
  querySelector(selector) { return this.byClass(selector.slice(1))[0] ?? null }
  get options() { return this.children.filter((c) => c.tag === "option") }
}

let focused = null
let scrolled = null
globalThis.document = {
  createElement: (tag) => new Node(tag),
  createTextNode: (text) => ({ nodeType: 3, textContent: String(text) }),
  createDocumentFragment: () => new Node("#fragment")
}

const { render: number } = await import("items/number")
const { render: fraction } = await import("items/fraction")
const { render: expression } = await import("items/expression")
const { render: choice } = await import("items/choice")
const { render: ordering } = await import("items/ordering")
const { render: matching } = await import("items/matching")
const { render: normalizedText } = await import("items/normalized_text")
const { render: shortAnswer } = await import("items/short_answer")
const { renderPart } = await import("items/render")

const t = {
  number_label: "Numero", fraction_numerator: "Numeratore", fraction_denominator: "Denominatore", fraction_whole: "Parte intera",
  helper_keys: "Tasti", key_minus: "Meno", key_comma: "Virgola", expression_label: "Espressione", expression_text_hint: "Scrivi",
  expression_echo: "Si legge", choice_label: "Scegli", ordering_label: "Ordina", ordering_up: "Su", ordering_down: "Giù",
  matching_label: "Abbina", matching_reuse_label: "Classifica", matching_blank: "—", text_label: "Testo", accents_label: "Lettere",
  long_text_label: "Scrivi", passage: "Brano", question_of: "Domanda %{n}", dont_know: "Non lo so"
}
const ctx = { t }

// Counts the item-change events that reach the template's element.
function listen(answer) {
  const seen = { count: 0 }
  answer.element.addEventListener("item-change", () => { seen.count += 1 })
  return seen
}

// restore(draft()) on a second, fresh instance gives the same draft and the same raw answer.
function roundTrips(first, second) {
  second.restore(first.draft())
  assert.equal(second.draft(), first.draft())
  assert.equal(second.raw(), first.raw())
}

// Garbage never throws. A template whose draft has a structure (fraction, choice, ordering, matching, testlet) also stays as it was;
// the free text of the others takes any string as typed text.
function ignoresGarbage(answer, { unchanged = true } = {}) {
  const before = [answer.draft(), answer.raw()]
  for (const garbage of ["garbage", "{", "[1,2", "null", "42", '{"x":1}', undefined, null, 7, {}]) answer.restore(garbage)
  if (unchanged) assert.deepEqual([answer.draft(), answer.raw()], before)
}

test("number: a draft is the typed text, '' when empty; restore puts it back and nothing else", () => {
  const first = number({ component: "number" }, ctx)
  assert.equal(first.draft(), "")
  const seen = listen(first)
  first.element.byTag("input")[0].type("12,5")
  assert.equal(seen.count, 1)
  assert.equal(first.draft(), "12,5")
  roundTrips(first, number({ component: "number" }, ctx))
  ignoresGarbage(number({ component: "number" }, ctx), { unchanged: false })
  const foreign = number({ component: "number" }, ctx)
  foreign.restore('{"n":"1","d":"2"}')
  assert.equal(foreign.draft(), "")
})

test("number: the helper keys announce a change", () => {
  const answer = number({ component: "number" }, ctx)
  const seen = listen(answer)
  answer.element.byClass("helper-key")[1].fire("click")
  assert.equal(seen.count, 1)
  assert.equal(answer.raw(), ",")
})

test("fraction: a numerator alone is a draft and round-trips; garbage is ignored", () => {
  const first = fraction({ component: "fraction" }, ctx)
  assert.equal(first.draft(), "")
  const seen = listen(first)
  first.element.byTag("input")[0].type("3")
  assert.equal(seen.count, 1)
  assert.equal(first.draft(), '{"n":"3","d":""}')
  roundTrips(first, fraction({ component: "fraction" }, ctx))
  const fresh = fraction({ component: "fraction" }, ctx)
  ignoresGarbage(fresh)
  assert.equal(fresh.draft(), "")
  assert.equal(fresh.isEmpty(), true)
})

test("fraction: a mixed number keeps the whole part; the minus key announces a change", () => {
  const first = fraction({ component: "fraction", mixed: true }, ctx)
  const seen = listen(first)
  const [whole, numerator, denominator] = first.element.byTag("input")
  whole.type("2"); numerator.type("1"); denominator.type("4")
  assert.equal(seen.count, 3)
  assert.equal(first.draft(), '{"n":"1","d":"4","w":"2"}')
  roundTrips(first, fraction({ component: "fraction", mixed: true }, ctx))
  first.element.byClass("helper-key")[0].fire("click")
  assert.equal(seen.count, 4)
})

const options = [{ id: "a", text: "Uno" }, { id: "b", text: "Due" }, { id: "c", text: "Tre" }]

test("choice: the chosen id is the draft; an unknown id is ignored; '' clears", () => {
  const first = choice({ component: "choice", options }, ctx)
  assert.equal(first.draft(), "")
  const seen = listen(first)
  const radios = first.element.byTag("input")
  radios[1].checked = true
  radios[1].fire("change")
  assert.equal(seen.count, 1)
  assert.equal(first.draft(), "b")
  roundTrips(first, choice({ component: "choice", options }, ctx))
  first.restore("zzz")
  assert.equal(first.draft(), "b")
  ignoresGarbage(first)
  assert.equal(first.draft(), "b")
  first.restore("")
  assert.equal(first.draft(), "")
})

test("choice: a number key picks an option and announces it", () => {
  const answer = choice({ component: "choice", options }, ctx)
  const seen = listen(answer)
  answer.element.fire("keydown", { key: "3" })
  assert.equal(seen.count, 1)
  assert.equal(answer.draft(), "c")
})

const elements = [{ id: "x1", text: "Primo" }, { id: "x2", text: "Secondo" }, { id: "x3", text: "Terzo" }]

test("ordering: the shown order is no draft; a moved step is; restore puts the order back", () => {
  const first = ordering({ component: "ordering", elements }, ctx)
  assert.equal(first.draft(), "")
  const seen = listen(first)
  first.element.byClass("order-row")[0].byTag("button")[1].fire("click")
  assert.equal(seen.count, 1)
  assert.equal(first.raw(), '["x2","x1","x3"]')
  assert.equal(first.draft(), '["x2","x1","x3"]')
  roundTrips(first, ordering({ component: "ordering", elements }, ctx))
  first.element.byClass("order-row")[0].fire("keydown", { altKey: true, key: "ArrowDown" })
  assert.equal(seen.count, 2)
  // Back to the shown order: nothing typed.
  first.element.byClass("order-row")[0].fire("keydown", { altKey: true, key: "ArrowUp" })
  assert.equal(first.draft(), "")
  assert.equal(first.raw(), '["x1","x2","x3"]')
})

test("ordering: a draft that is not the ids of this item is ignored; '' resets", () => {
  const answer = ordering({ component: "ordering", elements }, ctx)
  answer.restore('["x3","x2","x1"]')
  assert.equal(answer.raw(), '["x3","x2","x1"]')
  for (const bad of ['["x1","x2"]', '["x1","x2","q"]', '["x1","x1","x2"]', "garbage", '{"a":1}', null, 3, undefined]) {
    answer.restore(bad)
    assert.equal(answer.raw(), '["x3","x2","x1"]')
  }
  answer.restore("")
  assert.equal(answer.raw(), '["x1","x2","x3"]')
})

const pairs = {
  component: "matching",
  left: [{ id: "l1", text: "Gatto" }, { id: "l2", text: "Cane" }, { id: "l3", text: "Topo" }],
  right: [{ id: "r1", text: "miagola" }, { id: "r2", text: "abbaia" }, { id: "r3", text: "squittisce" }]
}
const pick = (answer, row, value) => {
  const select = answer.element.byTag("select")[row]
  select.value = value
  select.fire("change")
}

test("matching: a partial matching round-trips; '' when no row is set; garbage and unknown ids are ignored", () => {
  const first = matching(pairs, ctx)
  assert.equal(first.draft(), "")
  const seen = listen(first)
  pick(first, 0, "r2")
  pick(first, 2, "r3")
  assert.equal(seen.count, 2)
  assert.equal(first.draft(), '{"l1":"r2","l2":"","l3":"r3"}')
  const second = matching(pairs, ctx)
  roundTrips(first, second)
  // The entries taken in one select are greyed in the others, after a restore too.
  assert.equal(second.element.byTag("select")[1].options.find((o) => o.value === "r2").disabled, true)
  ignoresGarbage(matching(pairs, ctx))
  const fresh = matching(pairs, ctx)
  fresh.restore('{"l1":"nope","l2":"r1","zz":"r3","l3":5}')
  assert.equal(fresh.draft(), '{"l1":"","l2":"r1","l3":""}')
})

test("matching: showMissing marks the empty rows, focuses the first, and a mark goes when the row is answered", () => {
  const answer = matching(pairs, ctx)
  pick(answer, 1, "r1")
  assert.equal(answer.showMissing(), 2)
  const rows = answer.element.byClass("match-row")
  const selects = answer.element.byTag("select")
  assert.deepEqual(rows.map((r) => r.classList.contains("missing")), [true, false, true])
  assert.deepEqual(selects.map((s) => s.getAttribute("aria-invalid")), ["true", null, "true"])
  assert.equal(focused, selects[0])
  assert.equal(scrolled, rows[0])
  pick(answer, 0, "r2")
  assert.deepEqual(rows.map((r) => r.classList.contains("missing")), [false, false, true])
  assert.equal(selects[0].getAttribute("aria-invalid"), null)
  assert.equal(answer.showMissing(false), 1)
  pick(answer, 2, "r3")
  assert.equal(answer.showMissing(), 0)
  assert.equal(rows.some((r) => r.classList.contains("missing")), false)
})

test("matching: a classification (reuse_right) round-trips and marks too", () => {
  const part = { ...pairs, reuse_right: true }
  const first = matching(part, ctx)
  pick(first, 0, "r1"); pick(first, 1, "r1")
  roundTrips(first, matching(part, ctx))
  assert.equal(first.showMissing(), 1)
})

test("normalized_text: the typed text is the draft; an accent key announces a change", () => {
  const part = { component: "normalized_text", accents: "es" }
  const first = normalizedText(part, ctx)
  assert.equal(first.draft(), "")
  const seen = listen(first)
  first.element.byTag("input")[0].type("mañana")
  assert.equal(seen.count, 1)
  first.element.byTag("button")[0].fire("click")
  assert.equal(seen.count, 2)
  assert.equal(first.draft(), "mañanaá")
  roundTrips(first, normalizedText(part, ctx))
  ignoresGarbage(normalizedText(part, ctx), { unchanged: false })
  const typed = normalizedText(part, ctx)
  typed.restore("   ")
  assert.equal(typed.draft(), "")
})

test("short_answer: the typed text keeps its lines and round-trips", () => {
  const first = shortAnswer({ component: "short_answer" }, ctx)
  assert.equal(first.draft(), "")
  const seen = listen(first)
  first.element.byTag("textarea")[0].type("una riga\nun'altra")
  assert.equal(seen.count, 1)
  assert.equal(first.draft(), "una riga\nun'altra")
  roundTrips(first, shortAnswer({ component: "short_answer" }, ctx))
  const fresh = shortAnswer({ component: "short_answer" }, ctx)
  fresh.restore(undefined)
  fresh.restore({})
  assert.equal(fresh.draft(), "")
})

test("expression (the text fallback): the typed text is the draft; restore is silent", async () => {
  const first = await expression({ component: "expression", input: "text" }, ctx)
  assert.equal(first.draft(), "")
  const seen = listen(first)
  first.element.byTag("input")[0].type("2x+1")
  assert.equal(seen.count, 1)
  assert.equal(first.draft(), "2x+1")
  const second = await expression({ component: "expression", input: "text" }, ctx)
  const heard = listen(second)
  roundTrips(first, second)
  assert.equal(heard.count, 0)
  ignoresGarbage(await expression({ component: "expression", input: "text" }, ctx), { unchanged: false })
})

const testlet = {
  component: "testlet",
  passage_it: "",
  sub_items: [
    { id: "s1", component: "number" },
    { id: "s2", component: "matching", left: pairs.left, right: pairs.right },
    { id: "s3", component: "choice", options }
  ]
}

test("testlet: the draft is a JSON of the parts' drafts; restore puts each part back; a change of a part reaches the testlet", async () => {
  const first = await renderPart(testlet, ctx)
  assert.equal(first.draft(), "")
  const seen = listen(first)
  const [box] = first.element.byTag("input")
  box.type("7")
  const sections = first.element.byClass("sub-item")
  sections[1].byTag("select")[0].value = "r3"
  sections[1].byTag("select")[0].fire("change")
  const giveUp = sections[2].byClass("give-up")[0]
  giveUp.checked = true
  giveUp.fire("change")
  assert.equal(seen.count, 3)
  const draft = JSON.parse(first.draft())
  assert.deepEqual(draft.s1, { d: "7", g: false })
  assert.deepEqual(draft.s2, { d: '{"l1":"r3","l2":"","l3":""}', g: false })
  assert.deepEqual(draft.s3, { d: "", g: true })
  const second = await renderPart(testlet, ctx)
  roundTrips(first, second)
  assert.equal(second.element.byClass("sub-item")[2].classList.contains("given-up"), true)
  const fresh = await renderPart(testlet, ctx)
  ignoresGarbage(fresh)
  fresh.restore('{"s1":"7","zz":{"d":"1"},"s2":null}')
  assert.equal(fresh.draft(), "")
})

test("testlet: showMissing marks the parts with no answer, the empty rows of a matching, not a part given up", async () => {
  const answer = await renderPart(testlet, ctx)
  const sections = answer.element.byClass("sub-item")
  const giveUp = sections[2].byClass("give-up")[0]
  giveUp.checked = true
  giveUp.fire("change")
  assert.equal(answer.showMissing(), 2)
  assert.equal(sections[0].classList.contains("missing"), true)
  assert.equal(sections[2].classList.contains("missing"), false)
  assert.equal(sections[1].byClass("match-row").every((r) => r.classList.contains("missing")), true)
  assert.equal(focused, sections[0].byTag("input")[0])
  // Typing in the part clears its mark.
  sections[0].byTag("input")[0].type("1")
  assert.equal(sections[0].classList.contains("missing"), false)
})
