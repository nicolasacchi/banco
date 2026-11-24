// The bilingual items (D-402) drawn by the student's templates over a small stand-in document, from the golden served fixture
// (test/fixtures/lang/served_item.json): the target text, a translation node under each text, no button inside a control, the passage's Italian withheld until
// the exercise is over, the teacher's frozen slot open. A legacy payload is drawn exactly as before: no node, no button, no scope.
import "../../../app/javascript/lesson/test/setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const TEXT = 3

class Node {
  constructor(tag) { this.tagName = tag.toUpperCase(); this.attrs = new Map(); this.childNodes = []; this.parentNode = null; this.listeners = {}; this.dataset = {}; this.own = "" }
  get children() { return this.childNodes.filter((c) => c.nodeType !== TEXT) }
  get nodeType() { return 1 }
  set className(v) { this.attrs.set("class", String(v)) }
  get className() { return this.attrs.get("class") ?? "" }
  set textContent(v) { this.childNodes = []; this.own = String(v) }
  get textContent() { return this.own + this.childNodes.map((c) => c.textContent).join("") }
  setAttribute(name, value) { this.attrs.set(name, String(value)); if (name === "value") this.value = String(value) }
  getAttribute(name) { return this.attrs.has(name) ? this.attrs.get(name) : null }
  hasAttribute(name) { return this.attrs.has(name) }
  removeAttribute(name) { this.attrs.delete(name) }
  appendChild(child) {
    if (child.tagName === "#FRAGMENT") { for (const kid of [...child.childNodes]) this.appendChild(kid); return child }
    child.parentNode?.remove(child)
    child.parentNode = this
    this.childNodes.push(child)
    return child
  }
  remove(child) { this.childNodes = this.childNodes.filter((c) => c !== child) }
  addEventListener(name, fn) { (this.listeners[name] ??= []).push(fn) }
  dispatchEvent(event) { for (let n = this; n; n = n.parentNode) for (const fn of n.listeners[event.type] ?? []) fn(event); return true }
  click() { for (const fn of this.listeners.click ?? []) fn({}) }
  focus() {}
  get firstElementChild() { return this.children[0] ?? null }
  all(test, out = []) { for (const c of this.children) { if (test(c)) out.push(c); c.all(test, out) } return out }
  matches(selector) {
    return selector.split(",").some((part) => {
      const m = part.trim().match(/^([a-z0-9-]*)((?:\.[\w-]+)*)((?:\[[\w-]+(?:=[\w-]+)?\])*)(?::not\(\.([\w-]+)\))?$/)
      if (!m) throw new Error(`selector not understood: ${part}`)
      const [, tag, classes, attrs, notClass] = m
      const own = this.className.split(/\s+/)
      return (!tag || this.tagName === tag.toUpperCase()) &&
        classes.split(".").filter(Boolean).every((c) => own.includes(c)) &&
        [...attrs.matchAll(/\[([\w-]+)(?:=([\w-]+))?\]/g)].every(([, a, v]) => this.hasAttribute(a) && (v === undefined || this.getAttribute(a) === v)) &&
        !(notClass && own.includes(notClass))
    })
  }
  querySelectorAll(selector) { return this.all((n) => n.matches(selector)) }
  querySelector(selector) { return this.querySelectorAll(selector)[0] ?? null }
  closest(selector) { for (let n = this; n; n = n.parentNode) if (n.matches?.(selector)) return n; return null }
  get options() { return this.children.filter((c) => c.tagName === "OPTION") }
}

const html = new Node("html")
globalThis.document = {
  documentElement: html,
  createElement: (tag) => new Node(tag),
  createTextNode: (text) => ({ nodeType: TEXT, textContent: String(text), parentNode: null }),
  createDocumentFragment: () => new Node("#fragment"),
  querySelector: () => null,
  createTreeWalker: () => ({ nextNode: () => null })
}
globalThis.NodeFilter = { SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2 }

const fixture = JSON.parse(readFileSync(new URL("../../fixtures/lang/served_item.json", import.meta.url)))
const { renderItem } = await import("items/render")
const { sides, bare, langOf, reveal, LONG_WORDS } = await import("items/bilingual")
const T = await import("items/translation")
const { drawFrozen } = await import("items/frozen_slot")

const t = {
  choice_label: "Scegli", ordering_label: "Ordina", ordering_up: "Su", ordering_down: "Giù", matching_label: "Abbina", matching_reuse_label: "Classifica",
  matching_blank: "—", text_label: "Testo", accents_label: "Lettere", long_text_label: "Scrivi", passage: "Brano", question_of: "Domanda %{n}",
  dont_know: "Non lo so", steps_title: "Cosa fare", missing: "Manca", translation_toggle: "Traduzione", translation_unit: "Mostra la traduzione: %{words}"
}
const ctx = { t }

const trNodes = (root) => root.all((n) => n.matches(".tr"))
const buttons = (root) => root.all((n) => n.matches(".tr-toggle"))
const inside = (node, selector) => node.closest(selector) !== null
// What the student can read with the translation closed: the text of everything that is not a translation node.
const target = (root) => {
  const walk = (n) => (n.nodeType === TEXT ? n.textContent : n.matches(".tr") ? "" : n.own + n.childNodes.map(walk).join(""))
  return walk(root)
}
const scoped = (element, state = "off") => {
  const scope = new Node("div")
  scope.setAttribute("data-tr-scope", "item")
  scope.setAttribute("data-translation", state)
  scope.appendChild(element)
  return scope
}

// ---- the reader ---------------------------------------------------------------------------------------------

test("sides reads a pair, a legacy text and nothing, with the same call", () => {
  assert.deepEqual(sides({ stem_en: "Go.", stem_it: "Vai." }, "stem", "en"), { text: "Go.", italian: "Vai.", lang: "en" })
  assert.deepEqual(sides({ stem_es: "Ve.", stem_it: "Vai." }, "stem"), { text: "Ve.", italian: "Vai.", lang: "es" })
  assert.deepEqual(sides({ stem_it: "Vai." }, "stem"), { text: "Vai.", italian: null, lang: null })
  assert.equal(sides({}, "stem"), null)
  assert.equal(sides(null, "stem"), null)
  // an Italian-only hash of a language item read with the item's language is still the legacy text
  assert.deepEqual(sides({ stem_it: "Vai." }, "stem", "en"), { text: "Vai.", italian: null, lang: null })
  assert.deepEqual(bare({ text: "do", text_it: "fare" }, "text", "en"), { text: "do", italian: "fare" })
  assert.deepEqual(bare({ text: "do", text_it: "fare" }, "text", null), { text: "do", italian: null })
  assert.equal(langOf({ lang: "en" }), "en")
  assert.equal(langOf({ lang: "it" }), null)
  assert.equal(langOf({}, "es"), "es")
})

// ---- the choice and the blank of the golden fixture ----------------------------------------------------------

test("choice: the target text with a translation node under each text, no button anywhere", async () => {
  const handle = await renderItem(fixture.choice.part, ctx)
  const root = handle.element
  const text = target(root)
  assert.match(text, /Choose the two words for the gaps/)
  assert.match(text, /On Saturdays I ___ my bed/)
  assert.match(text, /make \/ do/)
  assert.match(text, /Each option has two parts/)
  assert.match(text, /Read the whole sentence/)
  assert.doesNotMatch(text, /Scegli le due parole|Il sabato io|fare \/ fare|Leggi tutta la frase/, "the Italian is only in translation nodes")
  const translations = trNodes(root).map((n) => n.textContent)
  assert.ok(translations.some((s) => s.includes("Scegli le due parole")))
  assert.ok(translations.some((s) => s.includes("Il sabato io")))
  assert.equal(translations.filter((s) => s === "fare / fare").length, 4, "one per option")
  assert.ok(translations.some((s) => s.includes("Ogni opzione ha due parti")))
  assert.ok(translations.some((s) => s.includes("Leggi tutta la frase")))
  for (const node of trNodes(root)) {
    assert.equal(node.getAttribute("lang"), "it")
    assert.equal(node.hasAttribute("data-nospeech"), true)
    assert.equal(inside(node, "button"), false, "never inside a button")
  }
  assert.equal(buttons(root).length, 0, "short texts have no unit button of their own; the exercise's button opens them")
  assert.equal(root.querySelector(".prompt").querySelector(".instance-stem").getAttribute("lang"), "en")
})

test("choice: an option's Italian sits in its label, and the choice itself is unchanged", async () => {
  const handle = await renderItem(fixture.choice.part, ctx)
  const labels = handle.element.querySelectorAll("label.option")
  assert.equal(labels.length, 4)
  for (const label of labels) {
    assert.equal(trNodes(label).length, 1)
    assert.equal(buttons(label).length, 0)
  }
  assert.equal(labels[1].querySelector(".option-text").textContent, "make / do")
  const radio = handle.element.querySelectorAll("input")[1]
  radio.checked = true
  assert.equal(handle.raw(), "o2")
})

test("the translation is hidden until the exercise's scope is open, and opens with the button", async () => {
  const handle = await renderItem(fixture.choice.part, ctx)
  const card = scoped(handle.element)
  const some = trNodes(handle.element)[0]
  assert.equal(T.state(some), "off")
  const button = T.toggleButton({ text: t.translation_toggle })
  card.appendChild(button)
  T.refresh(card)
  assert.equal(button.getAttribute("aria-pressed"), "false")
  button.click()
  assert.equal(card.getAttribute("data-translation"), "on")
  assert.equal(T.state(some), "on")
  assert.equal(button.getAttribute("aria-pressed"), "true")
  button.click()
  assert.equal(T.state(some), "off")
})

test("a text added later (a hint, the feedback) joins the open scope", () => {
  const card = scoped(new Node("div"), "on")
  const later = T.node("Guarda di nuovo i nomi.", { tag: "span" })
  card.appendChild(later)
  assert.equal(T.state(later), "on")
})

test("blank: a text box in English, the Italian of the stem under it", async () => {
  const handle = await renderItem(fixture.blank.part, ctx)
  assert.match(target(handle.element), /She ___ to school by bus\./)
  assert.doesNotMatch(target(handle.element), /Lei ___ a scuola/)
  assert.ok(trNodes(handle.element).some((n) => n.textContent === "Lei ___ a scuola in autobus."))
  assert.equal(handle.element.querySelector("input").getAttribute("lang"), "en")
})

test("a long Italian text gets a unit button in its own block, outside any control, named by the first words", async () => {
  const long = "Read the whole short text with great care before you choose the right word for the gap in the sentence that follows now."
  const part = { ...fixture.blank.part, stem_en: long, stem_it: Array(LONG_WORDS + 2).fill("parola").join(" ") }
  const handle = await renderItem(part, ctx)
  const unit = buttons(handle.element)
  assert.equal(unit.length, 1)
  assert.equal(unit[0].getAttribute("aria-label"), "Mostra la traduzione: Read the whole short text with…")
  assert.equal(inside(unit[0], "label") || inside(unit[0], "button:not(.tr-toggle)"), false)
  const card = scoped(handle.element)
  T.refresh(card)
  unit[0].click()
  const stemBlock = unit[0].closest("[data-tr-scope=block]")
  assert.equal(stemBlock.getAttribute("data-translation"), "on")
  assert.equal(T.state(trNodes(stemBlock)[0]), "on")
  const others = trNodes(handle.element).filter((n) => !stemBlock.all((x) => x === n).length)
  assert.ok(others.length > 0)
  for (const node of others) assert.equal(T.state(node), "off", "the other texts stay closed")
})

// ---- legacy ---------------------------------------------------------------------------------------------------

test("a legacy item is drawn as before: its Italian text, no translation node, no button, no lang", async () => {
  const legacy = {
    component: "choice", stem_it: "Scegli la parola.", instance_stem_it: "Il sole è ___.", steps_it: ["Leggi."], answer_format_it: "Scegli una risposta.",
    options: [{ id: "a", text: "caldo" }, { id: "b", text: "freddo" }]
  }
  const handle = await renderItem(legacy, ctx)
  assert.equal(trNodes(handle.element).length, 0)
  assert.equal(buttons(handle.element).length, 0)
  assert.equal(handle.element.all((n) => n.hasAttribute("lang")).length, 0)
  assert.match(handle.element.textContent, /Scegli la parola\./)
  assert.match(handle.element.textContent, /Il sole è ___\./)
  assert.match(handle.element.textContent, /Scegli una risposta\./)
  assert.equal(handle.element.querySelectorAll("label.option")[0].children.length, 3, "radio, key and text: no option-body")
  // an option that carries text_it but no lang (a lesson check's own shape) is not translated
  const lesson = await renderItem({ component: "choice", options: [{ id: "a", text: "caldo", text_it: "hot" }] }, ctx)
  assert.equal(trNodes(lesson.element).length, 0)
})

test("a legacy passage (English text under passage_it) is drawn as before", async () => {
  const handle = await renderItem({
    component: "testlet", passage_it: "Tom has a dog.", sub_items: [{ id: "s1", component: "choice", stem_it: "Chi ha un cane?", options: [{ id: "a", text: "Tom" }] }]
  }, ctx)
  assert.match(handle.element.querySelector(".passage").textContent, /Tom has a dog\./)
  assert.equal(handle.element.querySelector(".passage").hasAttribute("data-lang"), false)
  assert.equal(trNodes(handle.element).length, 0)
})

// ---- the reading rule -----------------------------------------------------------------------------------------

const testlet = (extra = {}) => ({
  component: "testlet", lang: "en", passage_en: "Tom has a dog. The dog is brown.",
  sub_items: [{ id: "s1", component: "choice", stem_en: "Who has a dog?", stem_it: "Chi ha un cane?", options: [{ id: "a", text: "Tom", text_it: "Tom" }, { id: "b", text: "Amy", text_it: "Amy" }] }],
  ...extra
})

test("a testlet's passage is the target text; its Italian is nowhere on the page before the answer", async () => {
  const handle = await renderItem(testlet(), ctx)
  const passage = handle.element.querySelector(".passage")
  assert.match(passage.textContent, /Tom has a dog\. The dog is brown\./)
  assert.equal(passage.getAttribute("lang"), "en")
  assert.equal(trNodes(passage).length, 0)
  // the sub item's own question is translated as usual, and inherits the testlet's language
  assert.ok(trNodes(handle.element).some((n) => n.textContent === "Chi ha un cane?"))
})

test("a passage_it that reaches the client with the part is still not drawn for the student", async () => {
  const handle = await renderItem(testlet({ passage_it: "Tom ha un cane. Il cane è marrone." }), ctx)
  assert.doesNotMatch(handle.element.textContent, /Tom ha un cane/)
  const alone = await renderItem({ ...fixture.blank.part, passage_en: "Tom has a dog.", passage_it: "Tom ha un cane." }, ctx)
  assert.doesNotMatch(alone.element.textContent, /Tom ha un cane/)
})

test("reveal adds the passage's Italian after the answer, once, as a translation node of the open scope", async () => {
  const handle = await renderItem(testlet(), ctx)
  const card = scoped(handle.element)
  assert.equal(reveal(card, "Tom ha un cane. Il cane è marrone."), true)
  assert.equal(reveal(card, "Tom ha un cane. Il cane è marrone."), false)
  const passage = card.querySelector(".passage")
  assert.equal(trNodes(passage).length, 1)
  assert.equal(trNodes(passage)[0].getAttribute("lang"), "it")
  assert.equal(T.state(trNodes(passage)[0]), "off")
  card.setAttribute("data-translation", "on")
  assert.equal(T.state(trNodes(passage)[0]), "on")
})

test("a short answer's passage follows the same rule", async () => {
  const part = { component: "short_answer", lang: "es", passage_es: "Ana vive en Madrid.", stem_es: "¿Dónde vive Ana?", stem_it: "Dove vive Ana?" }
  const handle = await renderItem(part, ctx)
  assert.equal(handle.element.querySelector(".passage").getAttribute("lang"), "es")
  assert.equal(handle.element.querySelector("textarea").getAttribute("lang"), "es")
  assert.equal(trNodes(handle.element.querySelector(".passage")).length, 0)
  assert.ok(trNodes(handle.element).some((n) => n.textContent === "Dove vive Ana?"))
  assert.equal(reveal(handle.element, "Ana vive a Madrid."), true)
})

// ---- the other templates ----------------------------------------------------------------------------------------

test("matching: the Italian of a left text under its row; the right-hand answers have theirs in a legend under the rows", async () => {
  const part = {
    component: "matching", lang: "en",
    left: [{ id: "l1", text: "dog", text_it: "cane" }, { id: "l2", text: "cat", text_it: "gatto" }],
    right: [{ id: "r1", text: "an animal that barks", text_it: "un animale che abbaia" }, { id: "r2", text: "an animal that purrs", text_it: "un animale che fa le fusa" }]
  }
  const handle = await renderItem(part, ctx)
  const rows = handle.element.querySelectorAll(".match-row")
  assert.equal(rows.length, 2)
  assert.deepEqual(rows.map((r) => trNodes(r).map((n) => n.textContent)), [["cane"], ["gatto"]])
  assert.equal(handle.element.querySelectorAll("option").some((o) => /abbaia|fusa/.test(o.textContent)), false, "an <option> holds text only")
  assert.equal(buttons(handle.element).length, 0)
  // the legend: after the rows, outside every select, one line per label, target then Italian, hidden with the exercise's translation (the state is on the list itself)
  const legend = handle.element.querySelector(".match-legend")
  assert.ok(legend)
  const answer = handle.element.querySelector(".answer")
  assert.equal(answer.children.indexOf(legend), answer.children.length - 1, "under the rows")
  assert.equal(legend.closest("select"), null)
  const lines = legend.querySelectorAll("li")
  assert.deepEqual(lines.map((li) => li.querySelector(".match-legend-target").textContent), ["an animal that barks", "an animal that purrs"])
  assert.deepEqual(lines.map((li) => li.querySelector(".match-legend-it").textContent), ["un animale che abbaia", "un animale che fa le fusa"])
  assert.equal(lines[0].querySelector(".match-legend-target").getAttribute("lang"), "en")
  assert.equal(lines[0].querySelector(".match-legend-it").getAttribute("lang"), "it")
  assert.equal(legend.hasAttribute("data-nospeech"), true)
  assert.equal(inside(legend, "button"), false)
})

test("ordering: a sentence has its Italian line, a word does not", async () => {
  const part = {
    component: "ordering", lang: "en",
    elements: [{ id: "e1", text: "Tom wakes up at seven.", text_it: "Tom si sveglia alle sette." }, { id: "e2", text: "then", text_it: "poi" }]
  }
  const handle = await renderItem(part, ctx)
  const rows = handle.element.querySelectorAll("li.order-row")
  assert.deepEqual(rows.map((r) => trNodes(r).map((n) => n.textContent)), [["Tom si sveglia alle sette."], []])
  assert.equal(buttons(handle.element).length, 0)
  assert.equal(handle.raw(), '["e1","e2"]')
})

test("a table: target cells with the Italian under each, the caption paired, no button in a cell", async () => {
  const part = {
    ...fixture.blank.part, table: {
      caption_en: "My day", caption_it: "La mia giornata", header: ["Time", "Action"], header_it: ["Ora", "Azione"],
      rows: [["7:00", "I wake up."]], rows_it: [["7:00", "Mi sveglio."]]
    }
  }
  const handle = await renderItem(part, ctx)
  const table = handle.element.querySelector("table")
  assert.deepEqual(trNodes(table).map((n) => n.textContent), ["La mia giornata", "Ora", "Azione", "7:00", "Mi sveglio."])
  assert.equal(buttons(table).length, 0)
  assert.equal(table.getAttribute("lang"), "en")
})

// ---- the teacher's frozen slot ------------------------------------------------------------------------------------

test("the frozen slot is an open translation scope, shows the passage's Italian too, and keeps its translation buttons working", async () => {
  const slot = new Node("div")
  slot.dataset.presentation = JSON.stringify(testlet({
    passage_it: "Tom ha un cane. Il cane è marrone.",
    sub_items: [{ id: "s1", component: "choice", stem_en: "Who has a dog? ".repeat(3), stem_it: Array(LONG_WORDS + 2).fill("cane").join(" "), options: [{ id: "a", text: "Tom", text_it: "Tom" }] }]
  }))
  await drawFrozen(slot, t)
  assert.equal(slot.getAttribute("data-translation"), "on")
  assert.equal(slot.getAttribute("data-tr-scope"), "item")
  const passage = slot.querySelector(".passage")
  assert.match(passage.textContent, /Tom ha un cane/)
  assert.equal(T.state(trNodes(passage)[0]), "on")
  assert.equal(slot.getAttribute("aria-disabled"), "true")
  for (const input of slot.querySelectorAll("input")) assert.equal(input.disabled, true)
  const unit = buttons(slot)
  assert.equal(unit.length, 1)
  assert.equal(unit[0].disabled, undefined, "a translation button is not an answer control")
  assert.equal(unit[0].getAttribute("aria-pressed"), "true")
})

test("the frozen slot of a legacy item draws it as before", async () => {
  const slot = new Node("div")
  slot.dataset.presentation = JSON.stringify({ component: "choice", stem_it: "Scegli.", options: [{ id: "a", text: "uno" }] })
  await drawFrozen(slot, t)
  assert.equal(trNodes(slot).length, 0)
  assert.equal(buttons(slot).length, 0)
  assert.match(slot.textContent, /Scegli\./)
})

// ---- the pairs the page reads after the answer -------------------------------------------------------------------------

test("the golden hint, feedback, reminder and solution are pairs that sides() reads", () => {
  for (const key of ["choice", "blank"]) {
    const served = fixture[key]
    const lang = langOf(served.part)
    assert.ok(sides(served.hint, "hint", lang).italian)
    assert.ok(sides(served.feedback, "message", lang).italian)
    assert.ok(sides(served.reminder, "reminder", lang).italian)
    assert.ok(sides(served.exercise, "title", lang).italian)
    for (const step of served.solution.steps) assert.ok(sides(step, "text", lang).italian)
    assert.ok(served.solution.final_it)
  }
})

// ---- [[it:..]] -----------------------------------------------------------------------------------------------------

test("[[it:..]] is drawn as an Italian span (lang it, the span's own class), in a stem, an option and a hint, and never printed as markup", async () => {
  const part = {
    component: "choice", lang: "en", stem_en: "Say [[it:ho fame]] in English.", stem_it: "Di' «ho fame» in inglese.",
    options: [{ id: "a", text: "I am hungry", text_it: "ho fame" }, { id: "b", text: "I have [[it:fame]]", text_it: "ho fame" }]
  }
  const handle = await renderItem(part, ctx)
  const spans = handle.element.querySelectorAll("span.lang-it")
  assert.deepEqual(spans.map((n) => [n.getAttribute("lang"), n.textContent]), [["it", "ho fame"], ["it", "fame"]])
  assert.equal(spans[0].closest(".prompt") !== null, true)
  assert.doesNotMatch(handle.element.textContent, /\[\[/)
  assert.match(target(handle.element), /Say ho fame in English\./, "the words are in the text, in the sentence")
  assert.equal(inside(spans[0], ".tr"), false, "it is part of the target text, not a translation node")
  // a legacy (Italian-only) item draws the span too: the parser is the same
  const legacy = await renderItem({ component: "choice", stem_it: "Come si dice [[it:ho fame]]?", options: [{ id: "a", text: "x" }] }, ctx)
  assert.equal(legacy.element.querySelectorAll("span.lang-it").length, 1)
  assert.doesNotMatch(legacy.element.textContent, /\[\[/)
})

// ---- form material: the instruction is a pair, the material is target-only ------------------------------------------------

const formFixture = JSON.parse(readFileSync(new URL("../../fixtures/lang/served_item_form.json", import.meta.url)))

test("a form-material choice (no _it on the sentence, the options, the final): no translation line or button on the material; the instruction, steps and format have theirs", async () => {
  const { part } = formFixture.choice
  assert.equal(langOf(part), "en")
  assert.equal(part.instance_stem_it, undefined)
  assert.equal(part.options.some((o) => "text_it" in o), false)
  const handle = await renderItem(part, ctx)
  const root = handle.element
  assert.match(target(root), /My brother ___ thirteen\./)
  assert.equal(trNodes(root.querySelector(".instance-stem")).length, 0, "the sentence is material")
  assert.equal(root.querySelector(".instance-stem").getAttribute("lang"), "en", "it is still drawn as English text")
  for (const label of root.querySelectorAll("label.option")) {
    assert.equal(trNodes(label).length, 0, "an option is a form")
    assert.equal(label.querySelectorAll(".option-body").length, 0, "no wrapper for a translation that is not there")
  }
  assert.equal(buttons(root).length, 0, "no unit button anywhere")
  assert.deepEqual(trNodes(root).map((n) => n.textContent), [
    "Scegli la forma che completa la frase.", "Leggi la frase.", "Guarda il soggetto.", "Scegli la forma.", "Scegli una parola per lo spazio."
  ])
  assert.doesNotMatch(target(root), /Scegli la forma|Leggi la frase|Guarda il soggetto|Scegli una parola|Mio fratello/, "the Italian is only in translation nodes")
})

test("a form-material item still has the «Traduzione» scope: it opens the instruction's Italian, the material stays alone", async () => {
  const { part, hint, solution } = formFixture.choice
  const handle = await renderItem(part, ctx)
  const card = scoped(handle.element)
  const button = T.toggleButton({ text: t.translation_toggle })
  card.appendChild(button)
  T.refresh(card)
  button.click()
  assert.equal(button.getAttribute("aria-pressed"), "true")
  const open = trNodes(handle.element).filter((n) => T.state(n) === "on")
  assert.equal(open.length, 5)
  assert.equal(open.some((n) => inside(n, ".instance-stem") || inside(n, "label.option")), false)
  // what comes later: the hint and the solution steps are pairs, the final is not
  const lang = langOf(part)
  assert.equal(sides(hint, "hint", lang).italian, "Guarda di chi parla la frase.")
  assert.equal(sides(solution.steps[0], "text", lang).italian, "Mio fratello è una persona: «he» vuole «is».")
  assert.deepEqual(bare(solution, "final", lang), { text: "is", italian: null })
  assert.deepEqual(bare(part.options[0], "text", lang), { text: "am", italian: null })
})

test("a form-material matching: the rows alone, the verdict labels in the legend; a matching with no Italian on the right has no legend", async () => {
  const { part } = formFixture.matching
  const handle = await renderItem(part, ctx)
  const rows = handle.element.querySelectorAll(".match-row")
  assert.deepEqual(rows.map((r) => trNodes(r).length), [0, 0], "the sentences are material")
  assert.deepEqual(handle.element.querySelector(".match-legend").querySelectorAll("li").map((li) => li.querySelector(".match-legend-it").textContent), ["giusta", "ha un errore"])
  const bare_ = await renderItem({ ...part, right: part.right.map(({ id, text }) => ({ id, text })) }, ctx)
  assert.equal(bare_.element.querySelector(".match-legend"), null)
  const legacy = await renderItem({ component: "matching", left: [{ id: "l1", text: "cane" }], right: [{ id: "r1", text: "dog", text_it: "cane" }] }, ctx)
  assert.equal(legacy.element.querySelector(".match-legend"), null, "a legacy item has no legend")
})

test("an item with a lang and no Italian at all draws the target text alone (no node, no button, nothing broken)", async () => {
  const handle = await renderItem({ component: "choice", lang: "es", stem_es: "Elige.", instance_stem_es: "¿___ vives?", options: [{ id: "a", text: "Dónde" }] }, ctx)
  assert.equal(trNodes(handle.element).length, 0)
  assert.equal(buttons(handle.element).length, 0)
  assert.match(target(handle.element), /Elige\./)
  assert.match(target(handle.element), /¿___ vives\?/)
})
