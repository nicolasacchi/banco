import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"

const { createTiles, createOrdering } = await import("lesson/checks/sequence_model")
const { nearest, targetLabel } = await import("lesson/checks/select_model")
const { firstUses, locKey, howtoKey } = await import("lesson/checks/howto")
const { usedBy } = await import("lesson/preload")
const { sequenceText, targetNames } = await import("lesson/teacher_notes")

test("tiles: a tile goes to the line once, comes back, moves one place, and the bank keeps the served order", () => {
  const m = createTiles(["e1", "e2", "e3", "e4"])
  m.place("e3").place("e1").place("e3")
  assert.deepEqual(m.line(), ["e3", "e1"])
  assert.deepEqual(m.bank(), ["e2", "e4"])
  m.move("e1", -1)
  assert.deepEqual(m.line(), ["e1", "e3"])
  m.move("e1", -1)
  assert.deepEqual(m.line(), ["e1", "e3"], "at the left end it stays")
  m.move("e3", 1)
  assert.deepEqual(m.line(), ["e1", "e3"], "at the right end it stays")
  m.remove("e1")
  assert.deepEqual(m.line(), ["e3"])
  assert.deepEqual(m.bank(), ["e1", "e2", "e4"])
  m.place("zz")
  assert.deepEqual(m.line(), ["e3"], "an id that is not a tile is ignored")
  m.clear()
  assert.deepEqual(m.line(), [])
})

test("ordering: Su and Giù move one item, never out of the list", () => {
  const m = createOrdering(["e1", "e2", "e3"])
  m.move("e1", -1)
  assert.deepEqual(m.order(), ["e1", "e2", "e3"])
  m.move("e1", 1).move("e1", 1)
  assert.deepEqual(m.order(), ["e2", "e3", "e1"])
  m.move("e1", 1)
  assert.deepEqual(m.order(), ["e2", "e3", "e1"])
})

test("select: an arrow goes to the nearest target that way; with none that way the focus stays", () => {
  //  0 1 2
  //  3 4 5
  const boxes = [0, 1, 2, 3, 4, 5].map((i) => ({ x: (i % 3) * 100, y: Math.floor(i / 3) * 100, w: 40, h: 40 }))
  assert.equal(nearest(boxes, 0, "right"), 1)
  assert.equal(nearest(boxes, 1, "right"), 2)
  assert.equal(nearest(boxes, 2, "right"), 2)
  assert.equal(nearest(boxes, 4, "up"), 1)
  assert.equal(nearest(boxes, 1, "down"), 4)
  assert.equal(nearest(boxes, 4, "down"), 4)
  assert.equal(nearest(boxes, 4, "left"), 3)
  // straight ahead beats nearer but off to the side
  const odd = [{ x: 0, y: 0, w: 10, h: 10 }, { x: 60, y: 90, w: 10, h: 10 }, { x: 200, y: 0, w: 10, h: 10 }]
  assert.equal(nearest(odd, 0, "right"), 2, "straight ahead, 200 away, beats one that is 60 along but 90 across (score along + 2 x across: 200 against 240)")
})

test("select: a target is read as 'zona n di N' with the neutral description, never a name", () => {
  assert.equal(targetLabel("zona %{n} di %{total}", 3, 12, "a nord-ovest"), "zona 3 di 12, a nord-ovest")
  assert.equal(targetLabel("zona %{n} di %{total}", 3, 12), "zona 3 di 12")
})

const body = {
  cards: [
    { n: 1, level: "core", blocks: [{ n: 1, type: "text" }, { n: 2, type: "check", component: "tiles" }] },
    { n: 2, level: "core", blocks: [{ n: 1, type: "example", steps: [{ blank: { component: "choice" } }, { blank: { component: "select", diagram: { type: "network" } } }] }] },
    { n: 3, level: "core", blocks: [{ n: 1, type: "try", exercises: [{ n: 1, checks: [{ component: "ordering" }, { component: "tiles" }] }, { n: 2, check: { component: "number" } }] }] },
    { n: 9, level: "extra", blocks: [{ n: 1, type: "more", blocks: [{ n: 1, type: "check", component: "select", diagram: { type: "map" } }] }] }
  ]
}

test("how-to: the first use of each component in the order of the cards, at the address the check endpoint uses", () => {
  const first = firstUses(body)
  assert.equal(first.get("tiles"), locKey({ card: 1, block: 2 }))
  assert.equal(first.get("select"), locKey({ card: 2, block: 1, step: 2 }))
  assert.equal(first.get("ordering"), locKey({ card: 3, block: 1, ex: 1, part: 1 }))
  assert.equal(first.has("choice"), false)
  assert.equal(locKey({ card: 2, block: 1, step: 2 }), "2/1/2//")
})

test("how-to: select has one line for one tap and one for several", () => {
  assert.equal(howtoKey({ component: "select", pick: "one" }), "select_one")
  assert.equal(howtoKey({ component: "select", pick: "many" }), "select_many")
  assert.equal(howtoKey({ component: "tiles" }), "tiles")
  assert.equal(howtoKey({ component: "number" }), null)
})

test("preload: the diagram types and the components a body uses, a select check's figure included", () => {
  const { types, components } = usedBy({ ...body, hero: { type: "balance" } })
  assert.deepEqual([...types].sort(), ["balance", "map", "network"])
  assert.deepEqual([...components].sort(), ["choice", "number", "ordering", "select", "tiles"])
})

test("preload: an oral loads the ordering component its outline is put in order with (D-311)", () => {
  const oral = { cards: [{ n: 1, blocks: [{ type: "oral", question_it: "Spiega.", outline: [{ id: "e1", text_it: "Uno" }, { id: "e2", text_it: "Due" }] }] }] }
  assert.deepEqual([...usedBy(oral).components], ["ordering"])
})

test("teacher: tiles read as the built sentence, an ordering as its items joined by arrows, a select by the names of its targets", () => {
  const tiles = { component: "tiles", tiles: [{ id: "a", text_en: "If" }, { id: "b", text_en: "it" }, { id: "c", text_en: "rains" }] }
  assert.equal(sequenceText(tiles, ["a", "b", "c"]), "If it rains")
  const order = { component: "ordering", items: [{ id: "p", text_it: "La proposta" }, { id: "q", text_it: "Il voto" }] }
  assert.equal(sequenceText(order, ["p", "q"]), "La proposta → Il voto")
  // no available type has targets yet: the ids stand in for the names
  assert.deepEqual(targetNames({ diagram: { type: "table" }, targets: "cells" }, ["c1.nucleoid"]), ["c1.nucleoid"])
})

const { layout, describe } = await import("lesson/diagrams/registry")
const english = {
  type: "sentence", alt_it: "La frase She reads a book con il soggetto, il verbo e il complemento oggetto colorati.", text_en: "She reads a book",
  parts: [{ id: "s", text_en: "She", role: "subject" }, { id: "v", text_en: "reads", role: "verb" }, { id: "o", text_en: "a book", role: "object" }]
}
const measure = (text, px) => ({ w: Math.ceil(String(text).length * px * 0.5), h: Math.ceil(px * 1.4) })

test("sentence neutral: layout centre joins the parts to the verb, the centre role of english; the target-language labels carry lang", () => {
  const scene = layout({ ...english, layout: "centre" }, { width: 900, fontPx: 20, subject: "english", measure, state: 0 })
  assert.ok(!scene.error, scene.error?.message)
  assert.ok(scene.shapes.some((s) => s.key === "edge:s") && scene.shapes.some((s) => s.key === "edge:o"), "the subject and the object are joined to the verb")
  assert.ok(scene.shapes.some((s) => String(s.cls).includes("st-verb")), "the verb is the boxed centre")
  const text = scene.labels.find((l) => l.key === "part:v:text")
  assert.equal(text.lang, "en")
  assert.equal(text.text_it, "reads")
})

test("sentence neutral: an italian sentence has no lang and centres on the predicate", () => {
  const { text_en, ...rest } = english
  const it = { ...rest, text_it: "Marco legge un libro", parts: [{ id: "s", text_it: "Marco", role: "subject" }, { id: "v", text_it: "legge", role: "predicate" }, { id: "o", text_it: "un libro", role: "object" }] }
  const scene = layout({ ...it, layout: "centre" }, { width: 900, fontPx: 20, subject: "italian", measure, state: 0 })
  assert.ok(!scene.error, scene.error?.message)
  assert.equal(scene.labels.find((l) => l.key === "part:v:text").lang, undefined)
  assert.ok(scene.shapes.some((s) => String(s.cls).includes("st-predicate")))
})

test("sentence neutral: the description reads the lesson subject's palette", () => {
  assert.match(describe(english, { subject: "english" }), /«reads» è verbo/)
  assert.match(describe(english, { subject: "english" }), /«She» è soggetto/)
  assert.match(describe({ type: "sentence", alt_it: english.alt_it, text_it: "Marco legge", parts: [{ id: "v", text_it: "legge", role: "predicate" }] }), /«legge» è predicato/, "the default stays italian")
})

test("teacher: a select answer is read by the names the type gives its targets (name_it), never by tN", async () => {
  const { TYPES } = await import("lesson/diagrams/registry")
  TYPES.probe = { layout: () => ({ error: { path: "", message: "x", code: "E-LESSON-DIAGRAM" } }), describe: () => "", targets: () => [{ key: "z1", neutral_it: "in alto" }, { key: "z2", neutral_it: "in basso", name_it: "nucleoide" }, { key: "z3", name_it: "ribosomi" }] }
  try {
    const spec = { component: "select", diagram: { type: "probe" }, targets: "zones", pick: "many", answer: ["z2", "z3"] }
    assert.deepEqual(targetNames(spec, spec.answer), ["nucleoide", "ribosomi"])
    assert.deepEqual(targetNames(spec, ["z1"]), ["z1"], "a target without a name shows its id")
  } finally {
    delete TYPES.probe
  }
})
