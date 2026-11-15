// Render polish from the wave 14 reviews (D-335): the era of a year on a timeline (d.C. only when the axis has a year before Christ), the
// help line of a whole-number box (no word about decimals), the sample of a bracket group in a formula's key (its subscripts lowered). The
// grid of a three-column table is in table_keep.test.mjs. A small stand-in for the document, as helper_keys.test.mjs has.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

class Node {
  constructor(tag) { this.tag = tag; this.attrs = {}; this.children = []; this.own = ""; this.listeners = {}; this.value = "" }
  set className(v) { this.attrs.class = v }
  get className() { return this.attrs.class ?? "" }
  set textContent(v) { this.children = []; this.own = String(v) }
  get textContent() { return this.own + this.children.map((c) => c.textContent).join("") }
  setAttribute(name, value) { this.attrs[name] = String(value) }
  getAttribute(name) { return this.attrs[name] ?? null }
  appendChild(child) { this.children.push(child); return child }
  addEventListener(name, fn) { (this.listeners[name] ??= []).push(fn) }
  all(pred, out = []) {
    for (const child of this.children) if (child instanceof Node) { if (pred(child)) out.push(child); child.all(pred, out) }
    return out
  }
  byClass(cls) { return this.all((n) => n.className.split(/\s+/).includes(cls)) }
}

const timeline = await import("lesson/diagrams/time/timeline")
const years = await import("lesson/diagrams/time/years")
const Chem = await import("lesson/lib/chem")
const formula = await import("lesson/diagrams/science/formula")

const axis = (from, to, events) => ({
  type: "timeline", alt_it: "Una linea del tempo con due fatti inventati e gli anni che passano tra loro.", scale: "years", from, to, every: 10,
  events: events.map(([id, at, label_it]) => ({ id, at, label_it }))
})
const MODERN = axis("1960", "1990", [["a", "1969", "Fatto prima"], ["b", "1977", "Fatto dopo"]])
const ANCIENT = axis("-50", "50", [["a", "-27", "Fatto prima"], ["b", "14", "Fatto dopo"]])

test("a modern axis prints its years without the era: 1969, not 1969 d.C.", () => {
  const printed = timeline.printed(MODERN, 0)
  assert.ok(printed.includes("1969") && printed.includes("1977"))
  assert.ok(printed.every((t) => !/d\.C\./.test(t)), printed.join(" | "))
  assert.match(timeline.describe(MODERN, { state: 0 }), /dal 1960 al 1990/)
  assert.match(timeline.describe(MODERN, { state: 0 }), /1969: Fatto prima/)
  const scene = timeline.layout(MODERN, { width: 390, fontPx: 20, subject: "history" })
  assert.ok(!scene.error)
  const texts = scene.labels.map((l) => l.text_it)
  assert.ok(texts.includes("1969: Fatto prima"), texts.join(" | "))
  assert.ok(texts.every((t) => !/d\.C\./.test(t)), texts.join(" | "))
})

test("an axis with a year before Christ prints a.C. and d.C. both", () => {
  const printed = timeline.printed(ANCIENT, 0)
  assert.ok(printed.includes("27 a.C.") && printed.includes("14 d.C.") && printed.includes("10 d.C."))
  assert.match(timeline.describe(ANCIENT, { state: 0 }), /dal 50 a\.C\. al 50 d\.C\./)
  const texts = timeline.layout(ANCIENT, { width: 390, fontPx: 20, subject: "history" }).labels.map((l) => l.text_it)
  assert.ok(texts.includes("14 d.C.: Fatto dopo"), texts.join(" | "))
})

test("yearLabel keeps a.C. always and d.C. only on an axis that has a year before Christ", () => {
  assert.equal(years.yearLabel("-27", { from: "1960" }), "27 a.C.")
  assert.equal(years.yearLabel("1969", { from: "1960" }), "1969")
  assert.equal(years.yearLabel("1969", { from: "-50" }), "1969 d.C.")
  assert.equal(years.yearLabel("14"), "14 d.C.", "without an axis the era is written")
  assert.equal(years.eventYearLabel({ at: "1969", approx: true }, { from: "1960" }), "circa 1969")
})

const t = { number_label: "Scrivi il numero. Per i decimali usa la virgola.", number_integer_label: "Scrivi il numero intero.", number_scientific_label: "Scrivi in notazione scientifica.", helper_keys: "Tasti", key_minus: "Meno", key_comma: "Virgola" }

test("a whole-number check says nothing about decimals; a decimal key keeps the line", async () => {
  globalThis.document = { createElement: (tag) => new Node(tag), createTextNode: (text) => ({ nodeType: 3, textContent: String(text) }) }
  try {
    const { render } = await import("items/number")
    const hint = (part) => render(part, { t }).element.byClass("hint")[0]
    assert.equal(hint({ component: "number", integer: true }).textContent, "Scrivi il numero intero.")
    assert.doesNotMatch(hint({ component: "number", integer: true }).textContent, /decimali/)
    assert.match(hint({ component: "number" }).textContent, /decimali/)
    assert.match(hint({ component: "number", integer: false }).textContent, /decimali/)
    const input = render({ component: "number", integer: true }, { t }).element.all((n) => n.tag === "input")[0]
    assert.equal(input.getAttribute("aria-label"), "Scrivi il numero intero.")
    assert.match(hint({ component: "number", scientific: true }).textContent, /scientifica/)
  } finally {
    delete globalThis.document
  }
})

test("the key's sample of a bracket group draws its subscripts lowered, as the formula does", () => {
  assert.equal(Chem.subscripted("(C2H4)"), "$(\\mathrm{C}_{2}\\mathrm{H}_{4})$")
  assert.equal(Chem.subscripted("(NO3)"), "$(\\mathrm{N}\\mathrm{O}_{3})$")
  assert.equal(Chem.subscripted("(NaCl)"), "(NaCl)", "no digit, nothing to lower")
  const scene = formula.layout({ type: "formula", alt_it: "La formula 2 Ca(NO3)2 con il suo pacchetto.", formulas: ["2 Ca(NO3)2"], show: ["parts"] }, { width: 390, fontPx: 20, subject: "chemistry" })
  assert.ok(!scene.error, JSON.stringify(scene.error))
  const sample = scene.labels.find((l) => l.cls.includes("dg-keygroup"))
  assert.ok(sample, "the group has a sample in the key")
  assert.equal(sample.text_it, "$(\\mathrm{N}\\mathrm{O}_{3})$")
})
