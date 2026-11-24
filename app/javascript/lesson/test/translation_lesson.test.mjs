// The Italian translation of a bilingual lesson (D-402), drawn from the served golden fixtures (test/fixtures/lang/served_lesson.json, _es): the four text
// functions of lesson/text.js look the Italian up in the `tr` of the block, the card and the body and put a `.tr` node after the target text; the card's «Traduzione»
// and the unit buttons flip the one state machine of items/translation.js; a legacy lesson draws exactly as it always did. The page itself (CSS, display) is run in
// Chrome by the render check (test/validation/lesson_render_translation_test.rb); here the nodes and attributes are checked in a small stand-in for the document.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { beforeEach, test } from "node:test"
import { install } from "./fake_dom.mjs"

install()
const fixture = (name) => JSON.parse(readFileSync(new URL(`../../../../test/fixtures/lang/${name}`, import.meta.url), "utf8"))

const { renderCard, withUnitButton } = await import("lesson/cards")
const { beside, inButton, plainText, renderInlineRich, renderRich, scoped, translationFor, translationOf } = await import("lesson/text")
const T = await import("items/translation")
const { figureStrings } = await import("lesson/diagrams/common")
const { translationPanel } = await import("lesson/diagrams/draw")
const { el } = await import("lesson/dom")

// a stand-in for the labels: any key answers with its own name, nested ones too
const names = (path = "") => new Proxy(function () {}, {
  get: (_t, key) => (key === Symbol.toPrimitive ? () => path : key === "toString" ? () => path : typeof key === "symbol" ? undefined : names(path ? `${path}.${key}` : String(key))),
  apply: () => path
})
const labels = { translation: { toggle: "Traduzione", unit: "Mostra la traduzione: %{words}" } }
const t = new Proxy(labels, { get: (target, key) => (key in target ? target[key] : names(String(key))) })

const contextOf = (body, extra = {}) => ({
  subject: body.subject, t, items: names("items"), lang: body.lang ?? null, trScopes: body.lang ? [body] : null,
  glossary: new Map(), noSpeech: true, safe: false, renderCheck: true, mount() {}, track() {}, firstUse: new Map(), topicHref: () => "#",
  rich(text) { return el("div", { class: "rich" }, renderRich(text, this)) }, ...extra
})

const trNodes = (root) => root.querySelectorAll(".tr")
const card = (body, n) => body.cards.find((c) => c.n === n)
const draw = (body, n, extra) => renderCard(card(body, n), contextOf(body, extra), { kicker: "", newRoles: [] })

beforeEach(() => install())

for (const file of ["served_lesson.json", "served_lesson_es.json"]) {
  const body = fixture(file)
  const lang = body.lang

  test(`${file}: translationOf finds the Italian in the block, then the card, then the body`, () => {
    const ctx = scoped(contextOf(body), body.cards[0].blocks[0], body.cards[0])
    assert.equal(translationOf(body.cards[0].blocks[0].text_it, ctx), body.cards[0].blocks[0].tr[body.cards[0].blocks[0].text_it])
    assert.equal(translationOf(body.cards[0].title_it, ctx), body.cards[0].tr[body.cards[0].title_it])
    assert.equal(translationOf(body.title_it, ctx), body.tr[body.title_it])
    assert.equal(translationOf("a string that code built", ctx), null)
    assert.equal(translationOf(body.title_it, { ...ctx, lang: null }), null, "a legacy lesson has no translation")
    assert.equal(translationOf(body.title_it, { ...ctx, noTr: true }), null, "a place that draws none")
  })

  test(`${file}: a text block is target text in a ${lang} paragraph with its Italian in one .tr after it`, () => {
    const article = draw(body, 1)
    const block = article.querySelector(".block-text")
    const paragraph = block.children[0]
    assert.equal(paragraph.tag, "p")
    assert.equal(paragraph.getAttribute("lang"), lang)
    assert.equal(paragraph.hasAttribute("data-translated"), true)
    assert.equal(paragraph.textContent, card(body, 1).blocks[0].text_it)
    const tr = block.querySelector(".tr")
    assert.ok(tr, "the translation node")
    assert.equal(tr.getAttribute("lang"), "it")
    assert.equal(tr.hasAttribute("data-nospeech"), true)
    assert.equal(tr.textContent, card(body, 1).blocks[0].tr[card(body, 1).blocks[0].text_it])
    // the unit button of a long text stands between the text and its translation; nothing else does
    const between = block.childNodes.slice(block.childNodes.indexOf(paragraph) + 1, block.childNodes.indexOf(tr))
    assert.ok(between.every((n) => n.getAttribute("class") === "tr-unit"), "the translation follows the text")
  })

  test(`${file}: the card title is translated under the heading, not in it, and the heading keeps its name`, () => {
    const article = draw(body, 1)
    const heading = article.querySelector("h2")
    assert.equal(heading.textContent, card(body, 1).title_it)
    assert.equal(heading.querySelectorAll(".tr").length, 0)
    assert.equal(heading.hasAttribute("data-translated"), true)
    assert.equal(heading.getAttribute("lang"), lang)
    const titleTr = article.querySelector(".card-titles .tr")
    assert.equal(titleTr.textContent, card(body, 1).tr[card(body, 1).title_it])
  })

  test(`${file}: «Traduzione» is in the card head, flips the card and opens every translation in it`, () => {
    const article = draw(body, 1)
    const head = article.querySelector(".card-head")
    const button = head.querySelector(".tr-toggle")
    assert.ok(button, "the card button")
    assert.equal(button.textContent, "Traduzione")
    assert.equal(button.getAttribute("aria-pressed"), "false")
    assert.equal(article.getAttribute("data-tr-scope"), "card")
    assert.equal(article.getAttribute("data-tr-card"), "1")
    assert.equal(T.isOpen(trNodes(article)[0]), false)
    button.click()
    assert.equal(article.getAttribute("data-translation"), "on")
    assert.equal(button.getAttribute("aria-pressed"), "true")
    for (const tr of trNodes(article)) assert.equal(T.isOpen(tr), true)
    button.click()
    assert.equal(T.isOpen(trNodes(article)[0]), false)
  })

  test(`${file}: «Ascolta» reads the target only: every translation node is out of the reading`, () => {
    const article = draw(body, 1)
    assert.ok(trNodes(article).length >= 3)
    for (const tr of trNodes(article)) assert.equal(tr.hasAttribute("data-nospeech"), true)
    // the target text carries its language, so a reader that walks the card says it in that voice, and the chrome (no lang) keeps the interface's
    for (const p of article.querySelector(".block-text").children.filter((n) => n.tag === "p")) assert.equal(p.getAttribute("lang"), lang)
  })

  test(`${file}: the check prompt, its options and its hint carry their Italian; no translation sits in a button`, () => {
    const article = draw(body, 1)
    const form = article.querySelector("form.check")
    const prompt = form.querySelector(".check-prompt")
    assert.equal(prompt.querySelector(".tr").textContent, card(body, 1).blocks[1].tr[card(body, 1).blocks[1].prompt_it])
    const optionTrs = form.querySelectorAll("label .tr")
    const check = card(body, 1).blocks[1]
    if (check.translate_material === false) {
      // form material (D-402): the options are forms, served with no Italian: drawn as they are, left out of the render check on purpose
      assert.deepEqual(optionTrs, [], "no translation under an option that is form material")
      assert.equal(form.querySelectorAll("label [data-tr-exempt]").length, check.options.length)
    } else assert.deepEqual(optionTrs.map((n) => n.textContent), check.options.map((o) => check.tr[o.text_it]))
    for (const tr of trNodes(article)) assert.equal(tr.closest("button"), null, "a translation is never inside a button")
  })

  test(`${file}: a long text gets a unit button that opens its block alone; a short check prompt does not`, () => {
    const article = draw(body, 1)
    const textBlock = article.querySelector(".block-text")
    const unit = textBlock.querySelector(".tr-toggle-unit")
    assert.ok(unit, "the unit button")
    assert.equal(unit.getAttribute("aria-label"), `Mostra la traduzione: ${card(body, 1).blocks[0].text_it.split(" ").slice(0, 6).join(" ")}…`)
    assert.equal(textBlock.getAttribute("data-tr-scope"), "block")
    assert.equal(textBlock.getAttribute("data-tr-block"), "1")
    assert.equal(article.querySelector(".block-check").querySelector(".tr-toggle-unit"), null, "a prompt shorter than a line has no button of its own")
    unit.click()
    assert.equal(textBlock.getAttribute("data-translation"), "on")
    assert.equal(T.isOpen(textBlock.querySelector(".tr")), true)
    assert.equal(T.isOpen(article.querySelector(".block-check .tr")), false, "the other block stays closed")
    // the card's own button closes it again, whatever the block did alone
    article.querySelector(".card-head .tr-toggle").click()
    article.querySelector(".card-head .tr-toggle").click()
    assert.equal(textBlock.hasAttribute("data-translation"), false)
  })

  test(`${file}: the reply of a check joins the open scope with its own table`, () => {
    const ctx = scoped(contextOf(body), card(body, 1).blocks[1], card(body, 1))
    const wrong = fixture("reply_check_wrong.json")
    const right = fixture("reply_check_right.json")
    const reply = scoped(ctx, wrong)
    const message = renderRich(wrong.message_it, reply)
    assert.equal(message.querySelector(".tr").textContent, wrong.tr[wrong.message_it])
    const explain = renderRich(right.explain_it, scoped(ctx, right))
    assert.equal(explain.querySelector(".tr").textContent, right.tr[right.explain_it])
    // without the reply's table the string has no Italian, and draws none
    assert.equal(renderRich(wrong.message_it, ctx).querySelector(".tr"), null)
  })

  test(`${file}: the solution reply of «Prova tu» carries its Italian`, async () => {
    const solution = fixture("reply_solution.json")
    const ctx = scoped(contextOf(body), card(body, 2).blocks[0], card(body, 2))
    const node = renderRich(solution.solution_it, scoped(ctx, solution))
    assert.equal(node.querySelector(".tr").textContent, solution.tr[solution.solution_it])
  })

  test(`${file}: «Prova tu» draws its intro, exercises and checks with their translations`, () => {
    const article = draw(body, 2)
    const block = card(body, 2).blocks[0]
    const trs = trNodes(article).map((n) => n.textContent)
    const exercise = block.exercises[0]
    for (const source of [block.intro_it, exercise.check.prompt_it]) assert.ok(trs.includes(block.tr[source]), `the translation of «${source}»`)
    const material = [exercise.text_it, ...exercise.check.options.map((o) => o.text_it)]
    if (exercise.translate_material === false) {
      // form material (D-402): the sentence with its blank and the options have no Italian and draw none
      for (const source of material) assert.equal(block.tr?.[source], undefined, `no Italian for «${source}»`)
      assert.equal(exercise.check.translate_material, false, "the marker is on the exercise's own check too")
      assert.ok(article.querySelector(".exercise-text [data-tr-exempt]"), "the sentence is exempt, not missing")
    } else for (const source of material) assert.ok(trs.includes(block.tr[source]), `the translation of «${source}»`)
  })

  test(`${file}: every target text on the card is in a translation unit or exempt (what the render check asks)`, () => {
    for (const n of [1, 2]) {
      const article = draw(body, n)
      const missing = []
      for (const run of article.runs()) {
        const parent = run.parentNode
        if (parent.closest(".tr, svg, [data-tr-exempt], [data-translated]")) continue
        if ((run.nodeValue.match(/\p{L}/gu) ?? []).length <= 3) continue
        const language = parent.closest("[lang]")?.getAttribute("lang")
        if (language === "en" || language === "es") missing.push(run.nodeValue)
      }
      assert.deepEqual(missing, [], `card ${n}`)
    }
  })

  test(`${file}: a string that code built finds no translation and the card says so (the render check's «translation missing»)`, () => {
    const ctx = contextOf(body)
    const target = el("p", { class: "built" })
    renderInlineRich("Built here: not in any table", target, ctx)
    assert.equal(target.getAttribute("lang"), lang)
    assert.equal(target.hasAttribute("data-translated"), false)
    assert.equal(target.hasAttribute("data-tr-exempt"), false)
    assert.equal(target.querySelector(".tr"), null)
  })
}

test("a place that draws no translation (a button, a fragment) marks its text as exempt, never as missing", () => {
  const body = fixture("served_lesson.json")
  const ctx = scoped(contextOf(body), body.cards[0])
  const chip = renderInlineRich("Base verb", el("span"), inButton(ctx))
  assert.equal(chip.querySelector(".tr"), null)
  assert.equal(chip.getAttribute("lang"), "en")
  assert.equal(chip.hasAttribute("data-tr-exempt"), true)
})

test("the Italian is drawn without a lookup, with Italian role spans, and never in the target's voice", () => {
  const body = fixture("served_lesson.json")
  const ctx = scoped(contextOf(body), body.cards[0].blocks[0], body.cards[0])
  const tr = translationFor(body.cards[0].blocks[0].text_it, ctx, { block: true })
  assert.equal(tr.getAttribute("class"), "tr")
  assert.equal(tr.querySelector("[lang]"), null, "the Italian text is not marked as target")
  assert.equal(translationFor("nothing here", ctx), null)
})

test("beside() puts a plain line's translation after it, and leaves a legacy line as it was", () => {
  const body = fixture("served_lesson.json")
  const ctx = scoped(contextOf(body), body.cards[0])
  const line = beside(el("h1", { text: body.title_it }), body.title_it, ctx, { tag: "p" })
  assert.equal(line.childNodes.length, 2)
  assert.equal(line.childNodes[0].getAttribute("lang"), "en")
  assert.equal(line.childNodes[1].textContent, body.tr[body.title_it])
  const plain = el("h1", { text: "Titolo" })
  assert.equal(beside(plain, "Titolo", { ...ctx, lang: null }), plain)
  assert.equal(plain.getAttribute("lang"), null)
})

test("a legacy lesson draws exactly as it always did: no language, no unit button, no «Traduzione», no .tr", () => {
  const legacy = fixture("served_lesson.json")
  delete legacy.lang
  const strip = (value) => {
    if (Array.isArray(value)) value.forEach(strip)
    else if (value && typeof value === "object") { delete value.tr; Object.values(value).forEach(strip) }
  }
  strip(legacy)
  const ctx = contextOf(legacy)
  const article = renderCard(card(legacy, 1), ctx, { kicker: "", newRoles: [] })
  assert.equal(trNodes(article).length, 0)
  assert.equal(article.querySelectorAll(".tr-toggle").length, 0)
  assert.equal(article.querySelectorAll("[lang]").length, 0)
  assert.equal(article.querySelectorAll("[data-translated], [data-tr-exempt], [data-tr-scope]").length, 0)
  // and a legacy lesson whose body still carries a table, but no language, ignores it
  const withTable = fixture("served_lesson.json")
  delete withTable.lang
  const second = renderCard(card(withTable, 1), contextOf(withTable), { kicker: "", newRoles: [] })
  assert.equal(trNodes(second).length, 0)
})

test("a span of the target language in a bilingual text draws no speaker of its own; in the Italian it keeps it", () => {
  const body = fixture("served_lesson.json")
  const speakers = []
  const ctx = { ...contextOf(body), noSpeech: false, speaker: () => null, t: new Proxy({ speech: { languages: { en: "inglese" }, listen_text_in: "%{language} %{text}", unapproved: "x" }, translation: labels.translation }, { get: (target, key) => (key in target ? target[key] : names(String(key))) }) }
  const scope = scoped(ctx, { tr: { "Say [[en:hello]] first": "Di' [[en:hello]] per primo" } })
  const target = renderInlineRich("Say [[en:hello]] first", el("p"), scope)
  speakers.push(...target.querySelectorAll(".speak").filter((b) => !b.closest(".tr")))
  assert.equal(speakers.length, 0, "no speaker in the target text")
  assert.equal(target.querySelector(".tr").querySelectorAll(".speak").length, 1, "the quoted word in the Italian keeps its speaker")
})

test("figureStrings lists the `_it` texts of a figure's data once each, its alt and caption apart", () => {
  const data = { type: "flow", alt_it: "A flow", caption_it: "Caption", nodes: [{ id: "a", label_it: "Start" }, { id: "b", label_it: "Start" }, { id: "c", label_it: "Stop" }], parts_it: ["x one", "y two"], states: [{ op_it: "Step" }] }
  assert.deepEqual(figureStrings(data), ["Start", "Stop", "x one", "y two", "Step"])
})

test("the panel of a figure says the alt's translation and then «target → italiano» for each text that has one", () => {
  const body = fixture("served_lesson.json")
  const data = { type: "flow", alt_it: "A short flow", nodes: [{ id: "a", label_it: "Start" }, { id: "b", label_it: "No entry" }] }
  const ctx = scoped(contextOf(body), { tr: { "A short flow": "Un breve flusso", Start: "Inizio" } })
  const panel = translationPanel(data, ctx)
  assert.equal(panel.getAttribute("class"), "tr dg-tr")
  assert.equal(panel.querySelector(".dg-tr-alt").textContent, "Un breve flusso")
  const rows = panel.querySelectorAll("li")
  assert.equal(rows.length, 1)
  assert.equal(rows[0].textContent, "Start → Inizio")
  assert.equal(translationPanel({ type: "flow", alt_it: "Unknown", nodes: [] }, ctx), null)
})

test("withUnitButton stays out of a mistake, a reveal and a block with a short translation", () => {
  const body = fixture("served_lesson.json")
  const ctx = scoped(contextOf(body), body.cards[0])
  const short = el("div", {}, el("p", { text: "x" }), el("span", { class: "tr", text: "Breve." }))
  assert.equal(withUnitButton(short, { type: "text", n: 1, text_it: "x" }, ctx).querySelector(".tr-toggle"), null)
  const long = () => el("div", {}, el("p", { text: "x" }), el("div", { class: "tr", text: "Una traduzione abbastanza lunga da meritare un pulsante suo." }))
  assert.equal(withUnitButton(long(), { type: "mistake", n: 1 }, ctx).querySelector(".tr-toggle"), null)
  assert.ok(withUnitButton(long(), { type: "callout", n: 1, text_it: "x" }, ctx).querySelector(".tr-toggle"))
  assert.equal(withUnitButton(long(), { type: "text", n: 1, text_it: "x" }, { ...ctx, lang: null }).querySelector(".tr-toggle"), null)
})

test("plainText of a target title is the title (its names stay the target's)", () => {
  assert.equal(plainText("Can + the **base** verb"), "Can + the base verb")
})

const { render: renderTable } = await import("lesson/blocks/table")

test("a table's cells are target text with their Italian under them (header_it, rows_it); the stacked column names draw none", () => {
  const body = fixture("served_lesson.json")
  const ctx = scoped(contextOf(body), body.cards[0])
  const block = { type: "table", n: 3, header: ["Verb", "Meaning"], rows: [["make", "to build"], ["do", "to carry out"]], header_it: ["Verbo", "Significato"], rows_it: [["fare", "costruire"], ["fare", "eseguire"]] }
  const node = renderTable(block, ctx)
  assert.deepEqual(trNodes(node).map((n) => n.textContent), ["Verbo", "Significato", "fare", "costruire", "fare", "eseguire"])
  for (const tr of trNodes(node)) assert.equal(tr.getAttribute("lang"), "it")
  for (const cell of [...node.querySelectorAll("th"), ...node.querySelectorAll("td")]) {
    assert.equal(cell.getAttribute("lang"), body.lang)
    assert.equal(cell.hasAttribute("data-translated"), true, "the render check finds no cell without its translation")
  }
  for (const label of node.querySelectorAll(".cell-label")) assert.equal(trNodes(label).length, 0, "a column name in a stacked cell draws no translation")
  const legacy = renderTable(block, { ...ctx, lang: null, trScopes: null })
  assert.equal(trNodes(legacy).length, 0, "a legacy lesson draws its table as it did")
  assert.equal(renderTable({ ...block, header_it: undefined, rows_it: undefined }, ctx).querySelectorAll("th")[0].hasAttribute("data-translated"), false, "an unpaired cell is what the render check reports")
})

test("a figure's own tr table is looked up for its panel, in front of the block's", () => {
  const body = fixture("served_lesson.json")
  const data = { type: "flow", alt_it: "A short flow", caption_it: "Two steps", nodes: [{ id: "a", label_it: "Start" }], tr: { "A short flow": "Un breve flusso", Start: "Inizio", "Two steps": "Due passi" } }
  const block = contextOf(body)
  const panel = translationPanel(data, scoped(block, data))
  assert.equal(panel.querySelector(".dg-tr-alt").textContent, "Un breve flusso")
  assert.equal(panel.querySelector("li").textContent, "Start → Inizio")
  assert.equal(translationPanel(data, block), null, "without the figure's scope nothing is found: the table is nested in the figure, not in the block")
  const caption = renderInlineRich(data.caption_it, el("figcaption"), scoped(block, data))
  assert.equal(caption.querySelector(".tr").textContent, "Due passi")
})

test("a colour role in a translation is Italian text: parsed with no target, its words are not the target's", () => {
  const body = fixture("served_lesson.json")
  const ctx = scoped(contextOf(body), { tr: { "The [[subject:cat]] sleeps.": "Il [[subject:gatto]] dorme." } })
  const node = renderInlineRich("The [[subject:cat]] sleeps.", el("p"), ctx)
  const italian = node.querySelector(".tr")
  assert.equal(italian.textContent, "Il gatto dorme.")
  assert.equal(italian.querySelectorAll("[lang=en], [lang=es]").length, 0, "the role word of the translation is not drawn as target-language text")
})

test("figureStrings: the labels of a flow's edges (third place) are texts of the figure; a mirror's Italian pieces are not", () => {
  const flow = { type: "flow", alt_it: "A flow", nodes: [{ id: "a", text_it: "Start" }], edges: [["a", "b"], ["b", "c", "last"], ["b", "d", "last"], ["b", "e", "other"]] }
  assert.deepEqual(figureStrings(flow), ["Start", "last", "other"])
  const mirror = { type: "mirror", alt_it: "A mirror", rows: [{ pieces_it: ["Lei", "legge"], pieces_es: ["Ella", "lee"], notes: [{ side: "es", piece: 1, note_it: "a note" }] }] }
  assert.deepEqual(figureStrings(mirror), ["a note"])
})

test("figureStrings reaches the strings of every state, the last too", () => {
  const data = { type: "sentence", alt_it: "A sentence", parts: [{ label_it: "first label" }], states: [{ op_it: "One" }, { op_it: "Two", parts: [{ label_it: "last label" }] }] }
  assert.deepEqual(figureStrings(data), ["first label", "One", "Two", "last label"])
})

const { markLabel } = await import("lesson/diagrams/draw")

test("markLabel: a served slot with its Italian is target text with a translation; one without it is asked for; the layout's own words are Italian; target-only material is exempt", () => {
  const body = fixture("served_lesson_es.json")
  const ctx = scoped(contextOf(body), { tr: { "me agrada": "mi piace" } })
  const served = new Set(["me agrada", "sin traducir"])
  const mark = (label) => { const node = el("div"); markLabel(node, label, ctx, { served, figureCtx: ctx }); return node }
  const said = mark({ text_it: "me agrada" })
  assert.equal(said.getAttribute("lang"), "es")
  assert.equal(said.hasAttribute("data-translated"), true)
  const asked = mark({ text_it: "sin traducir" })
  assert.equal(asked.getAttribute("lang"), "es")
  assert.equal(asked.hasAttribute("data-translated"), false)
  assert.equal(asked.hasAttribute("data-tr-exempt"), false, "the check asks for it")
  const chrome = mark({ text_it: "Qui batte la voce" })
  assert.equal(chrome.getAttribute("lang"), "it", "the legend line is interface text, never target text")
  const material = mark({ text_it: "triste", lang: "es" })
  assert.equal(material.getAttribute("lang"), "es")
  assert.equal(material.hasAttribute("data-tr-exempt"), true)
  const italianSide = mark({ text_it: "Lei", lang: "it" })
  assert.equal(italianSide.getAttribute("lang"), "it")
  const legacy = el("div")
  markLabel(legacy, { text_it: "x" }, { ...ctx, lang: null }, { served, figureCtx: ctx })
  assert.equal(legacy.getAttribute("lang"), null, "a legacy lesson is drawn as it was")
})

test("a word_parts word's `label_it` beside its `form_*` is the legacy Italian gloss («banana» under «plátano»): not a served text, drawn as Italian; a folded pair (tr has it) is target text", () => {
  const data = { type: "word_parts", alt_it: "Words", view: "syllables", words: [{ form_es: "plátano", label_it: "banana" }, { form_es: "sillón", label_it: "última" }], tr: { "última": "ultima" } }
  assert.deepEqual(figureStrings(data), ["última"])
  const ctx = scoped(contextOf(fixture("served_lesson_es.json")), data)
  const served = new Set(figureStrings(data))
  const mark = (text) => { const node = el("div"); markLabel(node, { text_it: text }, ctx, { served, figureCtx: ctx }); return node }
  assert.equal(mark("banana").getAttribute("lang"), "it", "no «es text with no Italian translation»")
  assert.equal(mark("última").getAttribute("lang"), "es")
})

const { glossaryList } = await import("lesson/cards")

test("the card's glossary lists an entry once, however the card names it: [[g:sílaba]] in the target and [[g:sillaba]] in its translation", () => {
  const body = fixture("served_lesson_es.json")
  const entry = { term_it: "sílaba", def_it: "Un trozo de palabra.", example_it: null }
  const ctx = { ...contextOf(body), glossary: new Map([["sílaba", entry], ["sillaba", entry]]) }
  const aCard = { n: 1, blocks: [{ type: "text", n: 1, text_it: "Cuenta las [[g:sílaba]]s.", tr: { "Cuenta las [[g:sílaba]]s.": "Conta le [[g:sillaba]]." } }] }
  const list = glossaryList(aCard, ctx)
  assert.equal(list.querySelectorAll("dt").length, 1)
  assert.equal(list.querySelectorAll("dd").length, 1)
})

const { layout: layoutFigure } = await import("lesson/diagrams/registry")

test("a served bilingual table figure (header_it, rows_it, tr) passes the schema check and carries its Italian cells to the drawing", () => {
  const figure = { type: "table", alt_it: "A table of questions: the subject and the form.", header: ["Subject", "Question"], rows: [["he, she", "Has she got a dog?"]], header_it: ["Soggetto", "Domanda"], rows_it: [["lui, lei", "Ha un cane?"]], tr: { "A table of questions: the subject and the form.": "Una tabella." } }
  const scene = layoutFigure(figure, { width: 320, fontPx: 16, subject: "english", measure: (text) => ({ w: String(text).length * 8, h: 20 }), state: 0 })
  assert.ok(!scene.error, scene.error?.message)
  assert.deepEqual(scene.table.header_it, ["Soggetto", "Domanda"])
  assert.deepEqual(scene.table.rows_it, [["lui, lei", "Ha un cane?"]])
  const legacy = layoutFigure({ ...figure, header_it: undefined, rows_it: undefined, tr: undefined }, { width: 320, fontPx: 16, subject: "math", measure: (text) => ({ w: String(text).length * 8, h: 20 }), state: 0 })
  assert.ok(!legacy.error, "a legacy table is drawn as ever")
  const stray = layoutFigure({ type: "flow", alt_it: "A flow of two steps.", nodes: [], header_it: ["x"] }, { width: 320, fontPx: 16, subject: "math", measure: () => ({ w: 1, h: 1 }), state: 0 })
  assert.ok(stray.error, "header_it is allowed on a table figure only")
})

const { render: renderMistake } = await import("lesson/blocks/mistake")

test("form material (translate_material: false): a table's cells and a mistake's right form draw no translation and are exempt from the render check", () => {
  const body = fixture("served_lesson.json")
  const ctx = scoped(contextOf(body), body.cards[0])
  const material = renderTable({ type: "table", n: 3, translate_material: false, header: ["Subject", "Verb"], rows: [["he", "plays"]] }, scoped(contextOf(body), body.cards[0], { tr: { Subject: "Soggetto" } }))
  assert.deepEqual(trNodes(material), [], "no translation under a form, even if a string of the table is in tr")
  assert.ok(material.querySelector("td [data-tr-exempt], td[data-tr-exempt]"))
  const mistake = renderMistake({ type: "mistake", n: 4, wrong_it: "He play", right_it: "He plays", why_it: "Add -s." }, scoped(contextOf(body), { tr: { "Add -s.": "Aggiungi -s." } }))
  const rightText = mistake.querySelectorAll(".mistake-text")[1]
  assert.equal(rightText.querySelector(".tr"), null)
  assert.equal(rightText.hasAttribute("data-tr-exempt"), true)
  assert.equal(mistake.querySelector(".mistake-why .tr").textContent, "Aggiungi -s.", "the why is still paired")
})

test("a served table figure that is form material passes the schema check and carries the marker to the drawing", () => {
  const figure = { type: "table", alt_it: "A table of forms: the subject and the verb.", header: ["Subject", "Verb"], rows: [["he", "plays"]], translate_material: false, tr: {} }
  const scene = layoutFigure(figure, { width: 320, fontPx: 16, subject: "english", measure: (text) => ({ w: String(text).length * 8, h: 20 }), state: 0 })
  assert.ok(!scene.error, scene.error?.message)
  assert.equal(scene.table.translate_material, false)
})

test("the legend's role name and question are the palette's own in the language of a bilingual lesson, with the Italian one as a translation; a legacy lesson keeps the Italian", async () => {
  const { sample, render } = await import("lesson/blocks/legend")
  const body = fixture("served_lesson_es.json")
  const ctx = contextOf(body, { subject: "spanish" })
  const chip = sample("verb", ctx)
  const named = chip.children?.[0] ?? chip
  assert.equal(named.getAttribute("lang"), "es")
  assert.equal(named.textContent, "verbo")
  assert.equal(named.hasAttribute("data-translated"), true)
  assert.equal(trNodes(chip).length + (chip.children ?? []).filter((n) => n.classList?.contains("tr")).length > 0, true, "the Italian name follows as a .tr")
  const muted = sample("muted", ctx)
  assert.match((muted.children?.[0] ?? muted).textContent, /secundario/, "a common role: secundario, not secondario")
  const legacy = sample("verb", { ...ctx, lang: null, trScopes: null })
  assert.equal(legacy.textContent, "verbo")
  assert.equal(legacy.getAttribute("lang"), null)
  const list = render({ roles: [{ role: "od" }] }, ctx)
  assert.match(list.textContent, /complemento directo/)
  assert.match(list.textContent, /¿Qué\? ¿A quién\?/)
  assert.doesNotMatch(render({ roles: [{ role: "od" }] }, { ...ctx, lang: null, trScopes: null }).textContent, /directo/)
})
